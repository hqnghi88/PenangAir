/***
* Name: mainroadcells
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model main

import "agents/traffic.gaml"
import "agents/pollution.gaml"
import "agents/fire.gaml"
import "agents/policy.gaml"
import "agents/visualization.gaml"
global {
	//	list<pollutant_grid> active_cells;
	init {
		// Built here rather than at declaration time: the world projection is
		// not ready before init, so a declaration-time conversion can land
		// the study box off the network.
		site_merc <- to_GAMA_CRS(site_4326, "EPSG:4326").location;
		study_area <- square(2.0 * study_half_size) at_location site_merc;
		write "Study area: " + string(int(2.0 * study_half_size)) + " m x "
		    + string(int(2.0 * study_half_size)) + " m centred on the site.";

		if (simType = 0) {
			// The shapefile carries NAME and HIGHWAY columns, which is what
			// lets the survey CSV be matched street by street. Reading them
			// explicitly, because `create from:` would not map a shapefile
			// column onto a species attribute of the same name.
			loop geom over: roads_shape_file {
				string nm <- string(geom get ("NAME"));
				string hw <- string(geom get ("HIGHWAY"));
			create road(shape: geom, road_name: nm, highway: hw) {
				if (self.shape.perimeter < 1.0) {
					do die; }
				// Even-odd designation: ~30% even-only, ~30% odd-only,
				// the rest open every day.
				float roll <- rnd(1.0);
				parity_restriction <- roll < 0.3 ? 0 : (roll < 0.6 ? 1 : -1);
			}
			}

			// Only the study area is measured and reported, so drop the segments
			// outside it before building the routing graph. Doing it here, not
			// after, avoids seeding vehicles on roads that are about to vanish.
			list<road> in_study <- list<road>(road where (study_area covers each.shape));
			ask (road - in_study) {
				do die; }
			write "Roads: " + string(length(in_study)) + " of the shapefile segments lie inside the study area.";

			// Cropping to the study box cuts streets at the border and leaves
			// isolated fragments. Vehicles seeded on a fragment can never
			// route out, so they sit still forever: keep only the main
			// connected component before the routing graph is built.
			graph full_network <- as_edge_graph(road);
			list main_roads <- [];
			loop comp over: connected_components_of(full_network, true) {
				if (length(comp) > length(main_roads)) {
					main_roads <- list(comp); }
			}
			int dropped_roads <- length(road) - length(main_roads);
			if (dropped_roads > 0) {
				ask (road - main_roads) {
					do die; }
			}
			write "Road network: " + string(length(main_roads)) + " segments kept in the main"
			    + " component, " + string(dropped_roads) + " isolated fragments removed.";

			//Weights of the road
			road_weights <- road as_map (each :: each.shape.perimeter);
			road_network <- as_edge_graph(road);

			create study_boundary with: [shape :: study_area];
			// Additional visualization
			create building from: buildings_shape_file {
				depth <- (rnd(100) / 100) * (rnd(100) / 100) * (rnd(100) / 100 * 10) * 5 + 10;
				texture <- textures[rnd(9)];
			}
		}

		if (use_traffic_data = 1) {
			do load_traffic_counts;
		} else {
			create car_random number: 50 with: [type:: "car"];
			create motorbike_random number: 50 with: [type:: "motorbike"];
			create bus_random number: 50 with: [type:: "bus"];
			create lorry_random number: 50 with: [type:: "lorry"]; 
		}
		string traffic_source <- use_traffic_data = 1 ? "REAL (traffic_counts.csv)" : "RANDOM (default fleet)";
		write "Traffic source: " + traffic_source;
		if (length(param_indicator where (each.name = lb_TrafficSource)) > 0) {
			ask first(param_indicator where (each.name = lb_TrafficSource)) {
				do update(traffic_source);
			}
		}
		if (fire_enabled and length(fire_source) = 0) {
			create fire_source number: nb_fires with: [location::any_location_in(study_area)];
		}
	}

	// ==================================================================
	// TRAFFIC COUNTS -> FLEET
	// ==================================================================
	// The demonstration description asks for the real Penang traffic volume,
	// mixed across buses, cars, lorries and motorcycles, plugged into the
	// simulation. includes/traffic_counts.csv holds those counts (peak-hour
	// one-way flows in veh/h); this action turns them into agents.
	//
	// A road never holds as many vehicles at once as pass through it in an
	// hour, so Little's Law gives the fleet:
	//
	//     vehicles on a road = surveyed flow (veh/h) x crossing time (h)
	//
	// and crossing time for a segment of length L at speed v is L / v. The
	// shapefile splits a street into many short segments, so each segment
	// gets its share of the crossing time, with the leftover fraction carried
	// to the next segment rather than rounded away.
	//
	// Column order in the CSV is positional and must not change:
	//   0 road_name, 1 highway, 2 length_m, 3 cars, 4 buses, 5 lorries,
	//   6 motorcycles. length_m is informational; each segment already knows
	//   its own length.
	int count_of(string s) {
		if (s = nil) {
			return 0; }
		string t <- trim(s);
		if (t = "") {
			return 0; }
		return int(t);
	}

	action load_traffic_counts(){
		file counts_file <- csv_file("../includes/traffic_counts.csv", true);
		matrix counts <- matrix(counts_file);
		int first_row <- 0;
		if (string(counts[0, 0]) = "road_name") { first_row <- 1; }

		map<string, int> cars_by_name <- map<string, int>();
		map<string, int> buses_by_name <- map<string, int>();
		map<string, int> lorries_by_name <- map<string, int>();
		map<string, int> bikes_by_name <- map<string, int>();

		// Per-class sums and segment counts, so an unnamed lane can fall back
		// to the mean of its own road class instead of to nothing.
		map<string, int> cars_by_class <- map<string, int>();
		map<string, int> buses_by_class <- map<string, int>();
		map<string, int> lorries_by_class <- map<string, int>();
		map<string, int> bikes_by_class <- map<string, int>();
		map<string, int> segments_by_class <- map<string, int>();

		// `from: a to: b` runs backwards when a > b, so guard the loop or an
		// empty table executes twice instead of never.
		if (counts.rows > first_row) {
			loop i from: first_row to: counts.rows - 1 {
				string nm <- string(counts[0, i]);
				string hw <- string(counts[1, i]);
				int c_n <- count_of(string(counts[3, i]));
				int b_n <- count_of(string(counts[4, i]));
				int l_n <- count_of(string(counts[5, i]));
				int m_n <- count_of(string(counts[6, i]));

				cars_by_name[nm] <- c_n;
				buses_by_name[nm] <- b_n;
				lorries_by_name[nm] <- l_n;
				bikes_by_name[nm] <- m_n;

				// `k in some_map` tests VALUES in GAMA, not keys, so
				// membership has to be tested against the .keys list.
				bool have_class <- hw in segments_by_class.keys;
				if (have_class) {
					segments_by_class[hw] <- segments_by_class[hw] + 1;
					cars_by_class[hw] <- cars_by_class[hw] + c_n;
					buses_by_class[hw] <- buses_by_class[hw] + b_n;
					lorries_by_class[hw] <- lorries_by_class[hw] + l_n;
					bikes_by_class[hw] <- bikes_by_class[hw] + m_n;
				} else {
					segments_by_class[hw] <- 1;
					cars_by_class[hw] <- c_n;
					buses_by_class[hw] <- b_n;
					lorries_by_class[hw] <- l_n;
					bikes_by_class[hw] <- m_n;
				}
			}
		}

		list<geometry> car_spots <- list<geometry>();
		list<geometry> bike_spots <- list<geometry>();
		list<geometry> bus_spots <- list<geometry>();
		list<geometry> lorry_spots <- list<geometry>();

		// Fractional carry between segments: rounding each short segment down
		// would quietly delete most of the fleet.
		float carry_car <- 0.0;
		float carry_bike <- 0.0;
		float carry_bus <- 0.0;
		float carry_lorry <- 0.0;

		int matched_roads <- 0;
		int default_roads <- 0;

		loop r over: road {
			bool named <- (r.road_name != nil) and (r.road_name != "")
			    and (r.road_name in cars_by_name.keys);
			if (named) { matched_roads <- matched_roads + 1; } else { default_roads <- default_roads + 1; }

			int c_vol <- 0;
			int b_vol <- 0;
			int l_vol <- 0;
			int m_vol <- 0;
			if (named) {
				c_vol <- cars_by_name[r.road_name];
				b_vol <- buses_by_name[r.road_name];
				l_vol <- lorries_by_name[r.road_name];
				m_vol <- bikes_by_name[r.road_name];
			} else {
				bool counted <- r.highway in segments_by_class.keys;
				int n_seg <- counted ? segments_by_class[r.highway] : 1;
				c_vol <- counted ? int(cars_by_class[r.highway] / n_seg) : 100;
				b_vol <- counted ? int(buses_by_class[r.highway] / n_seg) : 4;
				l_vol <- counted ? int(lorries_by_class[r.highway] / n_seg) : 8;
				m_vol <- counted ? int(bikes_by_class[r.highway] / n_seg) : 90;
			}

			float crossing_h <- (r.shape.perimeter / 1000.0) / class_speed_of(r.highway);

			float raw_car <- c_vol * crossing_h * fleet_scale + carry_car;
			float raw_bike <- m_vol * crossing_h * fleet_scale + carry_bike;
			float raw_bus <- b_vol * crossing_h * fleet_scale + carry_bus;
			float raw_lorry <- l_vol * crossing_h * fleet_scale + carry_lorry;

			int n_car <- int(raw_car);
			int n_bike <- int(raw_bike);
			int n_bus <- int(raw_bus);
			int n_lorry <- int(raw_lorry);
			carry_car <- raw_car - n_car;
			carry_bike <- raw_bike - n_bike;
			carry_bus <- raw_bus - n_bus;
			carry_lorry <- raw_lorry - n_lorry;

			// The n > 0 guards matter: `from: 1 to: 0` executes twice.
			if (n_car > 0) { loop j from: 1 to: n_car { add item: r.shape to: car_spots; } }
			if (n_bike > 0) { loop j from: 1 to: n_bike { add item: r.shape to: bike_spots; } }
			if (n_bus > 0) { loop j from: 1 to: n_bus { add item: r.shape to: bus_spots; } }
			if (n_lorry > 0) { loop j from: 1 to: n_lorry { add item: r.shape to: lorry_spots; } }
		}

		// Keep the demo interactive on modest workshop hardware. Scaling every
		// class by the same factor preserves the surveyed vehicle mix.
		int total_spots <- length(car_spots) + length(bike_spots)
		                + length(bus_spots) + length(lorry_spots);
		write "Survey counts: " + string(matched_roads) + " segments matched a street name, "
		    + string(default_roads) + " used class defaults | raw spots: " + string(total_spots)
		    + " (cars " + string(length(car_spots)) + ", bikes " + string(length(bike_spots))
		    + ", buses " + string(length(bus_spots)) + ", lorries " + string(length(lorry_spots)) + ")";
		if (total_spots > max_vehicles and total_spots > 0) {
			float cap <- max_vehicles * 1.0 / total_spots;
			car_spots <- keep_leading(car_spots, int(length(car_spots) * cap));
			bike_spots <- keep_leading(bike_spots, int(length(bike_spots) * cap));
			bus_spots <- keep_leading(bus_spots, int(length(bus_spots) * cap));
			lorry_spots <- keep_leading(lorry_spots, int(length(lorry_spots) * cap));
		}

		create car_random from: car_spots with: [type:: "car"];
		create motorbike_random from: bike_spots with: [type:: "motorbike"];
		create bus_random from: bus_spots with: [type:: "bus"];
		create lorry_random from: lorry_spots with: [type:: "lorry"];

		max_cars <- max(1, length(car_random));
		max_motorbikes <- max(1, length(motorbike_random));
		max_bus <- max(1, length(bus_random));
		max_lorries <- max(1, length(lorry_random));

		// The bars are created by the entry point's init, which runs before
		// this one, so each one copied max_cars and friends while they still
		// held their declaration defaults of 1000/500/500/500. max_val is a
		// copy, not a reference, so without this the bars keep dividing by
		// 1000: setting every car electric would read as 29% instead of
		// 100%. Push the real fleet sizes in now that they are known.
		if (length(progress_bar) > 0) {
			ask first(progress_bar where (each.title = lb_rates_EG)) {
				max_val <- max_cars + max_bus + max_motorbikes + max_lorries;
			}
			ask first(progress_bar where (each.title = lb_cars)) { max_val <- max_cars; }
			ask first(progress_bar where (each.title = lb_motobike)) { max_val <- max_motorbikes; }
			ask first(progress_bar where (each.title = lb_bus)) { max_val <- max_bus; }
			ask first(progress_bar where (each.title = lb_lorries)) { max_val <- max_lorries; }
		}

		// Confirm the bars are now scaled against the real fleet. Every
		// max_val here must match the fleet size printed just below; if one
		// is still 1000/500 the bar percentages will read low.
		ask progress_bar {
			write ("bar '" + title + "' max_val=" + string(max_val));
		}

		write "Fleet from traffic_counts.csv: " + string(max_cars) + " cars, "
		    + string(max_motorbikes) + " motorbikes, " + string(max_bus) + " buses, "
		    + string(max_lorries) + " lorries.";
	}

	// First n elements of a list, as a new list, so the fleet can be scaled
	// down to the cap while preserving the order segments were added in.
	list<geometry> keep_leading(list<geometry> source, int n) {
		list<geometry> out <- list<geometry>(); 
		int last <- min(n, length(source)) - 1;
		if (last >= 0) {
			loop i from: 0 to: last {
				add item: source[i] to: out; }
		}
		return out;
	}

	// Free-flow speed by road class (km/h), the divisor in the Little's Law
	// crossing time. Unlisted classes fall back to 25.
	float class_speed_of(string highway) {
		if (highway = "motorway") {
			return 80.0; }
		if (highway = "trunk") {
			return 50.0; }
		if (highway = "primary") {
			return 40.0; }
		if (highway = "secondary") {
			return 35.0; }
		if (highway = "tertiary") {
			return 30.0; }
		if (highway = "living_street") {
			return 15.0; }
		return 25.0;
	}

	reflex update_time {
		int h <- current_date.hour;
		int m <- current_date.minute;
		int s <- current_date.second;
		string hh <- ((h < 10) ? "0" : "") + string(h);
		string mm <- ((m < 10) ? "0" : "") + string(m);
		string ss <- ((s < 10) ? "0" : "") + string(s);
		string t <- "" + date("now"); // hh + ":" + mm + ":" + ss;
		ask (param_indicator where (each.name = lb_Time)) {
			do update(t);
		}
	}

	// These four reflexes (congestion, real-calendar parity, the even-odd
	// gate and the even-odd chart feed) used to live in traffic.gaml's
	// global block — but reflexes of an imported file's global do not run
	// when `main` is the active model (the reason pollution.gaml's `diff`
	// had to move here too). While they sat there they were dead code:
	// no vehicle was ever parked or turned back, congestion never changed
	// and the even-odd charts stayed flat no matter what the buttons did.
	// Moved verbatim into main's global, whose reflexes do tick.

	reflex update_congestion when: every(5 #cycle) {
		// Weighted load per road: a lorry takes ~3x the space of a car and
		// a bus ~2x, a motorbike ~0.4x. congestion is load clamped to
		// capacity, and speed_coeff (12 = free flow) follows it.
		ask road {
			float load <- length((car_random where (each.active_today)) overlapping (shape + 12.0)) * 1.0
			            + length((motorbike_random where (each.active_today)) overlapping (shape + 12.0)) * 0.4
			            + length((bus_random where (each.active_today)) overlapping (shape + 12.0)) * 2.0
			            + length((lorry_random where (each.active_today)) overlapping (shape + 12.0)) * 3.0;
			congestion <- min(1.0, load / capacity);
			// The colour driver eases towards its new level (25% per update)
			// so the ramp on the map drifts instead of flickering; congestion
			// itself stays exact for routing, emissions and re-routing.
			speed_coeff <- speed_coeff + 0.25 * (max(0.6, 12.0 * (1.0 - congestion)) - speed_coeff);
		}
		float total <- 0.0;
		loop r over: road {
			total <- total + r.congestion;
		}
		network_congestion <- total / max(1, length(road));

		// Route weights penalise congested segments, so every vehicle that
		// recomputes its path prefers the free-flow alternative.
		road_weights <- road as_map (each :: each.shape.perimeter * (1.0 + 4.0 * each.congestion));

		// Per-vehicle congestion level, used for both the emission penalty
		// in main.gaml and the speed reduction below. Union of the four
		// concrete fleet subtypes — the bare parent name is empty.
		list<vehicle_random> fleet <- [] + car_random + motorbike_random + bus_random + lorry_random;
		ask fleet { current_congestion <- 0.0; }
		loop r over: road {
			if (r.congestion > 0.0) {
				ask fleet overlapping (r.shape + 12.0) {
					current_congestion <- max(current_congestion, r.congestion);
				}
			}
		}
		ask (param_indicator where (each.name = lb_NetworkCongestion)) {
			do update(string(int(network_congestion * 100)) + "%");
		}
	}

	// The even/odd switch follows the real calendar: parity is the day of
	// month of the actual current date (date("now")), not a cycle counter,
	// so the model always agrees with the clock on the wall. The panel
	// shows the day-of-month it is using.
	reflex advance_day {
		date today <- date("now");
		odd_today <- (today.day mod 2 = 1);
		string pol_str <- active_policies_string();
		if (pol_even_odd) {
			pol_str <- pol_str + "[day " + string(today.day) + (odd_today ? " odd" : " even") + "]";
		}
		ask (param_indicator where (each.name = lb_ActivePolicies)) {
			do update(pol_str);
		}
	}

	// Even-odd day rule, road level: only the designated subset of streets
	// is denied each day, never the whole network. road.parity_restriction
	// is -1 (open), 0 (even-only) or 1 (odd-only). A non-payer may stand on
	// restricted road R only when R matches BOTH today's parity and its own
	// plate; otherwise it waits (grey, speed 0, no load, no emissions) until
	// that parity's day comes round again — or, if the road can never admit
	// it (plate mismatch), it is turned back to the nearest admissible road.
	// Road-tax payers ignore the rule entirely. Incident dummy cars are
	// exempt so they still reach their target and die as designed.
	reflex even_odd_gate when: every(5 #cycle) {
		// The fleet is created as the four concrete subtypes; the bare
		// parent name does not enumerate them, so every fleet-wide ask
		// builds the union explicitly (same pattern as even_odd_stats).
		list<vehicle_random> fleet <- [] + car_random + motorbike_random + bus_random + lorry_random;
		if (not pol_even_odd) {
			ask (fleet where (each.active_today = false and not (each.should_die = true))) {
				active_today <- true;
			}
		} else {
			int d <- odd_today ? 1 : 0;
			ask (fleet where (not (each.should_die = true))) {
				if (road_tax_paid) {
					active_today <- true;
				} else {
					road r <- road closest_to self;
					bool ok <- (r = nil) or (r.parity_restriction = -1)
					    or (r.parity_restriction = d and r.parity_restriction = plate_parity);
					if (ok) {
						active_today <- true;
					} else if (r.parity_restriction = plate_parity) {
						// Own-parity road: it reopens on that parity's day.
						active_today <- false;
					} else {
						// Never admissible for this plate: turn back to a
						// road we may use and re-target there. Stamp the
						// event so the chart can count enforcement hits.
						last_turnback_at <- time;
						list<road> admissible <- road where (each.parity_restriction = -1 or each.parity_restriction = plate_parity);
						if (length(admissible) > 0) {
							road safe <- admissible closest_to self;
							location <- any_location_in(safe);
							target <- any_location_in(safe);
						}
						active_today <- true;
					}
				}
			}
		}
	}

	// Chart feed for the even-odd statistics. Runs every cycle rather
	// than with the gate, so the chart lines move continuously instead of
	// stepping every 5 cycles. Pure attribute filters — no enclosing
	// local is mutated from inside an ask. Meaningful both ways: with
	// the rule off it is the baseline (everyone driving, no turn-backs),
	// with it on the series step, ramp and spike as the rule bites.
	reflex even_odd_stats {
		list<vehicle_random> all<-[]+car_random+motorbike_random+bus_random+lorry_random;
		nb_fleet <- length(all where (not (each.should_die = true)));
		nb_even_active <- length(all where (not (each.should_die = true) and each.active_today and each.plate_parity = 0));
		nb_odd_active <- length(all where (not (each.should_die = true) and each.active_today and each.plate_parity = 1));
		nb_even_waiting <- length(all where (not (each.should_die = true) and each.active_today = false and each.plate_parity = 0));
		nb_odd_waiting <- length(all where (not (each.should_die = true) and each.active_today = false and each.plate_parity = 1));
		nb_turnbacks <- length(all where (not (each.should_die = true) and each.last_turnback_at > time - 5));
		list<vehicle_random> driving_set <- all where (not (each.should_die = true) and each.active_today);
		mean_speed_kmh <- (length(driving_set) = 0) ? 0.0 : mean(driving_set collect each.speed) * 3.6;
	}

	reflex calculate_aqi when: every(refreshing_rate_plot) { // every(1 #minute) {
		float aqi <- max(instant_heatmap);
		ask line_graph_aqi {
			do update(aqi * 10); 
		}
	// ask indicator_health_concern_level {
	// do update(aqi);
	// }
	}

	action update_vehicle_population (string type, int delta) {
		if (type = "motorbike") {
			ask motorbike_random {
				is_electrical <- false;
			}

			ask n_motorbikes among motorbike_random {
				is_electrical <- true;
			}

		}

		if (type = "car") {
			ask car_random {
				is_electrical <- false;
			}

			ask n_cars among car_random {
				is_electrical <- true;
			} 
		}

		if (type = "bus") {
		ask bus_random {
			is_electrical <- false;
		}

		ask n_bus among bus_random {
			is_electrical <- true;
		}

		}
	
		if (type = "lorry") {
			ask lorry_random {
				is_electrical <- false;
			}
	
			ask n_lorries among lorry_random {
				is_electrical <- true;
			}
	
		}

	}

	reflex update_car_population when: n_cars != n_cars_prev {
		// int delta_cars <- n_cars - n_cars_prev;
		do update_vehicle_population("car", n_cars);
		ask first(progress_bar where (each.title = lb_cars)) {
			do update(float(n_cars));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes + n_lorries)));
		}

		n_cars_prev <- n_cars;
	}

	reflex update_motorbike_population when: n_motorbikes != n_motorbikes_prev {
		// int delta_motorbikes <- n_motorbikes - n_motorbikes_prev;
		do update_vehicle_population("motorbike", n_motorbikes);
		ask first(progress_bar where (each.title = lb_motobike)) {
			do update(float(n_motorbikes));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes + n_lorries)));
		}

		n_motorbikes_prev <- n_motorbikes;
	}

	reflex update_bus_population when: n_bus != n_bus_prev {
		do update_vehicle_population("bus", n_bus);
		ask first(progress_bar where (each.title = lb_bus)) {
			do update(float(n_bus));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes + n_lorries)));
		}

		n_bus_prev <- n_bus;
	}

	reflex update_lorry_population when: n_lorries != n_lorries_prev {
		do update_vehicle_population("lorry", n_lorries);
		ask first(progress_bar where (each.title = lb_lorries)) {
			do update(float(n_lorries));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes + n_lorries)));
		}

		n_lorries_prev <- n_lorries;
	}
 
	// Stations come from the live feed over the full world extent, but the
	// model only measures inside the study area, so the ones outside it are
	// dropped rather than colouring an area that was never surveyed.
	reflex trim_ambient when: every(10#s) {
		list<AQI> outside <- list<AQI>(AQI where (not (study_area covers each.shape)));
		if (length(outside) > 0) {
			ask outside {
				do die;
			}
		} 
	}

	reflex update {
		// Decay the heat map so traffic contributions have a finite memory (this
		// step used to be commented out, so the field could only grow and the
		// measured ambient value could not be added without flooding it), then
		// inject the measured regional PM2.5 as a uniform background. The
		// background settles at ~ambient_pm25; vehicle emissions sit on top.
		float ambient_decay <- 0.02;
		instant_heatmap <- instant_heatmap * (1.0 - ambient_decay);
		// Seed the measured ambient reading only for the first 10 cycles:
		// adding it every cycle floods the field to a uniform value and the
		// whole map becomes one flat colour. After the seeding window it
		// decays away and only the traffic gradient remains.
		if (cycle_count < 10 and ambient_pm25 > 0) {
			instant_heatmap[site_merc] <- instant_heatmap[site_merc] + ambient_pm25 * AMBIENT_SCALE;
		}else{	
			cycle_count <- 0;
		}
		cycle_count <- cycle_count + 1;
		// Lorries join the emission: they are in the survey counts and their
		// PM/NOx factors sit an order of magnitude above a car's.
		ask car_random + motorbike_random + bus_random + lorry_random + dummy_car {
			// Emission is driven by the per-kilometre factors in pollution.gaml,
			// not by each species' arbitrary `aqh`. Those were inherited from
			// Hanoi, where a car emitted up to six times more than a lorry and a
			// bus almost nothing, so the heat map contradicted the very factors
			// the model quotes: lorries and buses now read as the heavy
			// contributors the survey and EMISSION_FACTOR describe.
			string kind <- (type != nil and type in EMISSION_FACTOR.keys) ? type : "car";
			// Congested/idling traffic emits more per cycle: multiply by
			// (1 + current_congestion). LEZ-modernised vehicles are halved.
			// Parked vehicles (even-odd rule, off-day) emit nothing.
			float factor <- (EMISSION_FACTOR[kind]["PM"] + EMISSION_FACTOR[kind]["NOx"])
			              * (modernized ? 0.5 : 1.0)
			              * (1.0 + current_congestion)
			              * (active_today ? 1.0 : 0.0);
			instant_heatmap[location] <- instant_heatmap[location] + (is_electrical ? 0.1 : 1.0) * factor * 3.0 * EMISSION_SCALE;
		}
	} 

	// Realistic wind: every 10 cycles the breeze veers a little (random
	// walk in direction) and gusts in strength, so plumes wander instead
	// of streaming one fixed way. wind_matrix in pollution.gaml rebuilds
	// the diffusion kernel from these two numbers each cycle.
	reflex vary_wind when: every(10 #cycle) {
		wind_angle <- wind_angle + rnd(-12.0, 12.0);
		wind_strength <- min(0.65, max(0.15, wind_strength + rnd(-0.07, 0.07)));
	}

	// Spread the heat map to neighbouring cells every cycle. The `diff` reflex
	// that used to do this sits inside the pollution model's own global block
	// (pollution.gaml), which does not run when `main` is the active model, so
	// without this the field stayed flat. The kernel is 5x5: ~30% stays in
	// place, the rest travels up to two cells away — leaning towards the
	// wandering wind while the Wind policy is on, symmetric when it is off.
	reflex spread {
		diffuse "phero" on: instant_heatmap matrix: (pol_wind ? wind_matrix(wind_angle, wind_strength) : mat_diff_calm);
	}

	// Fire maintenance, moved verbatim from fire.gaml's global block for
	// the same reason as `spread`: reflexes of an imported file's global do
	// not run when `main` is the active model. Fires are (re)seeded here
	// rather than in an init block: study_area is only built in this
	// init, so creating agents earlier would see a nil study_area. Every
	// creation passes an explicit location inside the study box.
	reflex maintain_fires when: every(5 #cycle) {
		if (not fire_enabled) {
			ask fire_source { do die; }
		} else {
			// Ignition: top up towards the target population, slowly.
			if (length(fire_source) < nb_fires and length(fire_source) < max_fires and flip(fire_ignite_rate)) {
				create fire_source with: [location::any_location_in(study_area)];
			}
			// Spread: an established fire may throw a new one nearby.
			// Fire suppression (policy) cuts the chance. Iterating a
			// snapshot so fires created here are not visited in the same
			// pass, which would needlessly re-seed from them.
			float spread_scale <- pol_fire_suppression ? 0.2 : 1.0;
			list<fire_source> snapshot <- list<fire_source>(fire_source);
			loop f over: snapshot {
				if (length(fire_source) < max_fires and flip(fire_spread_rate * spread_scale)) {
					point cand <- f.location + {rnd(-fire_radius * 2, fire_radius * 2), rnd(-fire_radius * 2, fire_radius * 2)};
					if (study_area covers cand) {
						create fire_source with: [location::cand];
					}
				}
			}
		}
		ask (param_indicator where (each.name = lb_ActiveFires)) {
			do update(string(length(fire_source)));
		}
	}

	// Live congestion incidents, derived from the simulated load per
	// road (the old commented-out API version is gone, so the triangle
	// markers now track real modelled queues). Old markers are cleared
	// first so incidents do not accumulate.
	reflex congestion_incidents when: every(100 #cycle) {
		ask traffic_incident {
			do die;
		}
		list<road> ordered <- list<road>(road sort_by (each.congestion));
		int made <- 0;
		if (length(ordered) > 0) {
			loop k from: 0 to: length(ordered) - 1 {
				road r <- ordered[length(ordered) - 1 - k];
				if (r.congestion >= 0.6 and made < 5) {
					create traffic_incident with: [
						location::r.shape.location,
						description::("congestion " + string(int(r.congestion * 100)) + "%")
					];
					made <- made + 1;
				}
			}
		}
		ask (param_indicator where (each.name = lb_Traffic_Incident)) {
			do update(string(made) + " congestion incidents @ " + date("now"));
		}
	}
}
 
// The 2 km box the survey counts are restricted to. Drawn so the audience can
// see what was measured. The old `boundary` species in visualization.gaml
// disappears after one cycle and cannot do that. 
species study_boundary {
	geometry shape;

	aspect default {
		// Outline only. Filling 4 km2 of translucent white would wash out the
		// very heat map the box frames, and `draw` in this GAMA version takes
		// no `transparency` facet while `border` wants an rgb or a bool, not a
		// thickness. The buffered second contour is what gives the line weight.
		draw shape.contour color: #white;
		draw shape.contour + 3 color: #white;
	}
}
