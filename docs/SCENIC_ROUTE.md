# Azure Coast route

The active world is `scenes/coastal_world.gd`, with waterfront architecture in `scenes/coastal_city.gd`. The original world remains a base for airport, atmosphere and terrain-mesh utilities; its valley build is not called. `metropolitan_world.gd` supplies instancing and architectural helpers; its old grid-city build is not called.

Eleven world-space waypoints drive navigation and six loadouts: Azure Bay, marina, skyline, downtown, harbor, bridge, island channel, panorama, lighthouse, descent and Cape North approach. Arrival requires horizontal distance below 290 m and vertical error below 190 m. There are no route teleports. Copilot and HUD use the same target.

The main city now uses two 2×2 km Helsinki photogrammetry districts: 128 coarse tiles and 256 higher-detail refinements for the southern district. Shared-distance switching with hysteresis keeps each four-tile refinement together. Baked photographic streets, roofs, trees and architecture replace the generated grid. Tile bounds provide conservative collision coverage (not street-level navigation). Airport and bridge bounds remain explicit. No network or map API is needed during flight. Credits and rebuilding instructions are in `simulator/assets/photogrammetry/CREDITS.md`.

## Verification

The coastal route regression completed all 11 waypoints in 185.27 simulated seconds, peaked at 1,041.19 m, and ended in a safe full-stop landing with zero terrain safety corrections. Campaign regression: 49 checks passed. These are assisted software checks, not proof of physical cardboard tracking or certified flight behavior.

Run the bundled Godot executable with `--headless --path simulator --script tests/test_scenic_route.gd`. Additional suites: `test_campaign.gd`, `test_city.gd`, `test_camera.gd`, `test_landing.gd`.

Double-click `tools/Review Scenic Route.command` for cockpit checkpoint captures or `tools/Review City.command` for overview captures. Both exit when complete and do not open the webcam. Existing packaged apps must be rebuilt to include source changes. Rehearse physical controls before the event.
