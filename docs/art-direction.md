# Arcade art direction and asset production

Version 0.8 keeps one coherent SPECTRE airframe and two permanent weapons. Readability and responsive play take priority over realistic ammunition limits or demanding weapon locks.

The original title artwork is the visual reference: cool mountain shadows, dark conifers, warm low sunlight, reflective water, snow ridges and layered atmospheric depth. The live scene uses those colors and motifs with real geometry, shading, collision and frame-rate constraints.

## Generated assets

All images below were made with the built-in image-generation tool and copied into the game. No selectable model version or paid external API was used.

| File under simulator/assets | Purpose / prompt direction |
| --- | --- |
| fighter/spectre-satin.png | Edit the original F-35 UV atlas without moving islands; clean factory graphite, fine restrained seams, amber tail accent, X26 stencil, no real-world brands or flags. The source atlas's GPL obligations remain applicable. |
| environment/alpine-sunset.png | Seamless 2:1 equirectangular golden-hour cloud panorama, pure sky, cool slate clouds and a restrained warm sun region. |
| environment/alpine-cloud-front.png | Detailed front-facing sky; 80% cool storm clouds, warm lower band, no sun disk, photographic exposure rather than an orange wash. |
| environment/alpine-fir.png | Full mature narrow alpine fir, fine needles and irregular branches, neutral lighting, transparent cutout. |
| environment/alpine-fir-b.png | Broader asymmetrical Canadian pine/fir, distinct crown and branch gaps, transparent cutout, lighter new growth. |
| environment/alpine-granite.png | Seamless cool charcoal granite, angular fractures, mineral variation, neutral base-color lighting. |
| vfx/gatling-flash.png | Transparent directional flash with white-yellow ignition and amber turbulent gas; used on two short muzzle-aligned planes. |
| vfx/detonation.png | Transparent airborne fireball with warm fire, turbulent charcoal smoke and small sparks; no starburst, ground or interface. |

Tree textures are used on crossed geometry with varied scale, rotation, color and wind. They are not full photogrammetry tree meshes. The terrain's cached heightfield is shared by scenery placement and collision. Shoreline rocks have wet/dry material variation; water uses irregular ripples, nonmetallic reflections and a shallow-water color gradient.

## Blender work



The airframe preserves the licensed FlightGear model and animations. This release removes the old floating plates and nose probe, corrects exhaust/gun/pylon positions, applies the new livery and uses restrained material highlights plus a small aircraft-only fill light for readability.

Tracers are deliberately enlarged, and geese are closer and larger for forgiving arcade play.

`tools/build_cg26_blender.py` creates the original CG-26 shoulder-mounted rotary cannon, with six hollow barrels, rotating braces, receiver, ventilation slots, feed housing and amber service band. `docs/source/CG26.blend` retains editable source; the exported hierarchy preserves the gimbal, rotor and muzzle attachment. The gun follows the displayed aim and spins down after release.

Runtime-loaded 3D textures explicitly include mipmaps. Foliage uses alpha-to-coverage with 4× MSAA in both quality modes; stable instance color data avoids the earlier temporal speckling.

The CG-26 has a small receiver recoil and a short source-derived mechanical attack at the start of each trigger press.
