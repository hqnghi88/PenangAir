/***
* Name: visualization
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/
model visualization

import "../global_vars.gaml"

global {
	init{
		
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
		create param_indicator with: [x::ui_left, y::ctr.y + H * 0.47 - 50.0 * px + H * 0.06, size::20, name::lb_TrafficSource, value::(use_traffic_data = 1 ? "REAL (traffic_counts.csv)" : "RANDOM (default fleet)"), with_box::true, width::W * 0.30, height::H * 0.05];

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
		
	}
	point midpoint (point a, point b) {
		return (a + b) / 2;
	}

	int get_pollution_threshold(float aqi) {
		int threshold <- 0;
		loop thr over: thresholds_pollution.keys {
			if(aqi > thr) {
				threshold <- thr;
			}
		}
		return threshold;
	}
	
	string get_pollution_state(float aqi) {
		return thresholds_pollution[get_pollution_threshold(aqi)];
	}
	
	rgb get_pollution_color(float aqi) {
		return zone_colors[thresholds_pollution[get_pollution_threshold(aqi)]];		
	}
}

species progress_bar schedules: [] {
	float val;
	float max_val;
	// Position and size
	float x;
	float y;
	float width;
	float height;
	float scale <- 1.0;
	// Descriptions
	string title;
	string left_label;
	string right_label;
	int size_title <- 20;
	int size_labels <- 16;
	geometry bound;
	geometry rect (float rect_x, float rect_y, float rect_width, float rect_height, point loc) {
		return polygon([{rect_x, rect_y}, {rect_x + rect_width, rect_y}, {rect_x + rect_width, rect_y + rect_height}, {rect_x, rect_y + rect_height}, {rect_x, rect_y}]) at_location loc;
	}

	// Maps a world-space point to the fraction of this bar it represents.
	// Uses the bar's own x and width rather than anything derived from the
	// hit geometry, so the mapping stays exact however the aspect is drawn.
	float fraction_at (point p) {
		if (width <= 0.0) {
			return 0.0;
		}
		return min(1.0, max(0.0, (p.x - x) / width));
	}

	action update (float new_val) {
		val <- new_val;
	}

	aspect default {
		// Clamp the filled fraction to [0,1]. This guards two ways it could
		// go wrong: max_val is still 0 on the first draw, because max_cars and
		// friends are only assigned later in the run; and val can overshoot
		// max_val. Either would otherwise give a negative or NaN length and a
		// visibly broken bar.
		float frac <- 0.0;
		if (max_val > 0.0) {
			frac <- min(1.0, max(0.0, val / max_val));
		}
		float length_filled <- width * frac;
		float length_unfilled <- width - length_filled;
		// The hit region depends only on the bar's own geometry, never on
		// val, so it is correct from the first draw and never needs to be
		// recomputed. It is extended below the bar to cover the 0%/100%
		// labels and the percentage readout, which are drawn outside the
		// bar itself and would otherwise be unclickable.
		if (bound = nil) {
			bound <- rect(x - 10.0 * scale, y - 10.0 * scale, width + 20.0 * scale, height + 110.0, {(x - 10.0 * scale) + (width + 20.0 * scale) / 2, (y - 10.0 * scale) + (height + 110.0) / 2, Z_LVL2});
		}
		draw rect(x, y, length_filled, height, {x + length_filled / 2, y + height / 2, Z_LVL2}) color: #cyan;
		draw rect(x + length_filled, y, length_unfilled, height, {(x + length_filled) + length_unfilled / 2, y + height / 2, Z_LVL2}) color: #blue;
		draw (title + ": ") at: {x, y - 10 * scale, Z_LVL2} font: font(size_title) color: palet[TEXT_COLOR];
		draw (left_label) at: {x - 5, y + 40 * scale, Z_LVL2} font: font(size_labels) color: palet[TEXT_COLOR];
		draw (right_label) at: {x + width - 20, y + 40 * scale, Z_LVL2} font: font(size_labels) color: palet[TEXT_COLOR];
		draw (""+int(frac*100)+"%") at:{x+width/2,y+height/2+100,Z_LVL2}font: font(size_labels) color: #red;
	}

} 

species param_indicator {
	float x;
	float y;
	float width;
	float height;
	float size;
	string name;
	string value;
	rgb col <- palet[TEXT_COLOR];
	bool with_RT <- false;
	bool with_box <- false;

	action update (string new_val) {
		value <- new_val;
	}

	aspect default {
		if (with_box) {
			draw rectangle(width, height) color: rgb(#black, 0.5) at: {x + width / 2, y + height / 2, Z_LVL1};
			point center <- world.midpoint({x, y, Z_LVL3}, {x + width, y + height, Z_LVL2});
			draw (name + ": " + (with_RT ? "\n" : "") + value) at: center color: col anchor: #center font: font(size);
		} else {
			draw (name + ": " + (with_RT ? "\n" : "") + value) font: font(size) at: {x, y, Z_LVL2} color: col;
		}

	}

}

species line_graph_aqi parent: line_graph {
	list<float> thresholds;
	int thick_axe <- 5;
	int thick_line <- 5;

	action draw_zones() {
	// Calculate threshold lines' y-pos 
		thresholds <- [];
		loop thr over: thresholds_pollution.keys {
			if (thr < max_val) {
				add calculate_val_y_pos(float(thr)) to: thresholds at: 0;
			}

		}

		add calculate_val_y_pos(max_val) to: thresholds at: 0;

		// Draw the AQI level zones
		loop i from: 0 to: length(thresholds) - 2 {
			float h <- thresholds[i + 1] - thresholds[i];
			draw rectangle(width, h) at: {x + width / 2, thresholds[i] + h / 2, 0.1} color: zone_colors.values[length(thresholds) - 2 - i] /*, 0.5*/;
		}

	}

	action update (float new_val) {
		invoke update(new_val);
	}

	float calculate_val_y_pos (float value) {
		return origin.y - (value / max_val * height);
	}
	action drawing() {
		
		do draw_zones;
		// Draw axis
		do draw_line a: origin b: {x, y, Z_LVL2} thickness: thick_axe col: palet[AQI_CHART];
		do draw_line a: origin b: {x + width, y + height, Z_LVL2} thickness: thick_axe col: palet[AQI_CHART];
		point prev_val_pos <- origin;
		loop i from: 0 to: length(val_list) - 1 {
			if (val_list[i] >= 0) {
				float val_x_pos <- origin.x + width / length(val_list) * i;
				float val_y_pos <- origin.y - (val_list[i] / max_val * height);
				point val_pos <- {val_x_pos, val_y_pos, Z_LVL3};
				// Graph the value
				draw circle(10, val_pos) color: palet[AQI_CHART];
				do draw_line a: val_pos b: prev_val_pos thickness: thick_line col: palet[AQI_CHART];
				prev_val_pos <- val_pos;
			}

		}
		
	}
	aspect default {
		do drawing;
	}

}

species line_graph schedules: [] {
// Params
	float x;
	float y;
	float width;
	float height;
	string label <- "";
	string unit <- "";
	point origin <- {x, y + height, Z_LVL2};
	list<float> val_list <- list_with(20, -1.0);
	float max_val -> max(max(val_list), 50.0);

	action draw_line (point a, point b, int thickness <- 1, rgb col <- #white, int end_arrow <- 0) {
		draw line([a, b]) + thickness at: world.midpoint(a, b) color: col end_arrow: end_arrow;
	}

	action update (float new_val) {
		remove index: 0 from: val_list;
		add item: new_val to: val_list at: length(val_list);
	}

	aspect default {
	// Draw axis
		do draw_line a: origin b: {x, y, Z_LVL2} thickness: 5;
		do draw_line a: origin b: {x + width, y + height, Z_LVL2} thickness: 5;
		point prev_val_pos <- nil;
		loop i from: 0 to: length(val_list) - 1 {
			if (val_list[i] >= 0) {
				float val_x_pos <- origin.x + width / length(val_list) * i;
				float val_y_pos <- origin.y - (val_list[i] / max_val * height);
				point val_pos <- {val_x_pos, val_y_pos, Z_LVL2};
				// Graph the value
				draw circle(10, val_pos) color: #white;
				if (prev_val_pos != nil) {
					do draw_line a: val_pos b: prev_val_pos thickness: 3;
				}

				prev_val_pos <- val_pos;
			}

		}
		// Draw current value indicator
		//		do draw_line({x, prev_val_pos.y}, {x + width, prev_val_pos.y}, 2, #red);
		//		draw label + " " + string(round(val_list[length(val_list) - 1])) + " " + unit at: {x + 50,  prev_val_pos.y - 50, 0.2} font: font(20) color: #orange;
	}

}

species indicator_health_concern_level schedules: [] {
	float x <- 3000.0;
	float y <- 1000.0;
	float width <- 600.0;
	float height <- 200.0;
	rgb color;
	rgb text_color;
	string text;
	point anchor <- #center;
	point midpoint (point a, point b) {
		return (a + b) / 2;
	}

	action update (float aqi) {
		color <- world.get_pollution_color(aqi);
		text <- world.get_pollution_state(aqi);
		text_color <- (text = THRESHOLD_MODERATE) ? #black : #white;
		anchor <- (text = THRESHOLD_UNHEALTHY_SENSITIVE) ? #bottom_center : #center;
	}

	aspect default {
		draw rectangle(width, height) color: color at: {x + width / 2, y + height / 2, Z_LVL2};
		point center <- midpoint({x, y, 0.3}, {x + width, y + height, Z_LVL3});
		draw text at: center color: text_color anchor: anchor font: font(20);
		//	draw "Health concern \n level" at: center - {650, 0, 0} color: #yellow anchor: #bottom_center font: font(20);
	}

}

species boundary {

	reflex disappear when: (cycle > 1) {
		do die;
	}

	aspect {
		draw (shape + 100) - shape wireframe: false color: #pink;
	}

}

species background schedules: [] {
	float x;
	float y;
	float width;
	float height;
	float alpha <- 0.1;

	aspect default {
		draw rectangle(width, height) color: rgb(#black, alpha) at: {x + width / 2, y + height / 2, Z_LVL1};
	}

}