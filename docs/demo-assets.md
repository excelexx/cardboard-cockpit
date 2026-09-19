# SPECTRE asset credits

- **SPECTRE airframe:** FlightGear F-35B, GPL-3.0. The base mesh and source textures are included with license and pinned SHA-256 manifest. This project adds swept fore-chines, widened proportions, game-tuned materials, animation and the SPECTRE graphite/amber livery. The generated livery adapts the original UV texture and retains its GPL licensing obligations. [Aircraft notices](../THIRD_PARTY_ASSETS.md).
- **Title artwork:** generated for this release, `assets/art/spectre-title.png`. Cinematic fictional fighter flying through an alpine valley; no third-party logo. The built-in image generator does not expose a selectable model version.
- **Canada goose:** “Goose” by Poly by Google, [Poly Pizza](https://poly.pizza/m/9wn3If7Qgb4), CC BY 3.0. Original model is included; scaled/reoriented with animated wing attachments. License: https://creativecommons.org/licenses/by/3.0/.
- **Music:** “Space Adventure” by MintoDog, [OpenGameArt](https://opengameart.org/content/space-adventure), CC0; original OGG.
- **Goose calls:** Canada Geese, recorded by Lawrence Shove in 1966; copyright The British Library Board; [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Canada_Geese_(Branta_canadensis)_(W1CDR0001421_BD11).ogg), CC BY-SA 4.0. Original unmodified OGG included. https://creativecommons.org/licenses/by-sa/4.0/.

- **Missile:** Jarlan Perez, [Poly Pizza](https://poly.pizza/m/1Xid2Qhqn2s), CC BY 3.0. Scaled and oriented for underwing stores and guided flight.
- **Smoke and impact sprites:** [Kenney Particle Pack](https://kenney.nl/assets/particle-pack), CC0.
- **Electronics, weapon effects and ambience:** [Kenney Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds), CC0.
- **Engine, wind, cannon, afterburner and sonic recordings:** FlightGear F-35B (GPL-3.0) and AN-225 (GPL-2.0). Original files and notices are included. The afterburner and sonic samples use F-35B revision `2726b3bdf3c7c54ea09a5d4a248e86a739604ca7`; processing and hashes are recorded in `assets/audio/spectre-sources.json`.
- **Gear, flap, wheel and touchdown recordings:** pinned FlightGear AN-225 library, GPL-2.0; source retained for attribution and redistribution.
- **Radio:** [Kenney Voiceover Pack](https://kenney.nl/assets/voiceover-pack), CC0. Male voice Jeffrey M. Smith; female voice Giselle. Fifteen event cues are assembled from licensed clips using narrow-band EQ, compression, static and squelch. Original clips, license, processed files and SHA-256 manifest are in `assets/audio/radio`. `tools/build_radio_assets.py` reproduces processing with ffmpeg and NumPy. These are licensed recordings, not ElevenLabs generations.
- **Terrain and sky:** Poly Haven, CC0; see [environment notice](../simulator/assets/environment/README.md).
- **Engine:** Godot, MIT; license bundled.

Earlier aircraft, ships and unused weapon assets remain in source history/provenance folders, with their notices. They are excluded from the SPECTRE executable. The current loadout contains only cannon rounds and guided missiles.
