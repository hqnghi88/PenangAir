/***
* Name: mainroadcells
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model main

import "main.gaml"

global {
	float step <- 1 #s;
	file icon <- file("../images/xanhsm.png");
	// Penang data (George Town, EPSG:3857): roads and buildings from
	// includes/penang_{roads,buildings}.shp. The fleet is NOT hardcoded here.
	// main2.gaml reads the real survey flows from includes/traffic_counts.csv
	// and converts them with Little's Law, across all four counted classes:
	// cars, buses, lorries and motorcycles. max_cars and friends are then set
	// to whatever the survey produced, and the bars below are scaled to those.
	shape_file roads_shape_file <- shape_file("../includes/penang_roads.shp"); 
	shape_file buildings_shape_file <- shape_file("../includes/penang_buildings.shp"); 
	geometry shape <- envelope(buildings_shape_file);
	float xx_sc <- 1.0;
	float xx <- 3300.0;
	float yy <- 2000.0;
	float lx <- 30.0;
	float ly <- -630.0;
	float sub_scale <- 0.4;
	//	float map_scale_main <- 0.75;
	//	float map_main_y <- 5200.0;
	float WW <- 3.9;
	float HH <- 3.9;

	init {
	//		sizeCoeff <- 100;
		sizeCoeff <- 0.2;

		// ------------------------------------------------------------------
		// Penang UI layout.
		// The Hanoi version hardcoded panel positions in metres (xx, lx, ly,
		// ...), which are meaningless in the Penang CRS: every panel ended up
		// ~1.1e7 units away from the map, i.e. off screen. Everything is now
		// derived from world.shape, so the panels stay glued to the map in
		// any projection. The map spans world.shape (ctr +/- W/2, H/2), so the
		// default camera covers it; the side column is placed just outside
		// that envelope and relies on the display fitting the whole scene.
		// ------------------------------------------------------------------
		point ctr <- world.shape.location;
		float W <- world.shape.width;
		float H <- world.shape.height;
		// progress_bar draws its title 10*scale above the bar and its
		// left/right labels 40*scale below it, so this sets the vertical
		// spacing needed between two stacked bars.
		float lab_scale <- H / 1400.0;
		// World units per screen pixel, used to nudge panels by a few pixels.
		// Assumes the scene spans the window over ~1200 px; adjust if the
		// panels need a bigger nudge.
		float px <- W / 1200.0;
		// Clock: left column, outside the world envelope. with_box is on so the
		// panel occupies exactly x..x+width and stays clear of the map.
		// The y axis reads downwards on screen in this display, hence the
		// minus sign on the px nudge.
		float ui_left <- ctr.x - W / 2.0 - W * 0.34;
		// Right column: outside the world envelope (the map spans
		// ctr.x +/- W/2), so the panels never cover the map. The display
		// fits the scene bounds on open, which then include this column.
		float ui_right <- ctr.x + W / 2.0 + W * 0.04;
		float bar_w <- W * 0.30;
		float bar_h <- H * 0.04;
		// Five bars stacked below the chart: the step has to clear the title
		// drawn 10*scale above a bar and the labels drawn 40*scale below it.
		float bar_step <- H * 0.105;
		float bar_y1 <- ctr.y - H * 0.10;

		create param_indicator with: [x::ui_left, y::ctr.y + H * 0.47 - 50.0 * px, size::22, name::lb_Time, value::"" + string(date("now")), with_box::true, width::W * 0.30, height::H * 0.05];

		// max_* now come from the survey (main2.gaml load_traffic_counts), so these
		// bars show the real counted fleet rather than hand-set numbers. The
		// labels keep their "% Electrical" wording because that is what the
		// sliders drive: n_* of max_* vehicles are made electric.
		create progress_bar with:
		[x::ui_right, y::bar_y1, width::bar_w, height::bar_h, max_val::(max_cars + max_bus + max_motorbikes + max_lorries), title::lb_rates_EG, left_label::"0%", right_label::"100%", scale::lab_scale];
		create progress_bar with:
		[x::ui_right, y::bar_y1 - bar_step, width::bar_w, height::bar_h, max_val::max_cars, title::lb_cars, left_label::"0%", right_label::"100%", scale::lab_scale];
		create progress_bar with:
		[x::ui_right, y::bar_y1 - 2.0 * bar_step, width::bar_w, height::bar_h, max_val::max_motorbikes, title::lb_motobike, left_label::"0%", right_label::"100%", scale::lab_scale];
		create progress_bar with:
		[x::ui_right, y::bar_y1 - 3.0 * bar_step, width::bar_w, height::bar_h, max_val::max_bus, title::lb_bus, left_label::"0%", right_label::"100%", scale::lab_scale];
		create progress_bar with:
		[x::ui_right, y::bar_y1 - 4.0 * bar_step, width::bar_w, height::bar_h, max_val::max_lorries, title::lb_lorries, left_label::"0%", right_label::"100%", scale::lab_scale];

		create line_graph_aqi with: [x::ui_right, y::ctr.y + H * 0.26, width::bar_w, height::H * 0.22, label::"Hourly AQI", thick_axe::1, thick_line::5];
		// aqi_site_4326: the live-feed loader lives in agents/traffic.gaml,
		// which cannot see main.gaml's site_merc. site_4326 rather than
		// site_merc because the latter is only built in main.gaml's init,
		// which has not run yet when this experiment init runs.
		create api_loader with: [aqi_site_4326::site_4326];
		ask api_loader {
			do run_thread interval: 60 #second;
		}

	}

	string map_center <- "48.8566140,2.3522219";

	//	reflex produce_pollutant {
	//		ask road { 
	//			speed_coeff <- rnd(12);
	//		}
	//
	//	}

}

experiment exp4Projector autorun: true {
	// The fleet comes from includes/traffic_counts.csv via main2.gaml, which
	// sets max_cars / max_motorbikes / max_bus / max_lorries from the survey.
	// study_half_size and fleet_scale are the two numbers the description asks
	// to be arguable on the workshop day: how big the study area is, and how
	// hard to push the counted traffic.
	parameter "Study area half-width (m)" var: study_half_size <- 1000 min: 300 max: 3000 step: 100;
	parameter "Fleet scale" var: fleet_scale <- 1.0 min: 0.1 max: 3.0 step: 0.1;
	parameter "% Electrical cars" var: n_cars <- 0 min: 0 max: max_cars;
	parameter "% Electrical motorcycles" var: n_motorbikes <- 0 min: 0 max: max_motorbikes;
	parameter "% Electrical buses" var: n_bus <- 0 min: 0 max: max_bus;
	parameter "% Electrical lorries" var: n_lorries <- 0 min: 0 max: max_lorries;
	output synchronized: true {
	//		layout #split parameters: false navigator: false editors: false consoles: false toolbars: false tray: false tabs: false controls: true;
		display "project" background: #black axes: false type: 3d 
		keystone: [{0.0,0.0,0.0},{0.0,1.0,0.0},{1.0,1.0,0.0},{0.9934502617256865,0.021782863139094277,0.0}]
		{
			// Penang: no raster backdrop (vindark.png is Hanoi) -- draw vectors only.
			species road refresh: false position: {0, 0, 0.05};
			species study_boundary position: {0, 0, 0.045};
			species building refresh: false;
			species car_random position: {0, 0, 0.05};
			species dummy_car aspect: base position: {0, 0, 0.05};
			species motorbike_random position: {0, 0, 0.05};
			species bus_random position: {0, 0, 0.05};
			species lorry_random position: {0, 0, 0.05};

			mesh instant_heatmap scale: 0 above: 0.5 triangulation: true position: {0, 0, 0.01} transparency: 0.2 color: scale(zone_colors1) smooth: 0;
			// Declared after the mesh on purpose: in a GAMA display layer order
			// is draw order, so a species listed before the mesh is painted over
			// by it and never appears.
			species AQI position: {0, 0, 0.02};
		}

	}

}

experiment MainExp autorun: false {
	// Same CSV-driven fleet as expProj; see main2.gaml load_traffic_counts.
	parameter "Study area half-width (m)" var: study_half_size <- 1000 min: 300 max: 3000 step: 100;
	parameter "Fleet scale" var: fleet_scale <- 1.0 min: 0.1 max: 3.0 step: 0.1;
	parameter "% Electrical cars" var: n_cars <- 0 min: 0 max: max_cars;
	parameter "% Electrical motorcycles" var: n_motorbikes <- 0 min: 0 max: max_motorbikes;
	parameter "% Electrical buses" var: n_bus <- 0 min: 0 max: max_bus;
	parameter "% Electrical lorries" var: n_lorries <- 0 min: 0 max: max_lorries;
	output synchronized: false {
			layout #split parameters: false navigator: false editors: false consoles: true toolbars: false tray: false tabs: false controls: true;
//		display "project" type: 3d {
//			image ("../includes/ocplight.png");
//		}

		display main type: opengl background: #black axes: false {
			overlay position: {50 #px, 50 #px} size: {1 #px, 1 #px} background: #black border: #black rounded: false {
			//for each possible type, we draw a square with the corresponding color and we write the name of the type
			//				draw "Estimated pollution based on realtime traffic incident and AQ sensors" at: {0, 0} anchor: #top_left color: #white font: title;
				float y <- 10 #px;
				draw rectangle(40 #px, 160 #px) at: {20 #px, y + 60 #px} wireframe: true color: #white;
				// Iterating .keys rather than .pairs: in this GAMA version a
				// pair from map<rgb, string>.pairs is pair<unknown, unknown>,
				// so p.key/p.value are unknown and everything built from them
				// fails -- rgb(unknown, 1.0), draw(unknown), and the ternary
				// below, which needs a bool condition. .keys keeps the
				// declared rgb type and legends[k] the declared string.
				loop key over: reverse(pollutions.keys) {
					string label <- pollutions[key];
					draw square(40 #px) at: {20 #px, y} color: rgb(key, 1.0);
					draw label at: {60 #px, y} anchor: #left_center color: #white font: text;
					y <- y + 40 #px;
				}

				y <- y + 340 #px;
				draw "Icons" at: {0, y} anchor: #top_left color: #white font: title;
				y <- y + 40 #px;
				//				draw rectangle(40 #px, 120 #px) at: {20 #px, y + 40 #px} wireframe: true color: #white;
				// Same .keys pattern as the pollution legend above, for the same
				// typing reason. Shape comes from legends_geom4, which is
				// map<string, geometry> and so yields a real geometry rather
				// than an unknown that draw cannot accept.
				loop key over: legends.keys {
					string label <- legends[key];
					geometry icon <- legends_geom4[label];
					draw icon at: {20 #px, y} color: key;
					draw label at: {60 #px, y} anchor: #left_center color: #white font: text;
					y <- y + 40 #px;
				}

				draw "Estimated realtime pollution" at: {220 #px, -20 #px} color: #white font: font(32);
			}

			//			light #ambient intensity: 256;
			// Penang: the Hanoi camera and the two vindark.png raster
			// mini-maps were removed (Hanoi imagery/coordinates); the panels
			// below are positioned from world.shape instead.
			species road refresh: false;// position: {0, 0, 0.02};
			species study_boundary;// position: {0, 0, 0.015};
			species building refresh: false;
			species car_random;
			species dummy_car aspect: base;
			species motorbike_random;
			// Each counted class draws its own aspect (traffic2.gaml) so the
			// mix is readable, and each honours is_electrical so moving a
			// slider is visible on the map, not only in the numbers.
			species bus_random;
			species lorry_random;

			mesh instant_heatmap scale: 4 above: 1 triangulation: true transparency: 0.5 color: scale(zone_colors1) smooth: 1;
			// The measured ambient station. Declared after the mesh so it is
			// drawn on top of it: layer order = draw order in a GAMA display,
			// and while this sat before the mesh the heat map painted over it
			// every cycle, so the marker never appeared on screen at all.
			species AQI position: {0, 0, 0.02};
			// Panels are declared last so they are drawn on top of the heat map
			// (layer order = draw order in a GAMA display).
			species progress_bar position: {0, 0, 0.0001};
			species line_graph_aqi position: {0, 0, 0.005};
			species param_indicator position: {0, 0, 0.01};
			event #mouse_down {
				// Click position is mapped to a fraction of a bar through the
				// bar's own x and width, then clamped. Everything about the
				// mapping is reported on every click, so the console shows
				// exactly what the bar thought was clicked.
				point p <- #user_location;
				bool hit <- false;
				string rep <- "click x=" + string(p.x) + " y=" + string(p.y);

				progress_bar pb_cars <- first(progress_bar where (each.title = lb_cars));
				progress_bar pb_moto <- first(progress_bar where (each.title = lb_motobike));
				progress_bar pb_bus <- first(progress_bar where (each.title = lb_bus));
				progress_bar pb_lorry <- first(progress_bar where (each.title = lb_lorries));

				if (p overlaps pb_cars.bound) {
					hit <- true;
					n_cars <- min(max_cars, max(0, int(max_cars * pb_cars.fraction_at(p))));
					rep <- rep + " | CARS frac=" + string(pb_cars.fraction_at(p))
					      + " n_cars=" + string(n_cars) + "/" + string(max_cars);
				}
				if (p overlaps pb_moto.bound) {
					hit <- true;
					n_motorbikes <- min(max_motorbikes, max(0, int(max_motorbikes * pb_moto.fraction_at(p))));
					rep <- rep + " | MOTO frac=" + string(pb_moto.fraction_at(p))
					      + " n_motorbikes=" + string(n_motorbikes) + "/" + string(max_motorbikes);
				}
				if (p overlaps pb_bus.bound) {
					hit <- true;
					n_bus <- min(max_bus, max(0, int(max_bus * pb_bus.fraction_at(p))));
					rep <- rep + " | BUS frac=" + string(pb_bus.fraction_at(p))
					      + " n_bus=" + string(n_bus) + "/" + string(max_bus);
				}
				if (p overlaps pb_lorry.bound) {
					hit <- true;
					n_lorries <- min(max_lorries, max(0, int(max_lorries * pb_lorry.fraction_at(p))));
					rep <- rep + " | LORRY frac=" + string(pb_lorry.fraction_at(p))
					      + " n_lorries=" + string(n_lorries) + "/" + string(max_lorries);
				}
				if (not hit) {
					rep <- rep + " | NO BAR HIT";
				}
				write rep;
			}

		}

	}

}