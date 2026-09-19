> Integrated in SPECTRE 0.9 with the current fighter and combat rules. The integrated route completes in 179.15 simulated seconds, visits all eleven landmarks, and spends 40.18 seconds above the city. This original branch report is retained for provenance.

# Coastal countryside and city flyover

The guided route now crosses the photographic city's actual footprint, rather
than following the offshore channel. The route regression requires at least ten
seconds over the city, all eleven landmarks, no terrain-rescue corrections and
a safe runway stop. It retains takeoff, interception and landing.

Verified route: 41.35 simulated seconds above the city, eleven landmarks, safe
stop after 198.08 simulated seconds, and zero terrain-rescue corrections.

Five settlements add sixty Kominka homes, timber verandas, tiled roofs, gardens,
village lanes, crop rows and stone foundations. The imported MIT asset kit uses
33 shared, downsampled textures, and homes are instanced by material. Distant
settlements stop rendering at 4.5 km. No publisher scripts execute at runtime.
Hidden interiors are omitted; gltfpack applies bounded simplification where
possible. The runtime kit occupies approximately 4.8 MB, excluding import cache.

Performance capture during this pass was contended by a separate user-launched
simulator instance. It is not a valid isolated frame-rate benchmark; previous
frame-time numbers must not be presented as measurements of this revision.

Forest clearings respect settlements. Tree scale is reduced, woodland ground
color is more coherent, and the coast uses stronger distance haze, warmer golden
light and restrained bloom. These are art-direction changes, not a claim that
all parts of the simulator now have uniform photographic fidelity.

Run `tools/Review City.command` for countryside and city screenshots, or
`tools/Review Scenic Route.command` for the complete guided journey.
