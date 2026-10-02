/***
* Name: mainroadcells
* Author: minhduc0711
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model main

import "agents/traffic2.gaml"
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
	//	list<road> open_roads;
	float traffic_light_interval <- 180 #s; //parameter: 'Traffic light interval' init: 60 #s;
	int tttt <- 1;
	//	list<pollutant_grid> active_cells;
	init {
		if (simType = 0) {
			create road from: roads_shape_file {
			}

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
			write "Road network: " + string(length(main_roads) + dropped_roads)
			    + " segments loaded, " + string(length(main_roads))
			    + " kept in the main component, " + string(dropped_roads)
			    + " isolated fragments removed.";

			//Weights of the road
			road_weights <- road as_map (each::each.shape.perimeter);
			road_network <- as_edge_graph(road);

			// Additional visualization
			create building from: buildings_shape_file {
				depth <- (rnd(100) / 100) * (rnd(100) / 100) * (rnd(100) / 100 * 10) * 5 + 10;
				texture <- textures[rnd(9)];
			}

		}

		if (tttt = 1) {
			create car_random number: max_cars with: [type:: "car"];
			create motorbike_random number: max_motorbikes with: [type:: "motorbike"];
			create bus_random number: max_bus with: [type:: "bus"];
		}

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

	}

	reflex update_car_population when: n_cars != n_cars_prev {
	//		int delta_cars <- n_cars - n_cars_prev;
		do update_vehicle_population("car", n_cars);
		ask first(progress_bar where (each.title = lb_cars)) {
			do update(float(n_cars));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes)));
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
			do update(float((n_bus + n_cars + n_motorbikes)));
		}

		n_motorbikes_prev <- n_motorbikes;
	}

	reflex update_taxi_population when: n_bus != n_bus_prev {
	//		int delta_taxi <- n_bus - n_taxi_prev;
		do update_vehicle_population("bus", n_bus);
		ask first(progress_bar where (each.title = lb_bus)) {
			do update(float(n_bus));
		}

		ask first(progress_bar where (each.title = lb_rates_EG)) {
			do update(float((n_bus + n_cars + n_motorbikes)));
		}

		n_bus_prev <- n_bus;
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
	reflex diff {
		diffuse "phero" on: instant_heatmap matrix: mat_diff;
		//		diffuse "trial" on: instant_heatmap;
	}

	reflex update {
	//			instant_heatmap[] <- instant_heatmap[] * decrease_coeff;
	//			instant_heatmap[] <-0;
		ask car_random + motorbike_random + bus_random + dummy_car {
			instant_heatmap[location] <- instant_heatmap[location] + (is_electrical ? 0.1 : 1.0) * self.aqh / 200;
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