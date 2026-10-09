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
		// Nine buttons now, so each is narrower than the original seven.
		float bw <- W * 0.098;
		float bh <- H * 0.06;
		float gap <- W * 0.006;
		float x0 <- ctr.x - W * 0.46;
		float by <- ctr.y + H * 0.85;
		create policy_button with: [x::x0, y::by, width::bw, height::bh, code::"charge", label::"Cong. charge", active::pol_congestion_charge];
		create policy_button with: [x::x0 + (bw + gap), y::by, width::bw, height::bh, code::"lez", label::"Low emission zone", active::pol_low_emission_zone];
		create policy_button with: [x::x0 + 2 * (bw + gap), y::by, width::bw, height::bh, code::"pt", label::"PT boost", active::pol_public_transport];
		create policy_button with: [x::x0 + 3 * (bw + gap), y::by, width::bw, height::bh, code::"signal", label::"Signal timing", active::pol_signal_timing];
		create policy_button with: [x::x0 + 4 * (bw + gap), y::by, width::bw, height::bh, code::"telework", label::"Telework", active::pol_telework];
		create policy_button with: [x::x0 + 5 * (bw + gap), y::by, width::bw, height::bh, code::"evenodd", label::"Even-odd days", active::pol_even_odd];
		create policy_button with: [x::x0 + 6 * (bw + gap), y::by, width::bw, height::bh, code::"roadtax", label::"Road tax", active::pol_road_tax];
		create policy_button with: [x::x0 + 7 * (bw + gap), y::by, width::bw, height::bh, code::"suppression", label::"Fire suppression", active::pol_fire_suppression];
		create policy_button with: [x::x0 + 8 * (bw + gap), y::by, width::bw, height::bh, code::"fires", label::"Fires on/off", active::pol_fires_enabled];
		// Map overlay for the zone policies; built here because its own
		// geometry prep waits for study_area via a reflex.
		create policy_overlay;
	}

	// active_policies_string() now lives in global_vars.gaml so that
	// traffic.gaml can refresh the panel too (policy cannot be imported
	// from traffic: the import would be circular).

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
		if (code = "evenodd") {
			// Switching off releases everyone the rule had parked; the
			// live gate in traffic.gaml re-applies it when switched on.
			if (not pol_even_odd) {
				ask (vehicle_random where (each.active_today = false)) { active_today <- true; }
			}
		}
		if (code = "roadtax") {
			// road_tax_share of the fleet buys the exemption: payers may
			// drive on any day under the even-odd rule. Switching off
			// cancels every pass.
			if (pol_road_tax) {
				ask vehicle_random { road_tax_paid <- false; }
				n <- int(length(vehicle_random) * road_tax_share);
				ask n among vehicle_random { road_tax_paid <- true; }
			} else {
				ask vehicle_random { road_tax_paid <- false; }
			}
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

// Map-level feedback for the policies that change geography rather than
// only fleet numbers: the congestion-charge cordon and the low emission
// zone are painted directly on the map while active. The geometries are
// built lazily because study_area only exists after main.gaml's init has
// run (this species' reflex sees it one cycle later).
species policy_overlay {
	geometry cordon;
	geometry lez;
	bool ready <- false;

	reflex prepare when: (not ready) and (study_area != nil) {
		cordon <- circle(study_half_size * 0.45) at_location study_area.location;
		lez <- circle(study_half_size * 0.85) at_location study_area.location;
		ready <- true;
	}

	aspect default {
		if (ready and pol_low_emission_zone) {
			draw lez color: rgb(0, 200, 0, 50) border: #lime;
			draw "LOW EMISSION ZONE" at: (lez.location + {0.0, study_half_size * 0.65})
			    color: #lime anchor: #center font: font(40);
		}
		if (ready and pol_congestion_charge) {
			draw cordon.contour color: #red;
			draw cordon.contour + 3 color: #red;
			draw "CONGESTION CHARGE" at: (cordon.location + {0.0, -study_half_size * 0.55})
			    color: #red anchor: #center font: font(40);
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
			match "evenodd" { pol_even_odd <- not pol_even_odd; active <- pol_even_odd; }
			match "roadtax" { pol_road_tax <- not pol_road_tax; active <- pol_road_tax; }
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
