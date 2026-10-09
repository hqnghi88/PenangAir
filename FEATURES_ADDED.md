# PenangAir - New Features Added

1. **More Pollution Sources (Fire)**
- Added fire sources (open burning) as pollution emitters
- `agents/fire.gaml`: `fire_source` species and dynamics (ignition, spread, decay, suppression)
- Each fire injects PM into `instant_heatmap` at its centre, a mid-ring and the rim
  (8 points each), scaled by `fire_emission_scale` (45) so one fire clearly
  dominates its neighbourhood: cars add ~3 units/cell/cycle, buses ~14,
  a fire ~27+ per cell while it burns
- Parameters: `fire_enabled`, `nb_fires`, `fire_intensity`, `fire_radius`, `fire_ignite_rate`,
  `fire_spread_rate`, `max_fires`; suppression driven by the `pol_fire_suppression` policy switch
- Dispersion widened: `wind_matrix` / `mat_diff_calm` are 5x5 kernels (~30% stays, the
  rest travels up to two cells per cycle). With the **Wind** button on, the breeze
  wanders realistically — direction veers and strength gusts every 10 cycles (random
  walk), rebuilding the kernel so plumes drift like wind-borne ash; off it spreads
  symmetrically. Every kernel sums to exactly 0.994, so overall levels never change
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
- `models/agents/policy.gaml`: 9 clickable policy buttons below the map
  - **Congestion charge** — removes 30% of private car traffic
  - **Low emission zone** — removes 30% of lorries, modernises surviving lorries/buses
    (half PM/NOx via `modernized`)
  - **PT boost** — adds 15 buses to the fleet
  - **Signal timing** — road capacity x1.5 (toggling off divides it back)
  - **Telework** — removes 20% of all vehicles
  - **Even-odd days** — roads are designated at seed time: ~30% even-only,
    ~30% odd-only, ~40% open. The even/odd switch follows the real calendar:
    parity is the day of month of the actual current date (`date("now")`), so
    the model agrees with the wall clock. A non-payer may stand on restricted
    road R only when R matches both today's parity and its own plate — otherwise it
    waits (grey, speed 0, no load, no emissions) until that parity's day, or
    is turned back to an admissible road. Only part of the network is ever
    denied, never all of it. Plate dots: yellow (even) / magenta (odd).
  - **Road tax** — a `road_tax_share` fraction of the fleet (experiment parameter,
    default 30%, picked randomly on toggle-on; later additions pay with the same
    probability) buys an exemption: payers go anywhere, every day, marked with a
    gold ring. Switching the policy off cancels all passes.
  - **Fire suppression** — 5x slower spread, faster burn-out
  - **Fires on/off** — ignition/enable switch, kills live fires when off
- Traffic-incident dummy cars are exempt from the even-odd gate so they still
  reach their target and die as designed.

**Map-visible feedback (every policy changes the map, not just the label):**
- Congestion charge — red cordon ring + "CONGESTION CHARGE" label over the centre;
  every street inside the cordon is overlaid in amber
- Low emission zone — translucent green disc + "LOW EMISSION ZONE" label;
  surviving buses/lorries turn lime green (modernised)
- PT boost — every bus gets a blue policy halo (plus the 15 added buses)
- Signal timing — capacity x1.5; road colours ease towards lighter shades as
  congestion clears (smoothed, no instant repaint)
- Telework / congestion charge — the fleet visibly thins out
- Even-odd — only the designated street subset changes: open-today restricted
  roads wear their parity colour (yellow = even-only, magenta = odd-only),
  denied-today roads turn dark red; vehicles waiting on those roads go grey
  with their plate dot visible
- Road tax — payers are repainted solid gold body + floating gold ring;
  they stay mobile on every day while the even-odd rule is on
- Fire suppression — blue containment ring around each fire
- Fires on/off — fires appear/disappear
- `models/global_vars.gaml`: the `pol_*` switches (shared by fire and policy without a
  circular import) plus the new panel labels
- UI indicators (left column): Traffic Incident, Network Congestion, Active Fires,
  Active Policies; toggles log to the console and refresh the panel live
- Fleet-size bars are re-scaled whenever a policy changes the fleet

Files modified: global_vars.gaml, main.gaml, PenangAir.gaml, agents/traffic.gaml,
agents/visualization.gaml
Files added: agents/fire.gaml, agents/policy.gaml
