# PenangAir - New Features Added

1. **More Pollution Sources (Fire)**
- Added fire sources (open burning) as pollution emitters
- `agents/fire.gaml`: `fire_source` species and dynamics (ignition, spread, decay, suppression)
- Each fire injects PM into `instant_heatmap` at its centre and on 8 rim points, using the
  same `EMIENT_SCALE` scale as vehicle emissions
- Parameters: `fire_enabled`, `nb_fires`, `fire_intensity`, `fire_radius`, `fire_ignite_rate`,
  `fire_spread_rate`, `max_fires`; suppression driven by the `pol_fire_suppression` policy switch
- Fires are seeded in `main.gaml` init (after `study_area` exists) and topped up every 5 cycles
- Rendered as layered orange/red circles on top of the heat map

2. **Traffic Model Enhancement & Congestion Reduction with Policies**
- `models/agents/traffic.gaml`:
  - Per-road weighted load every 5 cycles (car 1.0, motorbike 0.4, bus 2.0, lorry 3.0)
    clamped against road `capacity` → `road.congestion` in [0,1] and a matching `speed_coeff`
    (road colour now tracks real congestion)
  - `road_weights` penalise congested segments (`perimeter * (1 + 4 * congestion)`), so
    routing automatically prefers free-flow alternatives
  - Vehicles re-solve their path when their segment is >50% congested (plus a 2% random
    re-solve), i.e. queues clear by rerouting
  - `congestion_speed` reflex: up to 80% speed loss on saturated segments
  - Per-vehicle `current_congestion` exposed for emissions and policies
- `models/main.gaml`:
  - Emission penalty: factor `* (1 + current_congestion)` — congested/idling traffic now
    pollutes more per cycle
  - `congestion_incidents` reflex: every 100 cycles, roads at >=60% congestion become
    red `traffic_incident` markers (max 5), with a live count in the side panel

3. **Policy Intervention**
- `models/agents/policy.gaml`: 7 clickable policy buttons below the map
  - **Congestion charge** — removes 30% of private car traffic
  - **Low emission zone** — removes 30% of lorries, modernises surviving lorries/buses
    (half PM/NOx via `modernized`)
  - **PT boost** — adds 15 buses to the fleet
  - **Signal timing** — road capacity x1.5 (toggling off divides it back)
  - **Telework** — removes 20% of all vehicles
  - **Fire suppression** — 5x slower spread, faster burn-out
  - **Fires on/off** — ignition/enable switch, kills live fires when off
- `models/global_vars.gaml`: the `pol_*` switches (shared by fire and policy without a
  circular import) plus the new panel labels
- UI indicators (left column): Traffic Incident, Network Congestion, Active Fires,
  Active Policies; toggles log to the console and refresh the panel live
- Fleet-size bars are re-scaled whenever a policy changes the fleet

Files modified: global_vars.gaml, main.gaml, PenangAir.gaml, agents/traffic.gaml,
agents/visualization.gaml
Files added: agents/fire.gaml, agents/policy.gaml
