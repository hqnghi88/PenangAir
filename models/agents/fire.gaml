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
	// re-seeds towards this after decay/suppression removes some. Kept low:
	// fires now damage infrastructure, so a handful is plenty to split the
	// road network into pockets that traffic has to route around.
	int nb_fires <- 1;
	// Per-fire strength multiplier and footprint radius (m).
	float fire_intensity <- 1.0;
	float fire_radius <- 60.0;
	// Per-cycle PM injected per fire (times intensity). Sized so one fire
	// clearly dominates its neighbourhood on the heat map: a car puts
	// ~3 units into one cell per cycle, a bus ~14, so a fire needs tens
	// per cell to read as the pollution source it is.
	float fire_emission_scale <- 45.0;
	// Per-cycle probabilities of a new ignition site and of an existing
	// fire throwing a spark to a neighbour. Both cut well below the old
	// 0.05 / 0.02 so fires stay a rare event rather than a shower.
	float fire_ignite_rate <- 0.02;
	float fire_spread_rate <- 0.008;
	// Hard cap on live fires so a spread run cannot stall the reflex loop.
	int max_fires <- 4;

	// Infrastructure damage, applied every burn cycle to roads and
	// buildings inside a fire's footprint. Damage accumulates while the
	// fire burns and is permanent once the fire is out (turn fires off and
	// the burnt network stays burnt).
	//   roads:     ~0.06/cycle at intensity 1.0 -> closed after ~10 cycles
	//   buildings: ~0.12/cycle at intensity 1.0 -> collapse after ~5 cycles
	// The limits themselves live in global_vars.gaml so traffic.gaml's
	// aspects can read them without a circular import.
	float fire_road_damage <- 0.06;
	float fire_bldg_damage <- 0.12;
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
			// The fire eats the infrastructure around it. Roads inside the
			// footprint take damage every cycle until they close (drawn
			// charred, weighted out of the route solver), which is what
			// splits the network apart; buildings collapse to rubble.
			ask (road at_distance radius) {
				fire_damage <- fire_damage + myself.intensity * fire_road_damage;
				if (fire_damage >= road_damage_limit) {
					closed <- true;
				}
			}
			ask (building at_distance radius) {
				fire_damage <- fire_damage + myself.intensity * fire_bldg_damage;
				if (fire_damage >= bldg_damage_limit) {
					destroyed <- true;
				}
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
