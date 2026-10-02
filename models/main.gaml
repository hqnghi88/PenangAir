/***
* Name: mainroadcells
* Author: minhduc0711
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model main

import "agents/traffic.gaml"
import "agents/pollution.gaml"
import "agents/visualization.gaml"

global {

// Benchmark execution time 
	float step <- 1 #s;
	// Load shapefiles  
	// Penang data (see Scale3.gaml header): George Town study box, EPSG:3857.
	shape_file roads_shape_file <- shape_file("../includes/penang_roads.shp");
	shape_file buildings_shape_file <- shape_file("../includes/penang_buildings.shp");
	// Penang: Hanoi intersections file removed (declared but never used).
	// shape_file intersect0_shape_file <- shape_file("../includes/bigger_map/inter.shp");
	geometry shape <- envelope(roads_shape_file);

	// ==================================================================
	// STUDY AREA
	// ==================================================================
	// The demonstration description asks for a study area around the site
	// that is large enough to show traffic interactions but not needlessly
	// complex for the workshop. Half-width 1000 m gives 2 km x 2 km, which
	// holds a real junction and its approaches while staying legible on a
	// projected screen. Exposed as an experiment parameter (300-3000 m) so
	// the size can be argued with the team on the day.
	point site_4326 <- {100.316083, 5.409611};
	point site_merc;
	float study_half_size <- 1000.0;
	geometry study_area;
	//	list<road> open_roads;
	float traffic_light_interval <- 180 #s; //parameter: 'Traffic light interval' init: 60 #s;
	int tttt <- 1;
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
					if (self.shape.perimeter < 1.0) { do die; }
				}
			}

			// Only the study area is measured and reported, so drop the segments
			// outside it before building the routing graph. Doing it here, not
			// after, avoids seeding vehicles on roads that are about to vanish.
			list<road> in_study <- list<road>(road where (study_area covers each.shape));
			ask (road - in_study) { do die; }
			write "Roads: " + string(length(in_study)) + " of the shapefile segments lie inside the study area.";

			// Cropping to the study box cuts streets at the border and leaves
			// isolated fragments. Vehicles seeded on a fragment can never
			// route out, so they sit still forever: keep only the main
			// connected component before the routing graph is built.
			graph full_network <- as_edge_graph(road);
			list main_roads <- [];
			loop comp over: connected_components_of(full_network, true) {
				if (length(comp) > length(main_roads)) { main_roads <- list(comp); }
			}
			int dropped_roads <- length(road) - length(main_roads);
			if (dropped_roads > 0) {
				ask (road - main_roads) { do die; }
			}
			write "Road network: " + string(length(main_roads)) + " segments kept in the main"
			    + " component, " + string(dropped_roads) + " isolated fragments removed.";

			//Weights of the road
			road_weights <- road as_map (each::each.shape.perimeter);
			road_network <- as_edge_graph(road);

			create study_boundary with: [shape::study_area];
			// Additional visualization
			create building from: buildings_shape_file {
				depth <- (rnd(100) / 100) * (rnd(100) / 100) * (rnd(100) / 100 * 10) * 5 + 10;
				texture <- textures[rnd(9)];
			}

		}

		if (tttt = 1) {
			do load_traffic_counts;
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
	int count_of (string s) {
		if (s = nil) { return 0; }
		string t <- trim(s);
		if (t = "") { return 0; }
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
	list<geometry> keep_leading (list<geometry> source, int n) {
		list<geometry> out <- list<geometry>();
		int last <- min(n, length(source)) - 1;
		if (last >= 0) {
			loop i from: 0 to: last { add item: source[i] to: out; }
		}
		return out;
	}

	// Free-flow speed by road class (km/h), the divisor in the Little's Law
	// crossing time. Unlisted classes fall back to 25.
	float class_speed_of (string highway) {
		if (highway = "motorway") { return 80.0; }
		if (highway = "trunk") { return 50.0; }
		if (highway = "primary") { return 40.0; }
		if (highway = "secondary") { return 35.0; }
		if (highway = "tertiary") { return 30.0; }
		if (highway = "living_street") { return 15.0; }
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

	reflex calculate_aqi when: every(refreshing_rate_plot) { //every(1 #minute) {
		float aqi <- max(instant_heatmap);
		ask line_graph_aqi {
			do update(aqi * 10);
		}
		//		 ask indicator_health_concern_level {
		//		 	do update(aqi);
		//		 }
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
			//				create car_random number: delta;			
			//			list<car_random> vehicles <- list(car_random);
			//			if (delta < 0) {
			//				ask -delta among car_random {
			//					do die;
			//				}
			//
			//			} else {
			//				create car_random number: delta with: [type:: "car"];
			//			}

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
	//		int delta_cars <- n_cars - n_cars_prev;
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
	//		int delta_motorbikes <- n_motorbikes - n_motorbikes_prev;
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

	//	reflex update_road_scenario when: road_scenario != road_scenario_prev {
	//		switch road_scenario {
	//			match 0 {
	//				open_roads <- list(road);
	//			}
	//
	//			match 1 {
	//				open_roads <- road where !each.s1_closed;
	//			}
	//
	//			match 2 {
	//				open_roads <- road where !each.s2_closed;
	//			}
	//
	//		}
	//
	//		list<road> closed_roads <- road - open_roads;
	//		ask open_roads {
	//			closed <- false;
	//		}
	//
	//		ask closed_roads {
	//			closed <- true;
	//		}
	//
	//		map<road, float> road_weights <- open_roads as_map (each::each.shape.perimeter);
	//		graph new_road_network <- as_edge_graph(open_roads) with_weights road_weights;
	//		ask vehicle {
	//			recompute_path <- true;
	//		}
	//
	//		road_network <- new_road_network;
	//		road_scenario_prev <- road_scenario;
	//	}
	matrix<float> mat_diff <- matrix(
		[
			[1 / 20, 1 / 20, 1 / 20], 
			[1 / 20, 3 / 5 * pollutant_decay_rate, 1 / 20], 
			[1 / 20, 1 / 20, 1 / 20]
	]);
	//
	//	reflex produce_pollutant {
	//	// Absorb pollutants emitted by vehicles
	//		ask building parallel: true {
	//			aqi <- 0.0;
	//		}
	//
	//		ask road_cell {
	////			write self;
	//			list<car_random> vehicles_in_cell <- car_random inside self;
	//			loop v over: vehicles_in_cell {
	//				if (is_number(v.real_speed)) {
	//					float dist_traveled <- v.real_speed * step / #km;
	//					co <- co + dist_traveled * EMISSION_FACTOR[v.type]["CO"];
	//					nox <- nox + dist_traveled * EMISSION_FACTOR[v.type]["NOx"];
	//					so2 <- so2 + dist_traveled * EMISSION_FACTOR[v.type]["SO2"];
	//					pm <- pm + dist_traveled * EMISSION_FACTOR[v.type]["PM"];
	//				}
	//
	//			}
	//
	//			//			time_absorb_pollutants <- time_absorb_pollutants + (machine_time - start);
	//
	//			// Diffuse pollutants to neighbor cells
	//			ask neighbors {
	//				self.co <- self.co + pollutant_diffusion * myself.co;
	//				self.nox <- self.nox + pollutant_diffusion * myself.nox;
	//				self.so2 <- self.so2 + pollutant_diffusion * myself.so2;
	//				self.pm <- self.pm + pollutant_diffusion * myself.pm;
	//			}
	//
	//			co <- co * (1 - pollutant_diffusion * length(neighbors));
	//			nox <- nox * (1 - pollutant_diffusion * length(neighbors));
	//			so2 <- so2 * (1 - pollutant_diffusion * length(neighbors));
	//			pm <- pm * (1 - pollutant_diffusion * length(neighbors));
	//
	//			// Decay pollutants
	//			co <- pollutant_decay_rate * co;
	//			nox <- pollutant_decay_rate * nox;
	//			so2 <- pollutant_decay_rate * so2;
	//			pm <- pollutant_decay_rate * pm;
	//			//			time_diffuse_pollutants <- time_diffuse_pollutants + (machine_time - start);
	//			list<building> buildings <- list<building>(self.affected_buildings);
	//			ask buildings {
	//				self.aqi <- self.aqi + myself.aqi;
	//			}
	//
	//		}
	//
	//	}

	//	reflex benchmark when: benchmark and every(5 #cycle) {
	//		write "Vehicles move: " + time_vehicles_move;
	//		write "Create congestions: " + time_create_congestions;
	//		write "Absorb pollutants: " + time_absorb_pollutants;
	//		write "Diffuse pollutants: " + time_diffuse_pollutants;
	//		
	//		time_vehicles_move <- 0.0;
	//		time_absorb_pollutants <- 0.0;
	//		time_diffuse_pollutants <- 0.0;
	//	}
	// Stations come from the live feed over the full world extent, but the
	// model only measures inside the study area, so the ones outside it are
	// dropped rather than colouring an area that was never surveyed.
	reflex trim_ambient when: every(10 #s) {
		list<AQI> outside <- list<AQI>(AQI where (not (study_area covers each.shape)));
		if (length(outside) > 0) {
			ask outside {
				do die;
			}
		}
	}

	reflex diff {
		diffuse "phero" on: instant_heatmap matrix: mat_diff;
		//		diffuse "trial" on: instant_heatmap;
	}

	reflex update {
	//			instant_heatmap[] <- instant_heatmap[] * decrease_coeff;
	//			instant_heatmap[] <-0;
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
			float factor <- EMISSION_FACTOR[kind]["PM"] + EMISSION_FACTOR[kind]["NOx"];
			instant_heatmap[location] <- instant_heatmap[location]
				+ (is_electrical ? 0.1 : 1.0) * factor * 3.0;
		}

	}

}

//grid pollutant_grid height: 100 width: 100 neighbors: 8 /*schedules: active_cells*/ {
//	rgb color <- #black;
//	bool active <- false;
//	float pollution;
//
//	reflex pollution_increase when: active {
//		list<vehicle> people_on_cell <- vehicle overlapping self;
//		pollution <- pollution + sum(people_on_cell accumulate (each.get_pollution()));
//	}
//
//	reflex diffusion {
//		ask neighbors {
//			pollution <- pollution + 0.05 * myself.pollution;
//		}
//
//		pollution <- pollution * (1 - 8 * 0.05);
//	}
//
//	reflex update {
//		pollution <- pollution * decrease_coeff;
//		color <- rgb(255 * pollution/10, 0, 0);
//		color<-palette([ #white, #white, #orange, #orange, #red, #red, #red])[int(min(pollution,MAX_P)*7/MAX_P)mod 7];
//	} 
//} 

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
		draw shape.contour color: #blue-100;
		draw shape.contour + 3 color: #blue-100;
	}

}
