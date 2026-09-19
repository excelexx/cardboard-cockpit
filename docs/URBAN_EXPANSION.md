# Greater Azure: neighborhood and lighting overhaul

The city-first route combines the existing approximately 8 km² photographic
downtown with approximately 147.4 km² of generated urban blocks. This is
procedural scenery, not additional photogrammetry or a reproduction of a real city.

## What changed

The previous 200 m painted grid and four isolated buildings per tile are gone.
A deterministic street network now has variable block widths, bending avenues,
different orientations, and geometry-fitted streets. Protected airport approaches,
the photographic district, harbor, and elevated rail alignment remain clear.

Residential blocks combine joined frontage, open courtyards, service wings,
pitched-roof terraces, and apartment slabs. Commercial blocks use offset retail
podiums and individual towers. Industrial districts use large warehouses and
loading trailers. Noise-based districts and park clusters avoid repeating the
same land use every few blocks. Legacy countryside plots no longer leave holes
inside the city.

Current deterministic layout: 2,213 residential blocks, 190 office blocks,
405 industrial blocks, and 554 park blocks. There are 46,154 building sections
(not that many unique models), including 105 main bodies taller than 150 m.
Geometry is shared across 952 nodes. A fixed budget of 650 moving cars is sampled
across the whole map, including both airport neighborhoods. The elevated train
has a protected greenway rather than cutting through the new curved blocks.

## Materials and lighting

Facades use local metre coordinates, so windows follow rotated buildings instead
of a world-axis projection. Smaller residential windows, reduced emissive noise,
muted brick/stone colors, world-scaled roof and pavement textures, and varied
roof forms replace the bright uniform toy-block appearance.

The central runway exclusion now ends at actual approaches instead of cutting
a 520 m grass strip through the whole city. Departure neighborhoods also use a
bounded budget of imported Poly Haven apartment facade modules, with real
window geometry. Window spacing varies per procedural building. Airfield turf
has broad moisture variation and subtle mowing lanes visible from altitude.
The latest pass adds scanned brick/plaster normal detail and up to 160 scanned
3D trees along the low-altitude departure edge. The remaining distant trees
are still billboards; this is not a wholesale photogrammetry replacement.

The panoramic cockpit display now prioritizes large speed, altitude, heading
and thrust readouts. Cockpit and paper-test overlays omit the oversized ammo
panels while retaining navigation, selected target and urgent warnings.

Golden-hour lighting has closer shadow cascade splits, reduced normal bias,
blended cascade transitions, stronger contact shading, and subtle screen-space
indirect light in High mode. Balanced mode disables indirect light. No additional
online services or paid assets are needed.

## Preserved cockpit work

The throttle and stick sit aft of the instrument panel on separate consoles.
Full-travel clearance tests cover the throttle. Large controls and panels have
chamfered edges, with grip ribs, switches, fasteners and restrained console lights.

## Validation

Run `tools/verify.sh`. Tests cover flight, weapons, airport/scan grounding,
controller integration, urban batching, variable block widths/orientations,
mixed land uses, traffic distribution, and cockpit control clearance.

Native visual/performance check:
Godot `--path simulator --script tests/test_urban_expansion.gd -- --visual`.
Before the latest facade additions, five Apple M4 views measured median frame intervals around 16.6–16.7 ms
and p95 around 17.1–18.1 ms after warmup; one sampled frame took 34.6 ms.
These are sampled local results, not a guarantee of sustained FPS elsewhere.
The accelerated moving-flight test also landed safely after 179.18 simulated
seconds: rendered intervals p50 16.74 ms, p95 19.80 ms, p99 20.88 ms, max 40.47 ms.

The scenery still uses shared procedural assets, simple distant geometry,
billboard vegetation and a flat metropolitan terrain base. It is not
MSFS-level photorealism.
