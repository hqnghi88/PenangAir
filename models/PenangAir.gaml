/***
* Name: PenangAir
* Author: adapted from VinUniAir (minhduc0711) for the Penang Air demonstration
* Description: Single-file GAMA model that turns street-level traffic counts into
*               an air-pollution demonstration for a non-specialist workshop.
*               Roads and buildings come from OpenStreetMap; vehicle populations
*               come from a simple CSV of survey counts.
* Tags: air pollution, AQI, traffic, OSM, workshop, Penang
***/

model PenangAir

global {

	// ==================================================================
	// 1. SITE AND STUDY AREA
	// ==================================================================
	// Demonstration site, given as 5 deg 24'34.6"N  100 deg 18'57.9"E
	// (George Town, Penang, near Jalan Prangin / Lebuh Acheh).
	point site <- {5.409611, 100.316083};
	point site_merc <- to_GAMA_CRS(site, "EPSG:3857").location;

	// Half-width of the square study area, in metres. 1000 => 2 km x 2 km.
	// This is the one number worth arguing about with the team: big enough to
	// hold a real junction and its approaches, small enough that a workshop
	// crowd can follow every vehicle on screen.
	float study_half_size <- 1000.0;
	geometry study_area <- square(2.0 * study_half_size) at_location site_merc;

	// The OSM extract is deliberately larger than the study area, so traffic
	// can drive in from outside and recirculate instead of jamming on the
	// boundary. Only the study area is measured and reported.
	//
	// study_samples is the sampling resolution of the peak-concentration
	// search, not the diffusion resolution.
	int study_samples <- 24;

	// ==================================================================
	// 2. DATA
	// ==================================================================
	// Everything is measured in EPSG:3857 metres, the same projected CRS the
	// VinUni model uses, so sizes, speeds and areas are in real units.
	string osm_path <- "../includes/penang.osm";
	string counts_path <- "../includes/traffic_counts.csv";

	// OSM tag filter. An empty list means "any value of this key".
	map<string, list> osm_filter <- map([
		"highway"::["motorway", "trunk", "primary", "secondary", "tertiary",
		            "unclassified", "residential", "living_street"],
		"building"::[]
	]);

	file<geometry> osmfile <- file<geometry>(osm_file(osm_path, osm_filter));
	geometry shape <- to_GAMA_CRS(envelope(osmfile), "EPSG:3857");

	// ==================================================================
	// 3. SIMULATION CLOCK
	// ==================================================================
	// One simulated second per cycle, so one cycle is one second of traffic.
	float step <- 1 #s;
	// Cycles per simulated minute, used for the on-screen clock.
	int cycles_per_minute <- 60;
	float run_minutes <- 30.0;

	// ==================================================================
	// 4. TRAFFIC -> VEHICLES
	// ==================================================================
	// Survey volumes are peak-hour one-way flows in veh/h. A road never holds
	// that many vehicles at once, so we use Little's Law:
	//
	//     vehicles on a road = flow (veh/h) x time to cross it (hours)
	//
	// This is the only place where survey numbers become agents, and it is one
	// line long so it can be explained on a whiteboard.
	float fleet_scale <- 1.0;
	int max_vehicles <- 900;

	// Free-flow speed by road class (km/h), used for the Little's Law term.
	map<string, float> class_speed <- [
		"motorway"::80.0, "trunk"::50.0, "primary"::40.0, "secondary"::35.0,
		"tertiary"::30.0, "unclassified"::25.0, "residential"::25.0, "living_street"::15.0
	];

	// Tailpipe emission factors in g/km. Car and motorcycle values are the ones
	// already used in the VinUni model; bus and lorry are standard diesel urban
	// values and are the only genuinely new numbers here. They are
	// order-of-magnitude figures for teaching, not certified factors.
	map<string, float> emission_pm <- [
		"car"::0.10, "motorbike"::0.10, "bus"::0.90, "lorry"::1.00
	];
	map<string, float> emission_nox <- [
		"car"::1.50, "motorbike"::0.30, "bus"::7.00, "lorry"::9.00
	];

	// Share of the fleet converted to electric. Zero tailpipe emissions, but
	// non-exhaust PM (brake and tyre wear, road dust) is not modelled, so this
	// is a lower bound rather than a real zero.
	float electric_share <- 0.0;

	// ==================================================================
	// 5. POLLUTION FIELD AND AQI
	// ==================================================================
	int field_size <- 300;
	field pm25_field <- field(field_size, field_size);

	// Diffusion kernel. The centre weight carries the decay of the pollutant
	// plus the share that is not passed to the eight neighbours.
	matrix<float> diffusion_kernel <- matrix([
		[1.0 / 20.0, 1.0 / 20.0, 1.0 / 20.0],
		[1.0 / 20.0, 0.60, 1.0 / 20.0],
		[1.0 / 20.0, 1.0 / 20.0, 1.0 / 20.0]
	]);

	// Turning grams of PM dropped in one cell into a concentration.
	// A cell holds cell_area m2 of ground; mixing it through pm_mix_height metres
	// of air gives cell_area * pm_mix_height m3, so the concentration in
	// micrograms per cubic metre is grams * 1e6 / (cell_area * pm_mix_height).
	// pm_mix_height is an effective dilution depth, not a measured boundary
	// layer: raising it is the same as saying the pollution is better mixed.
	float pm_mix_height <- 80.0;
	float cell_area;
	float pm_scale;

	// The field above is a physically shaped estimate, but it is still NOT a
	// measurement. One constant converts it to a PM2.5-equivalent
	// concentration, and the AQI below follows the US EPA PM2.5 breakpoints.
	//
	// pm25_calibration MUST be fitted against one real monitoring station
	// before any absolute AQI number is quoted or published. The spatial and
	// temporal pattern, and every comparison between two runs, do not depend
	// on it.
	float pm25_calibration <- 1.0;

	// AQI category boundaries (US EPA, 24-hour PM2.5).
	map<int, string> aqi_band <- [
		0::"Good",
		51::"Moderate",
		101::"Unhealthy for sensitive groups",
		151::"Unhealthy",
		201::"Very unhealthy",
		301::"Hazardous"
	];

	// Colours used for the pollution mesh.
	map<rgb, int> zone_colors <- [
		#green::0,
		#yellow::5,
		#orange::10,
		#red::15,
		rgb(116, 49, 121)::20,
		rgb(66, 18, 39)::30
	];

	// Live outputs for the workshop audience.
	float aqi_now <- 0.0;
	string aqi_state <- "Good";
	float nox_total <- 0.0;
	float pm_total <- 0.0;

	graph road_network;
	map<road, float> road_weights;

	int roads_loaded <- 0;
	int buildings_loaded <- 0;
	int vehicles_created <- 0;
	int matched_roads <- 0;
	int default_roads <- 0;

	// ==================================================================
	// 6. HELPERS
	// ==================================================================

	// First n elements of a list, as a new list. Used to scale the fleet down
	// to the cap while preserving the order the segments were added in.
	list<geometry> keep_leading(list<geometry> source, int n) {
		list<geometry> out <- list<geometry>();
		int last <- min(n, length(source)) - 1;
		if (last >= 0) {
			loop i from: 0 to: last {
				add item: source[i] to: out;
			}
		}
		return out;
	}

	// Survey spreadsheets arrive with blank cells. Treat a blank as zero
	// rather than letting the model die on a conversion error.
	int count_of(string s) {
		if (s = nil) { return 0; }
		string t <- s.trim();
		if (t = "") { return 0; }
		return int(t);
	}

	// US EPA PM2.5 breakpoints, linear inside each band.
	float aqi_from_index(float index) {
		float c <- index * pm25_calibration;   // PM2.5-equivalent, ug/m3
		if (c <= 9.0) { return c * 50.0 / 9.0; }
		if (c <= 35.4) { return 50.0 + (c - 9.0) * 50.0 / 26.4; }
		if (c <= 55.4) { return 100.0 + (c - 35.4) * 50.0 / 20.0; }
		if (c <= 125.4) { return 150.0 + (c - 55.4) * 50.0 / 70.0; }
		if (c <= 225.4) { return 200.0 + (c - 125.4) * 100.0 / 100.0; }
		return 300.0 + (c - 225.4) * 200.0 / 250.4;
	}

	string aqi_band_of(float aqi) {
		string state <- "Good";
		loop b over: aqi_band.pairs {
			if (aqi >= b.key) { state <- b.value; }
		}
		return state;
	}

	rgb aqi_color_of(float aqi) {
		if (aqi < 51) { return #green; }
		if (aqi < 101) { return #yellow; }
		if (aqi < 151) { return #orange; }
		if (aqi < 201) { return #red; }
		if (aqi < 301) { return rgb(116, 49, 121); }
		return rgb(66, 18, 39);
	}

	// Peak index inside the study area only, so traffic outside the
	// demonstration window cannot set the headline number.
	float peak_index_in_study_area {
		float peak <- 0.0;
		float dx <- 2.0 * study_half_size / study_samples;
		float dy <- 2.0 * study_half_size / study_samples;
		float x0 <- site_merc.x - study_half_size;
		float y0 <- site_merc.y - study_half_size;
		loop i from: 0 to: study_samples - 1 {
			loop j from: 0 to: study_samples - 1 {
				float v <- pm25_field[{ x0 + i * dx, y0 + j * dy }];
				if (v > peak) { peak <- v; }
			}
		}
		return peak;
	}

	// ==================================================================
	// 7. SET UP
	// ==================================================================
	init {
		cell_area <- (shape.width / field_size) * (shape.height / field_size);
		pm_scale <- 1000000.0 / (cell_area * pm_mix_height);

		// --- roads and buildings out of the OSM file ---
		// The OSM reader splits every way at its junctions, so one street
		// arrives here as many short segments that share endpoints. That is
		// exactly what the routing graph needs, and it is also why the
		// Little's Law term below uses each segment's own length.
		loop geom over: osmfile {
			string highway_str <- string(geom get ("highway"));
			string building_str <- string(geom get ("building"));

			if (highway_str != nil) {
				if (length(geom.points) > 1) {
					create road(
						shape: to_GAMA_CRS(geom, "EPSG:3857"),
						road_name: string(geom get ("name")),
						highway: highway_str
					) {
						// Belt and braces: the OSM reader already drops these.
						if (self.shape.perimeter < 1.0) { do die; }
					}
				}
			} else {
				if (building_str != nil) {
					if (length(geom.points) > 2) {
						create building(shape: to_GAMA_CRS(geom, "EPSG:3857")) {
							depth <- 6.0 + rnd(24.0);
						}
					}
				}
			}
		}

		roads_loaded <- length(road);
		buildings_loaded <- length(building);

		// Route preferentially along longer roads so vehicles use the main
		// streets rather than every service lane equally.
		road_weights <- road as_map (each::each.shape.perimeter);
		road_network <- as_edge_graph(road);

		// --- survey counts ---
		// The field team only has to label counts by the street they stood on.
		// Column order is fixed and documented in the README:
		//   0 road_name, 1 highway, 2 length_m, 3 cars, 4 buses,
		//   5 lorries, 6 motorcycles
		// length_m is informational and is not read: each OSM segment already
		// carries its own length, and that is the length Little's Law needs.
		file counts_file <- csv_file(counts_path, true);
		matrix counts <- matrix(counts_file);
		int first_row <- 0;
		if (string(counts[0, 0]) = "road_name") { first_row := 1; }

		map<string, int> cars_by_name <- map<string, int>();
		map<string, int> buses_by_name <- map<string, int>();
		map<string, int> lorries_by_name <- map<string, int>();
		map<string, int> bikes_by_name <- map<string, int>();
		map<string, int> cars_by_class <- map<string, int>();
		map<string, int> buses_by_class <- map<string, int>();
		map<string, int> lorries_by_class <- map<string, int>();
		map<string, int> bikes_by_class <- map<string, int>();
		map<string, int> segments_by_class <- map<string, int>();

		// GAMA runs `from: a to: b` backwards when a > b, so guard the loop
		// so an empty table (rows after the header = 0) runs zero times.
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

				// Class totals are used as per-segment fallbacks for unnamed
				// lanes, so count the segments per class to divide later.
				//
				// `k in some_map` tests VALUES in GAMA, not keys (GamaMap
				// .contains delegates to containsValue), so key membership
				// has to be tested against the .keys list.
				bool have_class <- hw in segments_by_class.keys;
				if (have_class) {
					segments_by_class[hw] := segments_by_class[hw] + 1;
					cars_by_class[hw] := cars_by_class[hw] + c_n;
					buses_by_class[hw] := buses_by_class[hw] + b_n;
					lorries_by_class[hw] := lorries_by_class[hw] + l_n;
					bikes_by_class[hw] := bikes_by_class[hw] + m_n;
				} else {
					segments_by_class[hw] := 1;
					cars_by_class[hw] := c_n;
					buses_by_class[hw] := b_n;
					lorries_by_class[hw] := l_n;
					bikes_by_class[hw] := m_n;
				}
			}
		}

		// --- place vehicles on the roads, using Little's Law ---
		// One geometry per vehicle. `from:` assigns each geometry to the shape
		// of the agent it creates, which is how a vehicle knows which segment
		// it was seeded on.
		list<geometry> car_spots <- list<geometry>();
		list<geometry> bus_spots <- list<geometry>();
		list<geometry> lorry_spots <- list<geometry>();
		list<geometry> bike_spots <- list<geometry>();

		// Fractional carry, so rounding each road down does not quietly delete
		// most of the fleet on short segments.
		float carry_car <- 0.0;
		float carry_bus <- 0.0;
		float carry_lorry <- 0.0;
		float carry_bike <- 0.0;

		loop r over: road {
			if (study_area covers r.shape) {
				// Little's Law per segment. The surveyed flow applies along the
				// whole street, and a segment's share of the vehicles in
				// transit is its share of the crossing time, i.e. its length
				// over speed. The OSM reader cuts a street into segments at its
				// junctions, so summing this over the segments of one street
				// recovers the single-street result: flow * length / speed.
				bool known_class <- r.highway in class_speed.keys;
				float v_kmh <- known_class ? class_speed[r.highway] : 25.0;
				float crossing_h <- (r.shape.perimeter / 1000.0) / v_kmh;

				bool named <- (r.road_name != nil) and (r.road_name in cars_by_name.keys);
				if (named) { matched_roads := matched_roads + 1; } else { default_roads := default_roads + 1; }

				// Unnamed lanes fall back to the mean of their road class,
				// spread over however many segments that class has.
				int c_vol <- 0;
				int b_vol <- 0;
				int l_vol <- 0;
				int m_vol <- 0;
				if (named) {
					c_vol := cars_by_name[r.road_name];
					b_vol := buses_by_name[r.road_name];
					l_vol := lorries_by_name[r.road_name];
					m_vol := bikes_by_name[r.road_name];
				} else {
					// Mean per segment for this road class. counted is false when the
					// class never appears in the CSV at all.
					bool counted <- r.highway in segments_by_class.keys;
					int n_seg <- counted ? segments_by_class[r.highway] : 1;
					c_vol := counted ? int(cars_by_class[r.highway] / n_seg) : 100;
					b_vol := counted ? int(buses_by_class[r.highway] / n_seg) : 4;
					l_vol := counted ? int(lorries_by_class[r.highway] / n_seg) : 8;
					m_vol := counted ? int(bikes_by_class[r.highway] / n_seg) : 90;
				}

				float raw_car := c_vol * crossing_h * fleet_scale + carry_car;
				float raw_bus := b_vol * crossing_h * fleet_scale + carry_bus;
				float raw_lorry := l_vol * crossing_h * fleet_scale + carry_lorry;
				float raw_bike := m_vol * crossing_h * fleet_scale + carry_bike;

				int n_car := int(raw_car);
				int n_bus := int(raw_bus);
				int n_lorry := int(raw_lorry);
				int n_bike := int(raw_bike);
				carry_car := raw_car - n_car;
				carry_bus := raw_bus - n_bus;
				carry_lorry := raw_lorry - n_lorry;
				carry_bike := raw_bike - n_bike;

				// The n > 0 guards matter. A GAMA `from: a to: b` loop runs
				// backwards when a > b, so `from: 1 to: 0` executes twice
				// instead of never.
				if (n_car > 0) {
					loop j from: 1 to: n_car { add item: r.shape to: car_spots; }
				}
				if (n_bus > 0) {
					loop j from: 1 to: n_bus { add item: r.shape to: bus_spots; }
				}
				if (n_lorry > 0) {
					loop j from: 1 to: n_lorry { add item: r.shape to: lorry_spots; }
				}
				if (n_bike > 0) {
					loop j from: 1 to: n_bike { add item: r.shape to: bike_spots; }
				}
			}
		}

		// Keep the demo interactive on modest workshop hardware. If the
		// surveyed fleet is larger than max_vehicles, scale every class down
		// by the same factor so the vehicle mix is preserved.
		int total_spots := length(car_spots) + length(bus_spots)
		                + length(lorry_spots) + length(bike_spots);
		if (total_spots > max_vehicles and total_spots > 0) {
			float cap <- max_vehicles * 1.0 / total_spots;
			car_spots <- keep_leading(car_spots, int(length(car_spots) * cap));
			bus_spots <- keep_leading(bus_spots, int(length(bus_spots) * cap));
			lorry_spots <- keep_leading(lorry_spots, int(length(lorry_spots) * cap));
			bike_spots <- keep_leading(bike_spots, int(length(bike_spots) * cap));
		}

		create car_random from: car_spots with: [type:: "car"];
		create bus_random from: bus_spots with: [type:: "bus"];
		create lorry_random from: lorry_spots with: [type:: "lorry"];
		create motorbike_random from: bike_spots with: [type:: "motorbike"];

		// Give a share of the fleet an electric powertrain.
		if (electric_share > 0.0) {
			ask (int(electric_share * length(car_random)) among car_random) { is_electrical := true; }
			ask (int(electric_share * length(motorbike_random)) among motorbike_random) { is_electrical := true; }
			ask (int(electric_share * length(bus_random)) among bus_random) { is_electrical := true; }
			ask (int(electric_share * length(lorry_random)) among lorry_random) { is_electrical := true; }
		}

		// Outline of the study area, so the audience always sees the boundary.
		study_border(shape: study_area);

		// On-screen furniture is anchored to the site, not to the OSM
		// envelope: the envelope runs to seven figures in EPSG:3857, so
		// coordinates near zero would be far off-camera.
		float panel_x <- site_merc.x - study_half_size + 80.0;
		float panel_y <- site_merc.y - study_half_size + 80.0;

		// Clock readout, bottom-left inside the study area.
		readout(
			clock_pos: { panel_x, panel_y + 130.0, 0.0 },
			note_pos:  { panel_x, panel_y + 70.0, 0.0 }
		);

		// AQI chart, bottom-right inside the study area.
		float chart_w <- 700.0;
		float chart_h <- 260.0;
		float chart_x <- site_merc.x + study_half_size - chart_w - 80.0;
		aqi_chart(
			origin:    { chart_x, panel_y, 0.0 },
			title_pos: { chart_x, panel_y + chart_h + 60.0, 0.0 },
			value_pos: { chart_x + chart_w, panel_y + chart_h - 30.0, 0.0 },
			state_pos: { chart_x + chart_w, panel_y + chart_h - 85.0, 0.0 },
			w: chart_w,
			h: chart_h
		);

		vehicles_created <- length(car_random) + length(motorbike_random)
		                  + length(bus_random) + length(lorry_random);

		write "Study area: " + string(int(2.0 * study_half_size)) + " m x "
		    + string(int(2.0 * study_half_size)) + " m centred on the site";
		write "Roads loaded: " + string(roads_loaded) + "   Buildings loaded: " + string(buildings_loaded);
		write "Roads using survey counts: " + string(matched_roads)
		    + "   segments using class defaults: " + string(default_roads);
		write "Vehicles created: " + string(vehicles_created)
		    + "  (cars " + string(length(car_random))
		    + ", motorbikes " + string(length(motorbike_random))
		    + ", buses " + string(length(bus_random))
		    + ", lorries " + string(length(lorry_random)) + ")";
		if (electric_share > 0.0) {
			write "Electric share: " + string(int(electric_share * 100.0)) + "%";
		}
		write "Pollution cell: " + string(int(cell_area)) + " m2, effective mixing depth "
		    + string(int(pm_mix_height)) + " m";
		write "NOTE: the AQI shown is NOT calibrated. Fit pm25_calibration against a real";
		write "      monitoring station before quoting any absolute AQI number.";
	}

	// ==================================================================
	// 8. RUNNING THE MODEL
	// ==================================================================
	reflex spread_pollution {
		// `var` is the omissible first facet, so the bare string is the
		// variable name. Over a field it only identifies the diffusion.
		diffuse "pm25" on: pm25_field matrix: diffusion_kernel;
	}

	reflex emit_pollution {
		ask car_random + motorbike_random + bus_random + lorry_random {
			// Distance covered during the last cycle, in km.
			float km <- self.travelled / 1000.0;
			self.travelled <- 0.0;
			if (km > 0.0) {
				float power <- is_electrical ? 0.0 : 1.0;
				float pm <- km * world.emission_pm[type] * power;
				self.collected_pm <- self.collected_pm + pm;
				self.collected_nox <- self.collected_nox + km * world.emission_nox[type] * power;
				pm25_field[location] <- pm25_field[location] + pm * world.pm_scale;
			}
		}
		// Bank this cycle's emission, then clear it. The collectors hold
		// a running total, so summing them without clearing would count
		// the same grams again on every cycle.
		pm_total <- pm_total + sum(car_random.collected_pm) + sum(motorbike_random.collected_pm)
		          + sum(bus_random.collected_pm) + sum(lorry_random.collected_pm);
		nox_total <- nox_total + sum(car_random.collected_nox) + sum(motorbike_random.collected_nox)
		          + sum(bus_random.collected_nox) + sum(lorry_random.collected_nox);
		ask car_random + motorbike_random + bus_random + lorry_random {
			self.collected_pm <- 0.0;
			self.collected_nox <- 0.0;
		}
	}

	reflex measure_aqi when: every(5 #cycle) {
		aqi_now <- aqi_from_index(peak_index_in_study_area());
		aqi_state <- aqi_band_of(aqi_now);
		ask aqi_chart {
			do update(world.aqi_now);
		}
	}

	// One screen refresh per simulated minute, driven by the cycle counter so
	// the readout is independent of how often the AQI reflex runs.
	reflex tick_clock when: (cycle mod cycles_per_minute = 0) {
		int sim_minutes <- cycle / cycles_per_minute;
		string clock <- "Simulated time   "
		              + string(int(sim_minutes / 60)) + "h "
		              + string(sim_minutes mod 60) + "m"
		              + "    of    " + string(int(run_minutes)) + "m";
		ask readout {
			do update(clock);
		}
	}

	reflex report when: (cycle mod cycles_per_minute = 0) and (cycle > 0) {
		write "t+" + string(int(cycle / cycles_per_minute)) + " min  |  AQI "
		    + string(int(aqi_now)) + " (" + aqi_state + ")  |  peak PM2.5-equiv "
		    + string(round(peak_index_in_study_area() * 100.0) / 100.0) + " ug/m3  |  PM "
		    + string(round(pm_total * 100.0) / 100.0) + " g  |  NOx "
		    + string(round(nox_total * 100.0) / 100.0) + " g  |  fleet "
		    + string(length(car_random) + length(motorbike_random)
		    + length(bus_random) + length(lorry_random));
	}

	reflex stop_at_end when: cycle > int(run_minutes * cycles_per_minute) {
		do pause;
	}

}

// ====================================================================
// AGENTS
// ====================================================================

species study_border schedules: [] {
	aspect default {
		draw shape.contour + 40 color: #cyan;
	}
}

species road schedules: [] {
	string road_name;
	string highway;

	aspect default {
		draw shape + 6.0 color: (world.study_area covers self.shape) ? #grey : #3a3a42;
	}
}

species building schedules: [] {
	float depth;

	aspect default {
		draw shape color: rgb(70, 70, 78) depth: depth border: #000000;
	}
}

// Base vehicle: drives the road graph towards a target, then picks another.
// Emissions come from the distance actually covered, so congestion
// automatically produces more pollution on the same road.
species base_vehicle skills: [moving] {
	graph road_graph;
	string type;
	point target;
	float speed;
	bool is_electrical <- false;
	float travelled <- 0.0;
	float collected_pm <- 0.0;
	float collected_nox <- 0.0;

	init {
		road_graph <- world.road_network;
		// `from:` gave this agent the shape of the segment it was seeded on.
		if (self.shape != nil) {
			location <- any_location_in(self.shape);
		} else {
			location <- any_location_in(one_of(road));
		}
	}

	reflex choose_target when: target = nil {
		// Mostly keep destinations inside the study area so traffic circulates
		// in front of the audience instead of leaving the screen.
		if (flip(0.75)) {
			target <- any_location_in(one_of(road where (world.study_area covers each.shape)));
		}
		if (target = nil) {
			target <- any_location_in(one_of(road));
		}
	}

	reflex drive when: target != nil {
		point before <- location;
		path followed <- goto(target: target, on: world.road_network, recompute_path: false,
		                      return_path: true, move_weights: world.road_weights);
		travelled <- travelled + (before distance_to location);
		if (location distance_to target < 30.0) {
			target <- nil;
		}
	}

	aspect base {
		draw squircle(26.0, 11.0) color: (is_electrical ? #cyan : #orange)
		     rotate: heading depth: 8.0 border: #000000;
	}
}

species car_random parent: base_vehicle {
	init { speed <- (20.0 + rnd(15.0)) #km / #h; }
}

species motorbike_random parent: base_vehicle {
	init { speed <- (25.0 + rnd(20.0)) #km / #h; }
}

species bus_random parent: base_vehicle {
	init { speed <- (15.0 + rnd(10.0)) #km / #h; }
}

// Lorries are the class the VinUni model never had. They matter in Penang
// because their PM and NOx factors are an order of magnitude above a car's.
species lorry_random parent: base_vehicle {
	init { speed <- (15.0 + rnd(10.0)) #km / #h; }
}

species readout schedules: [] {
	// Overwritten in the experiment's init; defaults only for the compiler.
	point clock_pos <- {11166200.0, 602200.0, 0.0};
	point note_pos <- {11166200.0, 602140.0, 0.0};
	string value <- "";

	action update(string v) {
		value <- v;
	}

	aspect default {
		draw value at: clock_pos anchor: #bottom_left color: #white font: font(30);
		draw "AQI comes from a modelled PM2.5 field and is NOT calibrated against a monitor"
		     at: note_pos anchor: #bottom_left color: #grey font: font(18);
	}
}

species aqi_chart schedules: [] {
	// All five are overwritten in the experiment's init with positions
	// anchored to site_merc; the values here only keep the compiler happy.
	point origin <- {11166600.0, 602000.0, 0.0};
	point title_pos <- {11166600.0, 602400.0, 0.0};
	point value_pos <- {11167300.0, 602250.0, 0.0};
	point state_pos <- {11167300.0, 602190.0, 0.0};
	float w <- 700.0;
	float h <- 260.0;
	float max_val <- 300.0;
	list<float> history <- list_with(40, -1.0);

	action update(float v) {
		remove index: 0 from: history;
		add item: v to: history at: length(history);
	}

	action draw_line(point a, point b, int thickness, rgb col) {
		// centroid of a two-point line is its midpoint (SpatialPunctal.java).
		geometry seg <- line([a, b]) + thickness;
		draw seg at: centroid(seg) color: col;
	}

	aspect default {
		// `origin` is the bottom-left of the plot box, so the trace grows
		// upward from it and AQI 0 sits on the baseline.
		draw rectangle(w, h) at: { origin.x + w / 2.0, origin.y + h / 2.0, 1.0 }
		     color: rgb(0, 0, 0, 140) border: #808080;
		draw "AQI inside the 2 km study area" at: title_pos anchor: #bottom_left
		     color: #white font: font(24);
		draw string(int(world.aqi_now)) at: value_pos anchor: #top_right
		     color: world.aqi_color_of(world.aqi_now) font: font(44);
		draw world.aqi_state at: state_pos anchor: #top_right
		     color: world.aqi_color_of(world.aqi_now) font: font(20);

		point previous <- nil;
		loop i from: 0 to: length(history) - 1 {
			if (history[i] >= 0) {
				point p <- { origin.x + w * i / length(history),
				             origin.y + h * min(1.0, history[i] / max_val), 2.0 };
				if (previous != nil) {
					do draw_line(previous, p, 3, world.aqi_color_of(history[i]));
				}
				previous <- p;
			}
		}
	}
}

// ====================================================================
// EXPERIMENTS
// ====================================================================

experiment Penang_Demo autorun: true {

	parameter "Study area half-width (m)" var: study_half_size <- 1000 min: 300 max: 3000 step: 100;
	parameter "Fleet scale" var: fleet_scale <- 1.0 min: 0.1 max: 3.0 step: 0.1;
	parameter "Electric share" var: electric_share <- 0.0 min: 0.0 max: 1.0 step: 0.05;
	parameter "Mixing depth (m)" var: pm_mix_height <- 80.0 min: 10.0 max: 300.0 step: 10.0;
	parameter "Run length (minutes)" var: run_minutes <- 30.0 min: 5.0 max: 120.0 step: 5.0;

	output synchronized: false {
		layout #split parameters: false navigator: false editors: false consoles: false
		       toolbars: false tray: false tabs: false controls: true;

		display main type: opengl background: #101014 axes: false {

			camera 'default' location: {11167135.0, 603091.0, 9500.0} target: {11167135.0, 603091.0, 0.0};

			species building;
			species road;
			species study_border;
			species car_random aspect: base;
			species motorbike_random aspect: base;
			species bus_random aspect: base;
			species lorry_random aspect: base;
			species readout;
			species aqi_chart;

			mesh pm25_field scale: 1 above: 1 triangulation: true transparency: 0.5
			     color: scale(zone_colors) smooth: 1;

			overlay position: {30 #px, 30 #px} size: {1 #px, 1 #px} background: #101014
			       border: #101014 rounded: false {
				float y <- 20 #px;
				draw "Penang Air demonstration" at: { 0, y } anchor: #top_left
				     color: #white font: font(26);
				y <- y + 55 #px;
				draw "Site 5.409611 N, 100.316083 E - 2 km study area"
				     at: { 0, y } anchor: #top_left color: #white font: font(18);
				y <- y + 40 #px;
				loop band over: aqi_band.pairs {
					draw square(20 #px) at: { 10 #px, y + 10 #px } color: aqi_color_of(float(band.key));
					draw band.value + "  (AQI " + string(band.key) + "+)"
					     at: { 38 #px, y } anchor: #left_center color: #white font: font(15);
					y <- y + 26 #px;
				}
				y <- y + 18 #px;
				draw square(20 #px) at: { 10 #px, y + 10 #px } color: #orange;
				draw "Combustion vehicle" at: { 38 #px, y } anchor: #left_center
				     color: #white font: font(15);
				y <- y + 24 #px;
				draw square(20 #px) at: { 10 #px, y + 10 #px } color: #cyan;
				draw "Electric vehicle" at: { 38 #px, y } anchor: #left_center
				     color: #white font: font(15);
			}
		}
	}
}

// Headless run, for producing the numbers and figures after the workshop.
// The same `report` reflex prints a row every simulated minute.
experiment Penang_Batch autorun: false type: batch until: (cycle > 1800) {

	parameter "Study area half-width (m)" var: study_half_size <- 1000 min: 300 max: 3000 step: 100;
	parameter "Fleet scale" var: fleet_scale <- 1.0 min: 0.1 max: 3.0 step: 0.1;
	parameter "Electric share" var: electric_share <- 0.0 min: 0.0 max: 1.0 step: 0.05;
	parameter "Mixing depth (m)" var: pm_mix_height <- 80.0 min: 10.0 max: 300.0 step: 10.0;
	parameter "Run length (minutes)" var: run_minutes <- 30.0 min: 5.0 max: 120.0 step: 5.0;

	output {
		layout #split parameters: false navigator: false editors: false consoles: false
		       toolbars: false tray: false tabs: false controls: false;
	}
}
