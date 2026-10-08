/***
* Name: policy
* Author: hqnghi
* Description: Policy intervention switches and their one-shot/continuous effects.
* Tags: policy
***/

model policy

import "../global_vars.gaml"
import "traffic.gaml"
import "fire.gaml"

global {
	// One-shot policy effects and live re-scaling for the road network.
	init {
		float W <- world.shape.width;
		float H <- world.shape.height;
		point ctr <- world.shape.location;
		// One row of clickable policy buttons below the world envelope.
		float bw <- W * 0.13;
		float bh <- H * 0.06;
		float gap <- W * 0.008;
		float x0 <- ctr.x - W * 0.49;
		float by <- ctr.y + H * 0.85;
		create policy_button with: [x::x0, y::by, width::bw, height::bh, code::"charge", label::"Congestion charge", active::pol_congestion_charge];
		create policy_button with: [x::x0 + (bw + gap), y::by, width::bw, height::bh, code::"lez", label::"Low emission zone", active::pol_low_emission_zone];
		create policy_button with: [x::x0 + 2 * (bw + gap), y::by, width::bw, height::bh, code::"pt", label::"PT boost", active::pol_public_transport];
		create policy_button with: [x::x0 + 3 * (bw + gap), y::by, width::bw, height::bh, code::"signal", label::"Signal timing", active::pol_signal_timing];
		create policy_button with: [x::x0 + 4 * (bw + gap), y::by, width::bw, height::bh, code::"telework", label::"Telework", active::pol_telework];
		create policy_button with: [x::x0 + 5 * (bw + gap), y::by, width::bw, height::bh, code::"suppression", label::"Fire suppression", active::pol_fire_suppression];
		create policy_button with: [x::x0 + 6 * (bw + gap), y::by, width::bw, height::bh, code::"fires", label::"Fires on/off", active::pol_fires_enabled];
	}

	// Comma-separated list of the active switches, for the UI panel.
	string active_policies_string() {
		string on <- "";
		if (pol_congestion_charge) { on <- on + "Charge, "; }
		if (pol_low_emission_zone) { on <- on + "LEZ, "; }
		if (pol_public_transport) { on <- on + "PT boost, "; }
		if (pol_signal_timing) { on <- on + "Signals, "; }
		if (pol_telework) { on <- on + "Telework, "; }
		if (pol_fire_suppression) { on <- on + "Fire supp., "; }
		if (on = "") { return "none"; }
		return on;
	}

	action refresh_policy_ui() {
		ask (param_indicator where (each.name = lb_ActivePolicies)) {
			do update(myself.active_policies_string());
		}
	}

	// The one-shot effect of switching a policy on. Called by the button's
	// toggle action through the world agent (global actions are not
	// directly callable from a species).
	action apply_policy(string code) {
		int n;
		if (code = "charge" and pol_congestion_charge) {
			// 30% of private car traffic shifts away under the charge.
			n <- int(length(car_random) * 0.3);
			ask n among car_random { do die; }
			max_cars <- max(1, length(car_random));
		}
		if (code = "lez" and pol_low_emission_zone) {
			// Heavy emitters are pushed out; the survivors are modernised.
			n <- int(length(lorry_random) * 0.3);
			ask n among lorry_random { do die; }
			ask (lorry_random + bus_random) { modernized <- true; }
			max_lorries <- max(1, length(lorry_random));
			max_bus <- max(1, length(bus_random));
		}
		if (code = "pt" and pol_public_transport) {
			// Extra buses on the network, funded by the policy.
			create bus_random number: 15 with: [type::"bus"];
			max_bus <- length(bus_random);
		}
		if (code = "signal") {
			// Optimised signal plans raise effective junction capacity.
			float f <- pol_signal_timing ? 1.5 : (1.0 / 1.5);
			ask road { capacity <- capacity * f; }
		}
		if (code = "telework" and pol_telework) {
			// 20% of all road traffic stays home.
			n <- int(length(vehicle_random) * 0.2);
			ask n among vehicle_random { do die; }
			max_cars <- max(1, length(car_random));
			max_motorbikes <- max(1, length(motorbike_random));
			max_bus <- max(1, length(bus_random));
			max_lorries <- max(1, length(lorry_random));
		}
		if (code = "fires") {
			fire_enabled <- pol_fires_enabled;
			if (not pol_fires_enabled) {
				ask fire_source { do die; }
			}
		}
		if (length(progress_bar) > 0) {
			ask first(progress_bar where (each.title = lb_cars)) { max_val <- max_cars; }
			ask first(progress_bar where (each.title = lb_motobike)) { max_val <- max_motorbikes; }
			ask first(progress_bar where (each.title = lb_bus)) { max_val <- max_bus; }
			ask first(progress_bar where (each.title = lb_lorries)) { max_val <- max_lorries; }
			ask first(progress_bar where (each.title = lb_rates_EG)) {
				max_val <- max_cars + max_bus + max_motorbikes + max_lorries;
			}
		}
	}
}

species policy_button {
	float x;
	float y;
	float width;
	float height;
	string code;
	string label;
	bool active;
	geometry bound;

	action toggle() {
		switch code {
			match "charge" { pol_congestion_charge <- not pol_congestion_charge; active <- pol_congestion_charge; }
			match "lez" { pol_low_emission_zone <- not pol_low_emission_zone; active <- pol_low_emission_zone; }
			match "pt" { pol_public_transport <- not pol_public_transport; active <- pol_public_transport; }
			match "signal" { pol_signal_timing <- not pol_signal_timing; active <- pol_signal_timing; }
			match "telework" { pol_telework <- not pol_telework; active <- pol_telework; }
			match "suppression" { pol_fire_suppression <- not pol_fire_suppression; active <- pol_fire_suppression; }
			match "fires" { pol_fires_enabled <- not pol_fires_enabled; active <- pol_fires_enabled; }
		}
		write "Policy '" + label + "' -> " + (active ? "ON" : "OFF");
		// Global actions are reachable through the world agent only. The
		// switch code is copied to a local first so the nested ask can read
		// it from the enclosing block.
		string c <- code;
		ask world {
			do apply_policy(c);
			do refresh_policy_ui();
		}
	}

	aspect default {
		if (bound = nil) {
			bound <- polygon([{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}, {x, y}])
				at_location {x + width / 2, y + height / 2, Z_LVL2};
		}
		draw rectangle(width, height) at: {x + width / 2, y + height / 2, Z_LVL2}
			color: active ? #darkgreen : #grey border: #white;
		draw label at: {x + width / 2, y + height / 2, Z_LVL3} anchor: #center color: #white font: font("Arial", 12, #bold);
	}
}
