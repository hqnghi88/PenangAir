/***
* Name: traffic
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model traffic

import "../global_vars.gaml"
import "visualization.gaml"

global {
	float time_vehicles_move;
	int nb_recompute_path;
	float lane_width <- 1.7;
	//Map containing all the weights for the road network graph
	map<road, float> road_weights;
	// Fleet-wide mean road congestion, for the status panel.
	float network_congestion <- 0.0;

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
			speed_coeff <- max(0.6, 12.0 * (1.0 - congestion));
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
		// in main.gaml and the speed reduction below.
		ask vehicle_random { current_congestion <- 0.0; }
		loop r over: road {
			if (r.congestion > 0.0) {
				ask vehicle_random overlapping (r.shape + 12.0) {
					current_congestion <- max(current_congestion, r.congestion);
				}
			}
		}
		ask (param_indicator where (each.name = lb_NetworkCongestion)) {
			do update(string(int(network_congestion * 100)) + "%");
		}
	}

	// Even-odd day rule: advance the simulation day and decide, per
	// vehicle, whether it may drive today. Non-payers whose plate
	// parity mismatches the day park (active_today = false -> speed 0,
	// grey glyph, no load, no emissions). Road-tax payers always drive.
	// The dummy cars that flow out of traffic incidents are exempt so
	// they still reach their target and die as designed.
	reflex even_odd_rule {
		sim_day <- int(time / day_length);
		odd_today <- (sim_day mod 2 = 1);
		if (not pol_even_odd) {
			ask (vehicle_random where (each.active_today = false and not (each.should_die = true))) {
				active_today <- true;
			}
		} else {
			ask (vehicle_random where (not (each.should_die = true))) {
				active_today <- road_tax_paid or (plate_parity = (odd_today ? 1 : 0));
			}
		} 
		// Keep the panel current; with the rule on it also shows which
		// day of the rotation we are in, so the parked half is explicable.
		string pol_str <- active_policies_string();
		if (pol_even_odd) {
			pol_str <- pol_str + "[day " + string(sim_day) + (odd_today ? " odd" : " even") + "]";
		}
		ask (param_indicator where (each.name = lb_ActivePolicies)) {
			do update(pol_str);
		}
	}
}

species road schedules: [] {
	rgb color <- #white;
	string type;
	// Survey lookup keys, read from the shapefile's NAME/HIGHWAY columns.
	// The traffic-counts CSV is keyed on street name, so without these the
	// counts cannot be attached to the segments they describe.
	string road_name;
	string highway;
	bool oneway;
	bool s1_closed;
	bool s2_closed;
	bool closed;
	float capacity <- 1 + shape.perimeter / 30;
	// Live congestion level of this segment, in [0,1].
	float congestion <- 0.0;
	float speed_coeff <- 12.0; // 3.0 + rnd(6.0) min: 0.1;

aspect default { 
		// speed_coeff is 12 while free-flowing and drops towards 0 under load.
		// brewer_colors returns at most 9 entries, so the index has to be
		// clamped: the raw int(13 - speed_coeff) ran off the end of the ramp
		// the moment update_speed_coeff produced a congested road.
		draw shape + (speed_coeff * sizeCoeff)
			color: brewer_colors("Reds")[min(8, max(0, int(9 - speed_coeff / 12.0 * 8.0)))];
		// Signal timing policy: a bright green trace over every street, so
		// the switch is visible network-wide rather than only in the panel.
		if (pol_signal_timing) {
			draw shape.contour color: rgb(0, 255, 120, 140);
		}
	}

}

species traffic_incident {
	geometry shape <- circle(30);
	string description;

	reflex flow when: flip(0.5) {
	//		list<road> tmp<-road at_distance 1;
		create dummy_car {
		//			target_roads <- tmp;
			targetP <- circle(10) at_location (myself.location);
			location <- any_location_in(targetP);
		}

	}

	aspect default {
	//		draw description color: #pink at: location perspective: false font: font("SansSerif", 36, #bold);
		draw triangle(500*sizeCoeff) color: #red;
	}

}

species base_vehicle skills: [moving] {
	rgb color <- rnd_color(255);
	graph road_graph;
	string type;
	bool should_die;
	//Target point of the agent
	point target;
	//Probability of leaving the building
	float leaving_proba <- 0.05;
	//Speed of the agent
	float speed <- rnd(10) #km / #h + 1;
	// Random state
	string state;
	//	list<road> target_roads;
	geometry targetP;
	bool is_electrical <- false;
	// Live congestion level of the segment this vehicle is on, in [0,1].
	// Written by the update_congestion reflex; read by the emission
	// penalty in main.gaml and the congestion_speed reflex below.
	float current_congestion <- 0.0;
	// Free-flow speed captured on the first cycle, so congestion_speed
	// can scale back from it rather than compounding the previous cycle.
	float base_speed <- 0.0;
	// Set by the Low Emission Zone policy: survivors are modernised and
	// emit half the PM/NOx of their class factor.
	bool modernized <- false;
	// Even-odd day rule. Every vehicle gets a plate parity at creation;
	// with pol_even_odd on it may only drive on the matching simulation
	// day (0 = even day, 1 = odd day) and parks otherwise. Road-tax
	// payers ignore the rule entirely and go anywhere, any day.
	int plate_parity <- flip(0.5) ? 0 : 1;
	bool road_tax_paid <- false;
	bool active_today <- true;

	init {
		location <- any_location_in(one_of(road));
		//		if (should_die) {
		//			target_roads <- [road closest_to self];
		//		location <- any_location_in(one_of(target_roads));
		//		}

	}
	//Reflex to leave the building to another building
	reflex depart when: (target = nil) and (flip(leaving_proba)) {
		if (should_die) {
			target <- any_location_in(targetP);
		} else {
			target <- any_location_in(one_of(road));
		}

	}
	//Reflex to move to the target building moving on the road network
	reflex move when: target != nil {
	//we use the return_path facet to return the path followed
	// Vehicles on a congested segment re-solve their route against the
	// congestion-penalised weights every cycle, so queues clear by
	// re-routing rather than by waiting; a small random re-solve keeps
	// paths fresh even on smooth roads.
		path path_followed <- goto(target: target, on: road_network, recompute_path: (current_congestion > 0.5) or flip(0.02), return_path: true, move_weights: road_weights);
		if (location distance_to target < 10) {
			if (should_die) {
				do die;
			} else {
				target <- nil;
			}

		} 
	}

	float dist <- rnd(1) * 10 + 10.0 * rnd(3);
	point compute_position {
	// Shifts the position of the vehicle perpendicularly to the road,
	// in order to visualize different lanes
		point shift_pt <- {cos(heading + 90) * dist* sizeCoeff*0.5, sin(heading + 90) * dist* sizeCoeff*0.5};
		return location + shift_pt;
	}

	aspect base {
	//				draw circle(10);
//		point pos <- compute_position(); 
//				point pos <- compute_position();
				draw squircle(50 * sizeCoeff, 6 * sizeCoeff) color: (active_today ? (is_electrical ? #cyan : (modernized ? #lime : #violet)) : rgb(120, 120, 120)) rotate: heading depth: 25.5 * sizeCoeff;
//		draw circle(20* sizeCoeff) color:#violet at: pos rotate: heading depth: 1 * sizeCoeff;
		//		draw rectangle(1 * sizeCoeff, sizeCoeff) color: color rotate: heading depth: 1 * sizeCoeff border: #black;
	} }

species vehicle_random parent: base_vehicle {
	float aqh <- 0.0;
	bool recompute_path <- false;
	// Deliberately no default shape. `create from:` sets it to the road segment
	// the survey placed this vehicle on, and init then seeds the agent there.
	// A default triangle here would be indistinguishable from a real seed and
	// would scatter the fleet away from the streets the counts were measured on.
	geometry shape;
	init {
		road_graph <- road_network;
		if (self.shape != nil) {
			location <- any_location_in(self.shape);
		} else {
			location <- any_location_in(any(road)); //one_of(non_deadend_nodes).location;
		}
		// Vehicles entering the fleet while the road tax is on pay with
		// the configured probability, same as the initial conversion.
		if (pol_road_tax) {
			road_tax_paid <- flip(road_tax_share);
		}
	}

	float pollution_from_speed {
		float returnedValue <- 1.0;
		return (returnedValue);
	}

	// Congestion slows vehicles: up to 80% speed loss on a saturated
	// segment. current_congestion is rewritten every 5 cycles by the
	// update_congestion reflex, so this tracks the network state.
	// Parked vehicles (even-odd rule, off-day) stand still entirely.
	reflex congestion_speed {
		if (base_speed = 0.0) {
			base_speed <- speed;
		}
		if (active_today) {
			speed <- base_speed * (1.0 - 0.8 * current_congestion);
		} else {
			speed <- 0.0;
		}
	}

	float get_pollution {
		return pollution_from_speed() * 1; // coeff_vehicle[type];
	} 

}

species motorbike_random parent: vehicle_random {
	float aqh <- 15 + rnd(50.0);

	init { 
		speed <- (10 + rnd(20)) #km / #h; 
	}


	// Shortest and thinnest glyph of the counted classes: on a 2 km study
	// area a motorbike has to read as clearly smaller than the car it shares
	// the lane with, otherwise the mix the survey measured is not legible.
	aspect default {
		draw squircle(30 * sizeCoeff, 3 * sizeCoeff) color: (active_today ? (is_electrical ? #cyan : (modernized ? #lime : #violet)) : rgb(120, 120, 120)) rotate: heading depth: 25.5 * sizeCoeff;
		// Badges float above the glyph (z clears its depth) and are sized
		// to enclose it, otherwise the extruded body hides them entirely.
		if (active_today and pol_even_odd) {
			draw (circle(7 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: (plate_parity = 0 ? #yellow : #magenta);
		}
		if (active_today and road_tax_paid and pol_road_tax) {
			draw (circle(22 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: rgb(255, 215, 0, 70) border: #gold;
		}
	}
}

species car_random parent: vehicle_random {
	float aqh <- 20 + rnd(100.0);

	init { 
		speed <- (20 + rnd(10)) #km / #h; 
	}


	aspect default {
		draw squircle(50 * sizeCoeff, 6 * sizeCoeff) color: (active_today ? (is_electrical ? #cyan : (modernized ? #lime : #violet)) : rgb(120, 120, 120)) rotate: heading depth: 25.5 * sizeCoeff;
		// Badges float above the glyph and enclose it (see motorbike).
		if (active_today and pol_even_odd) {
			draw (circle(8 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: (plate_parity = 0 ? #yellow : #magenta);
		}
		if (active_today and road_tax_paid and pol_road_tax) {
			draw (circle(35 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: rgb(255, 215, 0, 70) border: #gold;
		}
	}
}

species dummy_car parent: vehicle_random {
	float aqh <- 20 + rnd(100.0);

	init {
		should_die <- true; 
		speed <- (20 + rnd(10)) #km / #h; 
	}

}

// Lorries are the vehicle class the VinUni model never had. The Penang
// survey counts lorries in their own column (includes/traffic_counts.csv),
// so folding them into buses would both lose the count and understate their
// PM and NOx.
species lorry_random parent: vehicle_random {
	float aqh <- 25 + rnd(20.0);

	init {
		speed <- (12 + rnd(8)) #km / #h;
	}

	// Longest glyph in the fleet and wider than a bus, which is how a
	// 3-axle lorry reads against a 2-axle one at 2 km zoom.
	aspect default {
		draw squircle(80 * sizeCoeff, 10 * sizeCoeff) color: (active_today ? (is_electrical ? #cyan : (modernized ? #lime : #violet)) : rgb(120, 120, 120)) rotate: heading depth: 25.5 * sizeCoeff;
		// Badges float above the glyph and enclose it (see motorbike).
		if (active_today and pol_even_odd) {
			draw (circle(9 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: (plate_parity = 0 ? #yellow : #magenta);
		}
		if (active_today and road_tax_paid and pol_road_tax) {
			draw (circle(55 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: rgb(255, 215, 0, 70) border: #gold;
		}
	}
}

species bus_random parent: vehicle_random {
	float aqh <- 5 + rnd(2.0);

	init { 
		speed <- (10 + rnd(10)) #km / #h; 
	}


	// Longer than a car, narrower than a lorry.
	aspect default {
		draw squircle(90 * sizeCoeff, 8 * sizeCoeff) color: (active_today ? (is_electrical ? #cyan : (modernized ? #lime : #violet)) : rgb(120, 120, 120)) rotate: heading depth: 25.5 * sizeCoeff;
		// Badges float above the glyph and enclose it (see motorbike).
		if (active_today and pol_even_odd) {
			draw (circle(9 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: (plate_parity = 0 ? #yellow : #magenta);
		}
		if (active_today and road_tax_paid and pol_road_tax) {
			draw (circle(60 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: rgb(255, 215, 0, 70) border: #gold;
		}
		// PT boost: every bus gets a blue policy halo sized to enclose
		// the whole glyph, floating above it.
		if (active_today and pol_public_transport) {
			draw (circle(65 * sizeCoeff) at_location (location + {0.0, 0.0, 30.0 * sizeCoeff}))
			    color: rgb(30, 144, 255, 70) border: #dodgerblue;
		}
	}
}

species building schedules: [] {
	float height;
	string type;
	float aqi;
	rgb color;
	file texture;
	float depth;
	agent p_cell;
	int LVL;

//	init {
//		if height < min_height {
//			height <- mean_height + rnd(0.3, 0.3);
//		}
//
//	}

	aspect border {
		draw shape.contour + 50 border: #gray color: #orange;
	}

	aspect default {
	//		if (display_mode = 0) {
	//			draw shape texture: [roof_texture.path, texture.path] depth: depth color: (type = type_outArea) ? palet[BUILDING_OUTAREA] : palet[BUILDING_BASE] /*border: #darkgrey*/
	//			/*depth: height * 10*/;
	//		} else {
		draw shape color: #grey /*color: (type = type_outArea) ? palet[BUILDING_OUTAREA] : world.get_pollution_color(aqi) texture: [roof_texture.path, texture.path] border: #darkgrey*/
		depth: depth;
		//		}

	}

} 
