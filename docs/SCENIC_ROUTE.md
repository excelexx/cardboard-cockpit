# Azure Coast in SPECTRE 0.9

Integrated from Festyve’s `graphics/coastal-overhaul`, revision `8be8a51`. The active coastal world is `scenes/coastal_world.gd`, with its preserved terrain/airport helpers isolated in `coastal_base_world.gd`. The original alpine world remains independently selectable from the flight deck.

Eleven authored waypoints lead through Azure Bay, the marina, skyline, downtown, harbor, bridge, island channel, panorama, lighthouse, descent and Cape North approach. Blue navigation diamonds and the same waypoint list drive guidance and HUD. Arrival requires horizontal distance below 290 m and vertical error below 190 m. The tour uses the current SPECTRE and its permanent Gatling/missile loadout, with staggered harmless geese; it introduces no aircraft or weapon upgrades.

The city contains two Helsinki photogrammetry districts: 128 coarse tiles plus 256 close refinements. Detail switches in complete four-tile groups with hysteresis. Sixty modular Kominka homes form five countryside settlements. Conservative collision bounds cover buildings; airport and bridge collision remains explicit. All assets are available offline. Credits accompany the datasets.

Integrated route verification: all eleven landmarks, 40.18 simulated seconds above the city, a 1,047 m peak, continuous motion and a safe full-stop landing after 179.15 simulated seconds. The original alpine route also remains under full-sortie regression coverage.

Run `tools/Review Scenic Route.command` for checkpoint captures, `tools/Review City.command` for scenery views, or `tools/verify.sh` for software verification. Physical cardboard testing remains separate.
