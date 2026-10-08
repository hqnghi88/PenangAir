/***
* Name: fire
* Author: hqnghi
* Description: Open-burning fires as an additional pollution source.
* Tags: fire, pollution
***/

model fire

import "../global_vars.gaml"
import "pollution.gaml"

global {
	// Whether any fires are spawned at all.
	bool fire_enabled <- true;
	// Target number of simultaneously burning fires; the maintenance reflex
	// re-seeds towards this after decay/suppression removes some.
	int nb_fires <- 3;
	// Per-fire strength multiplier and footprint radius (m).
	float fire_intensity <- 1.0;
	float fire_radius <- 60.0;
	// Per-cycle probabilities of a new ignition site and of an existing
	// fire throwing a spark to a neighbour.
	float fire_ignite_rate <- 0.05;
	float fire_spread_rate <- 0.02;
	// Hard cap on live fires so a spread run cannot stall the reflex loop.
	int max_fires <- 12;

	// Fires are (re)seeded here rather than in an init block: study_area is
	// only built in main.gaml's init, which runs after this one, so
	// creating agents here would see a nil study_area. Every creation
	// passes an explicit location inside the study box.
	reflex maintain_fires when: every(5 #cycle) {
		if (not fire_enabled) {
			ask fire_source { do die; }
		} else {
			// Ignition: top up towards the target population, slowly.
			if (length(fire_source) < nb_fires and length(fire_source) < max_fires and flip(fire_ignite_rate)) {
				create fire_source with: [location::any_location_in(study_area)];
			}
			// Spread: an established fire may throw a new one nearby.
			// Fire suppression (policy) cuts the chance. Iterating a
			// snapshot so fires created here are not visited in the same
			// pass, which would needlessly re-seed from them.
			float spread_scale <- pol_fire_suppression ? 0.2 : 1.0;
			list<fire_source> snapshot <- list<fire_source>(fire_source);
			loop f over: snapshot {
				if (length(fire_source) < max_fires and flip(fire_spread_rate * spread_scale)) {
					point cand <- f.location + {rnd(-fire_radius * 2, fire_radius * 2), rnd(-fire_radius * 2, fire_radius * 2)};
					if (study_area covers cand) {
						create fire_source with: [location::cand];
					}
				}
			}
		}
		ask (param_indicator where (each.name = lb_ActiveFires)) {
			do update(string(length(fire_source)));
		}
	}
}

species fire_source {
	float intensity <- 1.0;
	float age <- 0.0;
	float max_age <- 200.0 + rnd(300.0);
	float radius <- 60.0;

	init {
		intensity <- fire_intensity * (0.7 + rnd(0.6));
		radius <- fire_radius * (0.7 + rnd(0.6));
	}

	reflex burn {
		age <- age + 1;
		// Suppression shortens the burn; unsuppressed fires decay slowly.
		intensity <- intensity - (pol_fire_suppression ? 0.02 : 0.006);
		if (intensity <= 0.05 or age > max_age) {
			do die;
		} else {
			// PM injected at the fire and points on its rim, scaled like the
			// vehicle emissions so both sources share one heat-map magnitude.
			float e <- intensity * 2.0 * EMISSION_SCALE;
			instant_heatmap[location] <- instant_heatmap[location] + e;
			loop a from: 0 to: 315 step: 45 {
				point p <- location + {cos(a) * radius, sin(a) * radius};
				instant_heatmap[p] <- instant_heatmap[p] + e * 0.4;
			}
		}
	}

	aspect default {
		draw circle(radius) color: rgb(255, 69, 0, 140) border: #yellow;
		draw circle(radius * 0.5) color: rgb(255, 165, 0, 180);
	}
}
