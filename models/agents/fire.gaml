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
	// Per-cycle PM injected per fire (times intensity). Sized so one fire
	// clearly dominates its neighbourhood on the heat map: a car puts
	// ~3 units into one cell per cycle, a bus ~14, so a fire needs tens
	// per cell to read as the pollution source it is.
	float fire_emission_scale <- 45.0;
	// Per-cycle probabilities of a new ignition site and of an existing
	// fire throwing a spark to a neighbour.
	float fire_ignite_rate <- 0.05;
	float fire_spread_rate <- 0.02;
	// Hard cap on live fires so a spread run cannot stall the reflex loop.
	int max_fires <- 12;
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
			// PM injected at the fire, a mid-ring and the rim, so the plume
			// has a filled footprint instead of a hollow outline. Diffusion
			// then smears it into a rising column over the following cycles.
			float e <- intensity * fire_intensity * fire_emission_scale * EMISSION_SCALE;
			instant_heatmap[location] <- instant_heatmap[location] + e;
			loop a from: 0 to: 315 step: 45 {
				point pm <- location + {cos(a) * radius * 0.5, sin(a) * radius * 0.5};
				instant_heatmap[pm] <- instant_heatmap[pm] + e * 0.75;
				point p <- location + {cos(a) * radius, sin(a) * radius};
				instant_heatmap[p] <- instant_heatmap[p] + e * 0.5;
			}
		}
	}

	aspect default {
		draw circle(radius) color: rgb(255, 69, 0, 140) border: #yellow;
		draw circle(radius * 0.5) color: rgb(255, 165, 0, 180);
		// Fire suppression: a blue containment ring clearly outside the
		// flames, floated a little above them to avoid z-fighting.
		if (pol_fire_suppression) {
			draw (circle(radius * 1.6) at_location (location + {0.0, 0.0, 8.0}))
			    color: rgb(30, 144, 255, 70) border: #dodgerblue;
		}
	}
}
