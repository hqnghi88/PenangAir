/***
* Name: pollution
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model pollution

import "../global_vars.gaml"
import "traffic.gaml"
global {
	field instant_heatmap <- field(size, size);
	// Live measured PM2.5 (ug/m3) from the AQI feed, pushed in by api_loader's
	// loadAQ. main.gaml's update reflex injects it as a uniform background
	// (with a decay step) so the modelled field reflects the real ambient read.
	float ambient_pm25 <- 0.0;
	// Simulation cycle counter used to seed the ambient reading only briefly.
	int cycle_count <- 0;
	// How strongly the measured ambient reading enters the heat map (0 = off,
	// 1 = full PM2.5 value as a uniform floor). Kept small so it tints the
	// background without overwriting the traffic gradient.
	float AMBIENT_SCALE <- 1.0;
	// Constants
	map<string, float> ALLOWED_AMOUNT <- ["CO" :: 30000 * 10e-6, "NOx" :: 200 * 10e-6, "SO2" :: 350 * 10e-6, "PM" :: 300 * 10e-6]; // Unit: g/m3
	// g/km. Car and motorbike values come from the original VinUni model;
	// bus and lorry are standard diesel urban figures. Lorries matter in
	// Penang because the survey counts a separate lorries column and their
	// PM/NOx factors sit an order of magnitude above a car's.
	map<string, map<string, float>> EMISSION_FACTOR <- ["motorbike" :: ["CO" :: 3.62, "NOx" :: 0.3, "SO2" :: 0.03, "PM" :: 0.1], "car" :: ["CO" :: 3.62, "NOx" :: 1.5, "SO2" :: 0.17, "PM" :: 0.1], "bus" :: ["CO" :: 13.0, "NOx" :: 7.0, "SO2" :: 0.5, "PM" :: 0.9], "lorry" :: ["CO" :: 15.0, "NOx" :: 9.0, "SO2" :: 0.6, "PM" :: 1.0]];

	// Display scaling applied to every vehicle's contribution on top of its
	// per-kilometre factor. Raised from 0.15 to 0.6 so congestion is visible
	// with the CSV-sized fleet.
	//
	// Deliberately a separate multiplier rather than dividing the numbers in
	// EMISSION_FACTOR: those are published g/km figures, and main.gaml's update
	// reflex is written specifically so the heat map does not contradict the
	// factors the model quotes. Scaling them here keeps the real values
	// intact and makes the whole heat-map magnitude one adjustable knob.
	//
	// main.gaml's `diff` reflex spreads instant_heatmap every cycle, so the
	// field settles to a quasi-steady maximum rather than growing without
	// bound: measured at 0.2 it levelled off near 365, and the level scales
	// linearly with this constant.
	float EMISSION_SCALE <- 0.6;
	 
	init {
	//		sizeCoeff <- 100;
		sizeCoeff <- 0.2;
// aqi_site_4326: the live-feed loader lives in agents/traffic.gaml,
		// which cannot see main.gaml's site_merc. site_4326 rather than
		// site_merc because the latter is only built in main.gaml's init,
		// which has not run yet when this experiment init runs.
		create api_loader with: [aqi_site_4326::site_4326];
		ask api_loader { 
//			do run_thread interval: 600 #second;
		}

	}
	matrix<float> mat_diff <- matrix(
		[[1 / 20, 1 / 20, 1 / 20], [1 / 20, 3 / 5 * pollutant_decay_rate, 1 / 20], [1 / 20, 1 / 20, 1 / 20]]); 
	

	reflex diff {
		diffuse "phero" on: instant_heatmap matrix: mat_diff;
	}
}
species AQI {
	geometry shape <- circle(30);
	string description;
	float aqi;
	// Measured PM2.5 in ug/m3. Carried separately from the dimensionless US-AQI
	// index because only PM2.5 is a concentration comparable with the field the
	// vehicles write into.
	float pm25;
	float noise <- 0.0;

	// Deliberately does NOT write into instant_heatmap.
	//
	// It used to seed the measured PM2.5 at this station every cycle. That was
	// wrong for two reasons, both measured rather than argued:
	//
	//  - main.gaml's decay reflex is commented out (main.gaml:581), so
	//    anything injected per cycle accumulates against diffusion alone.
	//    Injecting at `location` made one cell outrun the spread and left a
	//    permanent cone for the whole run.
	//  - The feed's single ~9 km cell covers this entire 2 km map, so its
	//    correct spatial form is uniform, not a point. Seeding the whole field
	//    instead removed the cone but flattened the cloud completely: measured
	//    max == min == 18.99 by cycle 4000, with the traffic structure gone.
	//
	// A regional concentration cannot be added to an accumulation-only field
	// without either spiking it or erasing what is already there. The reading
	// is therefore reported rather than simulated: it appears in the marker
	// label, carrying the cell it was measured at, and in the side panel.

	// A small dot, not the original label: at a 2 km study width a 32 pt
	// number is unreadable and the labels collided with the side panels.
	// description carries the measured value, so the dot is traceable back to
	// the reading that seeded this part of the heat map. Drawn at the dot's own
	// location with perspective: false so it stays upright and legible.
	aspect default {
		// Deliberately outside the zone_colors1 palette the heat map uses, so
		// the measured region is separable from modelled traffic by colour
		// alone.
		//
		// Solid and large rather than a thin ring: the previous outline was
		// ~86 m across on a 2 km map, about 4% of the visible width, and read
		// as almost nothing next to the heat map. A filled disc with a heavy
		// border is visible against any cell colour behind it.
		//
		// Filled in the heat-map palette's own terms would be invisible, since
		// one region colour can be arbitrarily dark; a flat cyan fill plus a
		// white edge holds up on both ends of the scale.
		draw circle(AQI_MARKER_RADIUS + pm25 * 2.0) color: #cyan border: #white at: location;
		// Label offset above the disc so it does not sit on the fill, and drawn
		// on top so it stays legible over both the disc and the heat map.
		draw description color: #white at: {location.x, location.y + AQI_MARKER_RADIUS * 0.5} perspective: false font: font("SansSerif", 9, #bold);
	}
}



species api_loader skills: [thread] {
	// Where the AQI feed's single reading is shown, in EPSG:4326: the study
	// site, which is the only position inside the 2 km world envelope that
	// can display the reading. This file cannot see main.gaml's site_merc,
	// so the experiment sets it when it creates the loader. Projected at
	// use time, not creation time, because the world projection is not
	// ready during the experiment's init.
	point aqi_site_4326;

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
		// Where the reading was actually taken, echoed back by the feed. The
		// feed snaps the requested coordinate to the centre of its own ~9 km
		// grid cell, so this cell sits roughly 2 km south-west of the request.
		// Kept for the label only: the map's world geometry is
		// envelope(penang_roads.shp), which spans only 2.01 x 2.00 km
		// (lon 100.30706..100.32510, lat 5.40064..5.41856). The cell is
		// outside that envelope, so placing the marker on it renders the
		// marker off-map and invisible at the default view.
		float cell_lat <- 0.0;
		float cell_lon <- 0.0;
		try {
			json_file
			sss <- json_file("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=5.4096&longitude=100.3161&current=us_aqi,pm2_5&timezone=auto");
			map<string, unknown> c <- sss.contents;
			map<string, unknown> cur <- c["current"];
			if (cur != nil and cur["us_aqi"] != nil) {
				aqi_val <- float(cur["us_aqi"]);
				pm25_val <- float(cur["pm2_5"]);
				ambient_pm25 <- pm25_val;
			}

			if (c["latitude"] != nil and c["longitude"] != nil) {
				cell_lat <- float(c["latitude"]);
				cell_lon <- float(c["longitude"]);
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
			
		write "AQI "+aqi_val;
			// One station, at the study site. This is the only position inside the
			// 2 km world envelope where the reading can be shown at all; the
			// cell it was measured at is off-map. The label carries the cell
			// coordinates so the marker's position is not mistaken for the
			// position of the measurement.
			//
			// Projected here rather than in main.gaml: this file cannot see
			// site_merc, and the world projection is not usable while the
			// experiment's own init is still running.
			point here <- to_GAMA_CRS(aqi_site_4326, "EPSG:4326").location;
			create AQI with: [
				location::here,
				aqi::aqi_val,
				pm25::pm25_val,
				noise::0.0,
				description::("cell " + string(round(cell_lat * 1000.0) / 1000.0) + ", "
					+ string(round(cell_lon * 1000.0) / 1000.0)
					+ "  AQI " + string(int(aqi_val)) + "  PM2.5 "
					+ string(round(pm25_val * 10) / 10.0) + " ug/m3")
			];
			ask (param_indicator where (each.name = lb_AQI_update)) {
				do update("US-AQI " + string(int(aqi_val)) + " PM2.5 " + string(round(pm25_val * 10) / 10.0) + " @ " + string(date("now")));
			}
		}

	}

	action loadtraffic() {
//		ask traffic_incident {
//			do die;
//		}
//
//		// No keyless realtime incident feed exists (the old Bing Maps key is
//		// dead and was hardcoded to Hanoi), so incidents are derived from the
//		// simulation itself: the most-loaded roads become live congestion
//		// incidents. Each incident keeps spawning dummy_car flow through the
//		// existing traffic_incident reflex, like the API ones used to.
//		map<road, int> load <- road as_map (each::length(vehicle_random overlapping (each.shape + 12.0)));
//		list<road> ordered <- list<road>(road sort_by (load[each]));
//		int made <- 0;
//		loop k from: 0 to: length(ordered) - 1 {
//			road r <- ordered[length(ordered) - 1 - k];
//			if (load[r] >= 3 and made < 5) {
//				create traffic_incident with: [
//					location::r.shape.location,
//					description::("congestion x" + string(load[r]) + " on " + string(r.shape.location))
//				];
//				made <- made + 1;
//			}
//		}
//		ask (param_indicator where (each.name = lb_Traffic_Incident)) {
//			do update(string(made) + " live congestion incidents @ " + date("now"));
//		}

	}
}

