/***
* Name: pollution
* Author: hqnghi
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model pollution
import "../global_vars.gaml"

global {
	// Constants
	map<string, float> ALLOWED_AMOUNT <- ["CO"::30000 * 10e-6, "NOx"::200 * 10e-6, "SO2"::350 * 10e-6, "PM"::300 * 10e-6]; // Unit: g/m3
	// g/km. Car and motorbike values come from the original VinUni model;
	// bus and lorry are standard diesel urban figures. Lorries matter in
	// Penang because the survey counts a separate lorries column and their
	// PM/NOx factors sit an order of magnitude above a car's.
	map<string, map<string, float>> EMISSION_FACTOR <- [
		"motorbike"::["CO"::3.62, "NOx"::0.3, "SO2"::0.03, "PM"::0.1],
		"car"::["CO"::3.62, "NOx"::1.5, "SO2"::0.17, "PM"::0.1],
		"bus"::["CO"::13.0, "NOx"::7.0, "SO2"::0.5, "PM"::0.9],
		"lorry"::["CO"::15.0, "NOx"::9.0, "SO2"::0.6, "PM"::1.0]
	];

	// Display scaling applied to every vehicle's contribution on top of its
	// per-kilometre factor, currently 1/20 of the unscaled total.
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
	float EMISSION_SCALE <- 0.2;
	
	// Params
	float cell_volume <- (shape.width / grid_size) * (shape.height / grid_size) * grid_depth;  // Unit: cubic meters	
}
 
species road_cell {
	list<road_cell> neighbors;
	list<agent> affected_buildings;
	
	// Pollutant values
	float co <- 0.0;
	float nox <- 0.0;
	float so2 <- 0.0;
	float pm <- 0.0;

	float aqi;
	float norm_pollution_level -> (co / ALLOWED_AMOUNT["CO"] + nox / ALLOWED_AMOUNT["NOx"] + 
																		so2 / ALLOWED_AMOUNT["SO2"] + pm / ALLOWED_AMOUNT["PM"]) / cell_volume / 4;
	
	reflex calculate_aqi {
		float aqi_co <- (co / cell_volume) / ALLOWED_AMOUNT["CO"] * 100;
		float aqi_nox <- (nox / cell_volume) / ALLOWED_AMOUNT["NOx"] * 100;
		float aqi_so2 <- (so2 / cell_volume) / ALLOWED_AMOUNT["SO2"] * 100;
		float aqi_pm <- (pm / cell_volume) / ALLOWED_AMOUNT["PM"] * 100;
		aqi <- max(aqi_co, aqi_nox, aqi_so2, aqi_pm);
	}
}

