/***
* Name: traffic
* Author: minhduc0711
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
	file icon <- file("../images/xanhsm.png");
	file icon_fire <- file("../images/fire.jpg");
	//Map containing all the weights for the road network graph
	map<road, float> road_weights;
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
	float speed_coeff <- 12.0; // 3.0 + rnd(6.0) min: 0.1;
	action update_speed_coeff (int n_cars_on_road, int n_motorbikes_on_road) {
		speed_coeff <- (n_cars_on_road + n_motorbikes_on_road <= capacity) ? 1 : exp(-(n_motorbikes_on_road + 4 * n_cars_on_road) / capacity);
	}

aspect default {
	//		if (display_mode = 0) {
//			if (closed) {
//				draw shape + 50 color: palet[CLOSED_ROAD_TRAFFIC];
//			} else {
		// speed_coeff is 12 while free-flowing and drops towards 0 under load.
		// brewer_colors returns at most 9 entries, so the index has to be
		// clamped: the raw int(13 - speed_coeff) ran off the end of the ramp
		// the moment update_speed_coeff produced a congested road.
		draw shape + (speed_coeff * sizeCoeff)
			color: brewer_colors("Reds")[min(8, max(0, int(9 - speed_coeff / 12.0 * 8.0)))];
		//			}
		//
		//		} else {
		//			if (closed) {
		//				draw shape + 50 color: palet[CLOSED_ROAD_POLLUTION];
		//			}
		//
		//		}

		//		if (closed) {
		//			draw shape + 5 color: palet[CLOSED_ROAD];
		//		} else if (display_mode = 0) {
		//			draw shape+2/(speed_coeff) color: (speed_coeff=1.0) ? palet[NOT_CONGESTED_ROAD] : palet[CONGESTED_ROAD] /*end_arrow: 10*/;
		//		} else {
		//			draw shape color: palet[ROAD_POLLUTION_DISPLAY] /*end_arrow: 10*/;
		//		}
	}

}

species api_loader skills: [thread] {
	float start <- gama.machine_time;
	float end <- gama.machine_time;

	//counting down
	action thread_action() {
		try {
			do loadtraffic;
			do loadAQ;
		}

		catch {
			write ".";
		}

	}

	action loadAQ() {
		ask AQI {
			do die;
		}

		// Open-Meteo CAMS air-quality feed (keyless, no token) for the Penang
		// site. Replaces the dead WAQI token URL, which was also hardcoded
		// to a Hanoi bounding box.
		float aqi_val <- -1.0;
		float pm25_val <- 0.0;
		try {
			json_file
			sss <- json_file("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=5.4096&longitude=100.3161&current=us_aqi,pm2_5&timezone=auto");
			map<string, unknown> c <- sss.contents;
			map<string, unknown> cur <- c["current"];
			if (cur != nil and cur["us_aqi"] != nil) {
				aqi_val <- float(cur["us_aqi"]);
				pm25_val <- float(cur["pm2_5"]);
			}
		}

		catch {
			write "AQI feed unreachable (offline?).";
		}

		if (aqi_val < 0.0) {
			ask (param_indicator where (each.name = lb_AQI_update)) {
				do update("feed offline, model-only heatmap");
			}
		} else {
			// One station per 3x3 cell over the world extent so the heatmap
			// keeps some spatial texture instead of a single flat value.
			float x0 <- world.shape.location.x - world.shape.width / 2.0;
			float y0 <- world.shape.location.y - world.shape.height / 2.0;
			float dx <- world.shape.width / 3.0;
			float dy <- world.shape.height / 3.0;
			loop i from: 0 to: 2 {
				loop j from: 0 to: 2 {
					create AQI with: [
						location::{x0 + i * dx + rnd(dx), y0 + j * dy + rnd(dy)},
						aqi::aqi_val * (0.9 + rnd(0.2)),
						noise::rnd(1.0)
					];
				}
			}
			ask (param_indicator where (each.name = lb_AQI_update)) {
				do update("US-AQI " + string(int(aqi_val)) + " PM2.5 " + string(round(pm25_val * 10) / 10.0) + " @ " + string(date("now")));
			}
		}

	}

	action loadtraffic() {
		ask traffic_incident {
			do die;
		}

int made <- 0;
		bool live_ok <- false;
		live_made <- 0;
		// Live positions come first: real buses crawling on real streets is
		// actual evidence of congestion, which the model's own load cannot give.
		if (load_gtfs_positions()) {
			live_ok <- true;
			do spawn_incidents_from_live_buses;
			made <- live_made;
		}

		if (not live_ok) {
			// Fallback: the simulation itself. The most-loaded roads become live
			// congestion incidents, each still spawning dummy_car flow through the
			// traffic_incident reflex. Used when the network or the feed is down.
			map<road, int> load <- road as_map (each::length(vehicle_random overlapping (each.shape + 12.0)));
			list<road> ordered <- list<road>(road sort_by (load[each]));
			loop k from: 0 to: length(ordered) - 1 {
				road r <- ordered[length(ordered) - 1 - k];
				if (load[r] >= 3 and made < 5) {
					create traffic_incident with: [
						location::r.shape.location,
						description::("congestion x" + string(load[r]) + " on " + string(r.shape.location))
					];
					made <- made + 1;
				}
			}
			ask (param_indicator where (each.name = lb_Traffic_Incident)) {
				do update(string(made) + " simulated congestion incidents @ " + date("now"));
			}

		} else {
			// Genuine feed, so this is live evidence even when nothing is slow.
			ask (param_indicator where (each.name = lb_Traffic_Incident)) {
				do update(string(length(bus_lat)) + " live Rapid Penang buses, "
					+ string(made) + " stopped/slow near site @ " + date("now"));
			}

		}

	}

	// ------------------------------------------------------------------
	// Live bus positions, from Malaysia's official open transit feed.
	//
	// data.gov.my publishes Rapid Penang vehicle positions as GTFS-Realtime,
	// which is protobuf. GAMA cannot decode that natively: there is no bytes
	// type, no bitwise operators and no hex codec, and reading the body as
	// text would corrupt every byte above 0x7F. Two things make it tractable:
	// json_file downloads the body as a verbatim byte copy (so the bytes on
	// disk are intact), and protobuf only needs varints plus little-endian
	// IEEE-754 floats, both of which can be rebuilt from div, mod and pow.
	//
	// Verified against the live feed: ~140 buses, refreshed every 30 s, each
	// with route, plate, position and speed.
	// ------------------------------------------------------------------

	string gtfs_url <- "https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-penang";

	list<float> bus_lat <- [];
	list<float> bus_lon <- [];
	list<float> bus_speed <- [];
	list<string> bus_route <- [];

	// Speed arrives inside Position, which is read before its parent
	// VehiclePosition, so it cannot be returned with the coordinates. These two
	// hand it back and keep bus_speed aligned index-for-index with bus_lat.
	float pos_speed <- 0.0;
	bool pos_has_speed <- false;
	// Incidents built from the live feed during the last load.
	int live_made <- 0;

	// Base-128 varint at index i. The value is in .key, the index just past
	// the varint in .value.
	pair<float, int> pb_varint (list<int> b, int i) {
		float v <- 0.0;
		float scale <- 1.0;
		int j <- i;
		bool more <- true;
		loop k from: i to: length(b) - 1 {
			if (not more) {
				break;
			}

			int by <- b[k];
			v <- v + (by mod 128) * scale;
			scale <- scale * 128.0;
			j <- k + 1;
			if (by < 128) {
				more <- false;
			}

		}

		return pair(v, j);

	}

	// IEEE-754 single precision, little-endian. Carved into sign, exponent and
	// mantissa arithmetically because GAMA has no shifts or masks.
	float pb_float32 (list<int> b, int i) {
		if (i + 3 >= length(b)) {
			return 0.0;
		}

		float bits <- float(b[i]) + float(b[i + 1]) * 256.0 + float(b[i + 2]) * 65536.0 + float(b[i + 3]) * 16777216.0;
		// Not named sign or exp: both are GAMA built-in functions.
		float sgn <- 1.0;
		if (bits >= 2147483648.0) {
			sgn <- -1.0;
			bits <- bits - 2147483648.0;
		}

		int lead <- int(bits / 8388608.0);
		int exponent <- lead mod 256;
		float mant <- bits - float(lead) * 8388608.0;
		if (exponent = 0) {
			return sgn * (mant / 8388608.0) * (2.0 ^ -126.0);
		}

		return sgn * (1.0 + mant / 8388608.0) * (2.0 ^ (float(exponent - 127)));

	}

	// Fetch the feed and fill bus_lat / bus_lon / bus_speed / bus_route.
	// Returns false when the feed is unreachable so the caller can fall back.
	bool load_gtfs_positions() {
		bus_lat <- [];
		bus_lon <- [];
		bus_speed <- [];
		bus_route <- [];

		list<int> b <- [];
		try {
			// Constructing the file only downloads it; contents is never
			// touched, so the JSON parser never sees the protobuf body.
			json_file feed <- json_file(gtfs_url);
			if (not feed.exists) {
				write "GTFS-RT feed unreachable (offline?).";
				return false;
			}

			// od emits unsigned decimal bytes, which GAML can read directly.
			// Hex would need a char-to-int operator the language does not have.
			string dump <- command("od -An -v -tu1 '" + feed.path + "' | tr -s '[:space:]' ' '");
			if (dump = "") {
				write "GTFS-RT feed was empty.";
				return false;
			}

			list<string> toks <- dump tokenize " ";
			b <- list<int>(toks collect int(each));

		}

		catch {
			write "GTFS-RT fetch failed, falling back to simulated incidents.";
			return false;
		}

		if (length(b) < 16) {
			write "GTFS-RT body too short to be a FeedMessage.";
			return false;
		}

		// FeedMessage: field 2 is a repeated FeedEntity.
		int i <- 0;
		loop k from: 0 to: length(b) - 1 {
			if (i >= length(b)) {
				break;
			}

			pair<float, int> t <- pb_varint(b, i);
			int tag <- int(t.key);
			i <- t.value;
			int fld <- tag div 8;
			int wire <- tag mod 8;
			if (wire = 0) {
				pair<float, int> skip <- pb_varint(b, i);
				i <- skip.value;

			} else if (wire = 1) {
				i <- i + 8;

			} else if (wire = 5) {
				i <- i + 4;

			} else if (wire = 2) {
				pair<float, int> l <- pb_varint(b, i);
				int len <- int(l.key);
				int start <- l.value;
				int stop <- start + len;
				if (fld = 2 and stop <= length(b)) {
					do read_entity(b, start, stop);
				}

				i <- stop;

			} else {
				i <- length(b);
			}

		}

		if (length(bus_lat) = 0) {
			write "GTFS-RT parsed but held no vehicle positions.";
			return false;
		}

		return true;

	}

	// FeedEntity: field 4 is the VehiclePosition.
	action read_entity (list<int> b, int start, int stop) {
		int i <- start;
		loop k from: start to: stop - 1 {
			if (i >= stop) {
				break;
			}

			pair<float, int> t <- pb_varint(b, i);
			int tag <- int(t.key);
			i <- t.value;
			int fld <- tag div 8;
			int wire <- tag mod 8;
			if (wire = 0) {
				pair<float, int> skip <- pb_varint(b, i);
				i <- skip.value;

			} else if (wire = 1) {
				i <- i + 8;

			} else if (wire = 5) {
				i <- i + 4;

			} else if (wire = 2) {
				pair<float, int> l <- pb_varint(b, i);
				int len <- int(l.key);
				int sub_start <- l.value;
				int sub_stop <- sub_start + len;
				if (fld = 4 and sub_stop <= stop) {
					do read_vehicle(b, sub_start, sub_stop);
				}

				i <- sub_stop;

			} else {
				i <- stop;
			}

		}

	}

	// VehiclePosition: field 1 is the trip descriptor, field 2 the position.
	action read_vehicle (list<int> b, int start, int stop) {
		string route <- "";
		float lat <- 0.0;
		float lon <- 0.0;
		bool have_pos <- false;
		int i <- start;
		loop k from: start to: stop - 1 {
			if (i >= stop) {
				break;
			}

			pair<float, int> t <- pb_varint(b, i);
			int tag <- int(t.key);
			i <- t.value;
			int fld <- tag div 8;
			int wire <- tag mod 8;
			if (wire = 0) {
				pair<float, int> skip <- pb_varint(b, i);
				i <- skip.value;

			} else if (wire = 1) {
				i <- i + 8;

			} else if (wire = 5) {
				i <- i + 4;

			} else if (wire = 2) {
				pair<float, int> l <- pb_varint(b, i);
				int len <- int(l.key);
				int sub_start <- l.value;
				int sub_stop <- sub_start + len;
				if (fld = 1 and sub_stop <= stop) {
					route <- read_route(b, sub_start, sub_stop);

				} else if (fld = 2 and sub_stop <= stop) {
					pair<float, float> pos <- read_position(b, sub_start, sub_stop);
					lat <- pos.key;
					lon <- pos.value;
					have_pos <- true;

				}

				i <- sub_stop;

			} else {
				i <- stop;
			}

		}

		if (have_pos) {
			add lat to: bus_lat;
			add lon to: bus_lon;
			add route to: bus_route;
			if (pos_has_speed) {
				add pos_speed to: bus_speed;

			} else {
				// -1 marks a position the feed gave without a speed, so that
				// bus_speed stays aligned with bus_lat.
				add -1.0 to: bus_speed;
			}

		}

	}

	// TripDescriptor: route_id is field 5 in this feed, not field 2.
	string read_route (list<int> b, int start, int stop) {
		string route <- "";
		int i <- start;
		loop k from: start to: stop - 1 {
			if (i >= stop) {
				break;
			}

			pair<float, int> t <- pb_varint(b, i);
			int tag <- int(t.key);
			i <- t.value;
			int fld <- tag div 8;
			int wire <- tag mod 8;
			if (wire = 2) {
				pair<float, int> l <- pb_varint(b, i);
				int len <- int(l.key);
				int sub_start <- l.value;
				int sub_stop <- sub_start + len;
				if (fld = 5 and sub_stop <= stop) {
					route <- read_string(b, sub_start, sub_stop);
				}

				i <- sub_stop;

			} else if (wire = 0) {
				pair<float, int> skip <- pb_varint(b, i);
				i <- skip.value;

			} else if (wire = 5) {
				i <- i + 4;

			} else if (wire = 1) {
				i <- i + 8;

			} else {
				i <- stop;
			}

		}

		return route;

	}

	// Position: latitude field 1, longitude field 2, bearing field 3, speed in
	// m/s field 5. Returns lat::lon, and reports the speed through pos_speed /
	// pos_has_speed.
	pair<float, float> read_position (list<int> b, int start, int stop) {
		float lat <- 0.0;
		float lon <- 0.0;
		pos_speed <- 0.0;
		pos_has_speed <- false;
		int i <- start;
		loop k from: start to: stop - 1 {
			if (i >= stop) {
				break;
			}

			pair<float, int> t <- pb_varint(b, i);
			int tag <- int(t.key);
			i <- t.value;
			int fld <- tag div 8;
			int wire <- tag mod 8;
			if (wire = 5) {
				if (fld = 1) {
					lat <- pb_float32(b, i);

				} else if (fld = 2) {
					lon <- pb_float32(b, i);

				} else if (fld = 5) {
					pos_speed <- pb_float32(b, i);
					pos_has_speed <- true;

				}

				i <- i + 4;

			} else if (wire = 2) {
				pair<float, int> l <- pb_varint(b, i);
				i <- l.value + int(l.key);

			} else if (wire = 0) {
				pair<float, int> skip <- pb_varint(b, i);
				i <- skip.value;

			} else if (wire = 1) {
				i <- i + 8;

			} else {
				i <- stop;
			}

		}

		return pair(lat, lon);

	}

	string read_string (list<int> b, int start, int stop) {
		string s <- "";
		int i <- start;
		loop k from: start to: stop - 1 {
			if (i >= stop) {
				break;
			}

			s <- s + char(b[i]);
			i <- i + 1;
		}

		return s;

	}

	// Turn slow live buses into incidents on the map. A single snapshot
	// cannot separate "waiting at a stop" from "stuck in traffic", so these are
	// labelled with the observed speed rather than called congestion.
	// Only buses near the study area are considered.
	action spawn_incidents_from_live_buses {
		float reach <- study_half_size * 3.0 + 1500.0;
		live_made <- 0;
		loop k from: 0 to: length(bus_lat) - 1 {
			float lat <- bus_lat[k];
			float lon <- bus_lon[k];
			point p <- to_GAMA_CRS({lon, lat}, "EPSG:4326").location;
			// Capped: each traffic_incident spawns a dummy_car through its reflex.
			if (live_made < 8 and p != nil and p distance_to study_area.location < reach) {
				float kmh <- 999.0;
				if (k < length(bus_speed) and bus_speed[k] >= 0.0) {
					kmh <- bus_speed[k] * 3.6;
				}

				// An unknown speed is not evidence of anything.
				if (kmh < 15.0) {
					string rt <- "";
					if (k < length(bus_route)) {
						rt <- bus_route[k];
					}

					create traffic_incident with: [
						location::p,
						description::("live bus " + rt + " at " + string(int(kmh)) + " km/h (GTFS-RT)")
					];
					live_made <- live_made + 1;
				}

			}

		}

	}


	//	reflex sss {
	//		if (end - start > 600) {
	////			do loadtraffic;
	////			do loadAQ;
	//			loop times:100000000{}
	//			start <- machine_time;
	//		}
	//
	//		end <- machine_time;
	//	}

}

species AQI {
	geometry shape <- circle(30);
	string description;
	float aqi;
	float noise <- 0.0;

	reflex pollute {
		instant_heatmap[location] <- instant_heatmap[location] + aqi / (15 + noise);
	}

	// A small dot, not the original label: at a 2 km study width a 32 pt
	// number is unreadable and the labels collided with the side panels.
	aspect default {
		draw circle(45 * sizeCoeff) color: #violet border: #white at: location;
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
		path path_followed <- goto(target: target, on: road_network, recompute_path: false, return_path: true, move_weights: road_weights);
		if (location distance_to target < 10) {
			if (should_die) {
				do die;
			} else {
				target <- nil;
			}

		} }

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
				draw squircle(50 * sizeCoeff, 6 * sizeCoeff)  texture:(is_electrical?icon: icon_fire)   rotate: heading depth: 25.5 * sizeCoeff;
//		draw circle(20* sizeCoeff) color:#blue at: pos rotate: heading depth: 1 * sizeCoeff;
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
	}

	float pollution_from_speed {
		float returnedValue <- 1.0;
		return (returnedValue);
	}

	float get_pollution {
		return pollution_from_speed() * 1; // coeff_vehicle[type];
	}
	// 
	//	reflex commute {
	//		do drive_random graph: road_graph;
	//	}

}

species motorbike_random parent: vehicle_random {
	float aqh <- 15 + rnd(50.0);

	init {
	//		vehicle_length <- 3.9 #m;
	//		num_lanes_occupied <- 1;
		speed <- (10 + rnd(20)) #km / #h;
		//		proba_block_node <- 0.0;
		//		proba_respect_priorities <- 1.0;
		//		proba_respect_stops <- [1.0];
		//		proba_use_linked_road <- 0.5;
		//		lane_change_limit <- 2;
		//		linked_lane_limit <- 1;
	}


	// Shortest and thinnest glyph of the counted classes: on a 2 km study
	// area a motorbike has to read as clearly smaller than the car it shares
	// the lane with, otherwise the mix the survey measured is not legible.
	aspect default {
		draw squircle(30 * sizeCoeff, 3 * sizeCoeff) texture: (is_electrical ? icon : icon_fire) rotate: heading depth: 25.5 * sizeCoeff;
	}
}

species car_random parent: vehicle_random {
	float aqh <- 20 + rnd(100.0);

	init {
	//		vehicle_length <- 6.8 #m;
	//		num_lanes_occupied <- 2;
		speed <- (20 + rnd(10)) #km / #h;
		//		proba_block_node <- 0.0;
		//		proba_respect_priorities <- 1.0;
		//		proba_respect_stops <- [1.0];
		//		proba_use_linked_road <- 0.0;
		//		lane_change_limit <- 2;
		//		linked_lane_limit <- 0;
	}


	aspect default {
		draw squircle(50 * sizeCoeff, 6 * sizeCoeff) texture: (is_electrical ? icon : icon_fire) rotate: heading depth: 25.5 * sizeCoeff;
	}
}

species dummy_car parent: vehicle_random {
	float aqh <- 20 + rnd(100.0);

	init {
		should_die <- true;
		//		vehicle_length <- 6.8 #m;
		//		num_lanes_occupied <- 2;
		speed <- (20 + rnd(10)) #km / #h;
		//		proba_block_node <- 0.0;
		//		proba_respect_priorities <- 1.0;
		//		proba_respect_stops <- [1.0];
		//		proba_use_linked_road <- 0.0;
		//		lane_change_limit <- 2;
		//		linked_lane_limit <- 0;
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
		draw squircle(80 * sizeCoeff, 10 * sizeCoeff) texture: (is_electrical ? icon : icon_fire) rotate: heading depth: 25.5 * sizeCoeff;
	}
}

species bus_random parent: vehicle_random {
	float aqh <- 5 + rnd(2.0);

	init {
	//		vehicle_length <- 6.8 #m;
	//		num_lanes_occupied <- 2;
		speed <- (10 + rnd(10)) #km / #h;
		//		proba_block_node <- 0.0;
		//		proba_respect_priorities <- 1.0;
		//		proba_respect_stops <- [1.0];
		//		proba_use_linked_road <- 0.0;
		//		lane_change_limit <- 2;
		//		linked_lane_limit <- 0;
	}


	// Longer than a car, narrower than a lorry.
	aspect default {
		draw squircle(90 * sizeCoeff, 8 * sizeCoeff) texture: (is_electrical ? icon : icon_fire) rotate: heading depth: 25.5 * sizeCoeff;
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
