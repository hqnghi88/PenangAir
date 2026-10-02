# Penang Air

A spatially explicit agent-based model, written in [GAMA](https://gama-platform.org), that turns street-level
traffic counts into a population of vehicle agents on a real road network and tracks the pollution they
produce as a diffusing field.

![The interactive MainExp view](Screenshot%202026-10-02%20at%2011.05.38.png)

In the interactive view you can convert any class of vehicle to electric while the model is running and watch
the pollution field respond.

---

## What the model does

1. Reads peak-hour traffic counts per street and per class — cars, buses, lorries, motorcycles.
2. Converts each street's flow into a number of vehicles on the ground using Little's Law, so the fleet
   represents transit time rather than hourly volume.
3. Seeds those vehicles as individual agents **on the streets their counts came from**, and lets them route
   across the network under a per-class speed law.
4. Writes each vehicle's emission into a 300 x 300 pollution grid each cycle, diffuses the grid, and draws it.
5. Layers ambient air-quality stations and derived congestion incidents on top of that field.

Traffic is genuinely simulated, not replayed — every vehicle has its own position, destination and lifecycle.

## Requirements

- **GAMA 2025.6.4** or later. No plugins, no external services required for a basic run.

## Running it

1. Open GAMA.
2. Open `models/PenangAir.gaml`.
3. Run the **`MainExp`** experiment.

Six `write()` lines print to the console during `init`. They are the fastest way to confirm the data actually
attached — study area size, how many segments fell inside it, how many matched a surveyed street name, and
the resulting fleet. See section 10 of the guide for what each line should report.

Two experiments are defined:

| Experiment | View | Use |
|---|---|---|
| `MainExp` | 2D OpenGL, manual start | the interactive view: all panels, sliders and mouse interaction |
| `exp4Projector` | 3D, keystoned, autorun | a wide-angle presentation throw |

### Parameters

| Parameter | Default | Effect |
|---|---|---|
| Study area half-width | 1000 m | crops the network and the fleet. Saturates above ~1004 m — see below |
| Fleet scale | 1.0 | multiplies every surveyed flow before the fleet is computed |
| % electric, per class | 0 | converts a fraction of that class's population, live |

## Repository layout

```
PenangAir/
├── models/
│   ├── PenangAir.gaml        entry point: experiments, displays, interface, live-feed loader
│   ├── main.gaml             globals, init sequence, survey → fleet conversion, emission and diffusion
│   ├── global_vars.gaml      constants, thresholds, colours, labels, the pollution field
│   ├── loadmap.gaml          (not referenced by the current import graph)
│   └── agents/
│       ├── traffic.gaml      road, vehicle, incident and station species; their dynamics and aspects
│       ├── pollution.gaml    emission factor table
│       └── visualization.gaml the bars, clock and chart
├── includes/
│   ├── traffic_counts.csv    the survey: 2,540 rows, 678 distinct street names, four counted classes
│   ├── penang_roads.*        656 road segments (NAME, HIGHWAY)
│   └── penang_buildings.*    1,090 footprints, used as a backdrop only
├── images/                   vehicle textures and building textures
└── PenangAir_model_and_guide.docx        full model documentation
```

## Study area

The site is `{100.316083, 5.409611}` in WGS84 — 5°24'34.6"N 100°18'57.9"E, near Jalan Prangin — projected to
EPSG:3857 at `(11167135.3, 603091.8)`.

The road data is a 2008 x 2004 m extract centred on that point, so **the study-area parameter can only crop, not
grow**. Measured on the shipped data:

| Half-width | Segments kept | Fleet (car / motorcycle / bus / lorry) | Total |
|---|---|---|---|
| 300 m | 66 | 17 / 10 / 0 / 1 | 28 |
| 500 m | 176 | 86 / 50 / 4 / 7 | 147 |
| 750 m | 349 | 211 / 123 / 10 / 17 | 361 |
| **1000 m** (default) | 644 | **433 / 254 / 21 / 36** | **744** |
| 1500 m and above | 656 (all) | 445 / 261 / 22 / 37 | 765 |

Anything above ~1004 m is a no-op. At 300 m the network is too sparse to show traffic interacting.

## Documentation

- **[PenangAir_model_and_guide.docx](PenangAir_model_and_guide.docx)** — how the model is built and what it
  actually computes: the modelling framework, the survey-to-fleet derivation, agent dynamics, the emission
  and field model, the observation layer, verification status, and limitations. Written for readers already
  familiar with GAMA and agent-based modelling.

## Read this before quoting any number

Three caveats are stated up front in the guide and repeated here, because they are easy to miss:

- **The survey data is placeholder data.** Every value in `traffic_counts.csv` must be replaced with the real
  survey before this model is shown as a statement about Penang traffic.
- **The number on the chart is not an AQI.** It is the peak of an uncalibrated field multiplied by ten. There
  is no PM mass, no µg/m³, no mixing height and no calibration anywhere in the model. It also disagrees with
  the heat-map colour bands by a factor of ten.
- **Emission is per cycle, not per kilometre.** A stationary vehicle emits as much as a moving one, so
  congestion does not increase pollution in this model. Non-exhaust PM is not represented at all, which makes
  a fully electric fleet a lower bound rather than a zero.

The model also has not been execution-tested — see section 11 of the guide, which includes a one-line probe
for the one input-parsing risk worth checking on the first run.

## Licence / attribution

Emission factors are standard urban reference values. Vehicle textures and the underlying road and building
extracts are from OSM-derived data — check their licensing before redistributing.