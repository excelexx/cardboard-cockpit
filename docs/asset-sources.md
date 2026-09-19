# Aircraft asset research

Checked September 18, 2026. No model files have been downloaded or imported at this checkpoint.

## Shortlist

The public Sketchfab model API reported `isDownloadable: true` and a CC BY 4.0 license for each model below. This establishes what the source currently declares, not independent proof of the uploader's ownership. Inspect the downloaded contents and provenance before importing.

| Aircraft | Source and author | Published geometry | Notes |
| --- | --- | --- | --- |
| Airbus A380 | [Airbus A380 — Brout](https://sketchfab.com/3d-models/airbus-a380-98d21f9c8104445f814cef47ef992889) | 67,580 triangles | One texture, no animations; author describes it as game ready |
| F-35 | [Low poly F-35 Lightning II — SIpriv](https://sketchfab.com/3d-models/low-poly-f-35-lightning-ii-561b5c56fbf94636a465f998e9af1224) | 7,689 triangles | Ten textures, three animations; animation content and visual detail uninspected |
| B-2 | [B-2 Spirit Bomber — Carlos.Maciel](https://sketchfab.com/3d-models/b-2-spirit-bomber-12244128967f4d93b9cac52b275c3d51) | 8,154 triangles | Five textures, no animations; real-time exterior candidate |
| Boeing 737 | [Boeing 737 — Adrenalin2122](https://sketchfab.com/3d-models/boeing-737-3c10f1943fa240e39606266ddabf5576) | 16,026 triangles | No textures or animations listed; likely needs additional material work |
| Boeing 747 | [Boeing 747 KLM — hilos run](https://sketchfab.com/3d-models/boeing-747-b747-klm-6d47915471d44dfeb9d822405709c563) | 38,441 triangles | No textures or animations listed; inspect material/livery and provenance |

License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).

The metadata endpoints use `https://api.sketchfab.com/v3/models/<model-id>`, where the ID is the final identifier in each model URL. The A380 download endpoint returned HTTP 401 without authentication. Normal downloads may therefore require a signed-in Sketchfab session. Do not assume unattended download access is available. Source archive formats remain unverified until files are obtained; prefer GLB/glTF where offered.

## Directly accessible 747 prototype option

The [God's Eye View model attribution record](https://github.com/bilawalsidhu/gods-eye-view/blob/main/public/models/README.md) identifies `airplane.glb` as a Boeing 747 by `zairiq-123`, under CC BY 4.0, modified and optimized by that project.

The [direct GLB URL](https://raw.githubusercontent.com/bilawalsidhu/gods-eye-view/main/public/models/airplane.glb) returned HTTP 200 with a reported size of 88,144 bytes on a HEAD request. It was not downloaded. The project documents meter scale, Y-up, and nose toward negative X. This heavily simplified model may be useful for testing; it is not a confirmed detailed hangar asset. Original creator ownership has not been independently established.

## Alternative source repositories

FlightGear aircraft repositories can provide model geometry and source materials without a Sketchfab session, but need conversion and a per-file license review:

- [A380](https://github.com/FGMEMBERS/A380): repository lists GPL-2.0.
- [F-35B](https://github.com/FGMEMBERS/F-35B): repository lists GPL-3.0.
- [737-300](https://github.com/FGMEMBERS/737-300): repository lists GPL-3.0.
- [747](https://github.com/FGMEMBERS/747): repository lists GPL-2.0.
- [B-2](https://github.com/FGMEMBERS/B-2): repository exists; license not established in this pass.

These are alternatives requiring evaluation, not approved imports. Preserve applicable source, notices and distribution terms for any files ultimately used.

## Next phase checks

1. Obtain and inspect an aircraft model, confirming access, license files, textures, scale and geometry before committing to its pipeline.
2. Verify provenance and preserve attribution; exclude game-ripped assets despite any conflicting uploader license label.
3. Import into Godot and inspect materials, orientation, pivots, animation, size and performance.
4. Distinguish usable exterior geometry from cockpit interior detail. Do not claim an exterior model includes a functioning cockpit.
5. Capture actual in-engine screenshots and record substitutions or unavailable downloads explicitly.
6. Populate the root third-party asset manifest only after the actual files are imported.
