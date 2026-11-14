> **Superseded by [game/docs/ASSET_BRIEF.md](game/docs/ASSET_BRIEF.md) (final Moon chapter story).**

# LAST LIGHT — asset brief and references

**Build target: one lunar workshop, one rover, one disabled rover and one station.** Start with the first-sortie objects. Asset work follows the mission's needed interactions.

This is a production brief, not a claim that the current imported assets meet these dimensions or budgets. Reuse working models before generating replacements. Coordinate with the owner of each scene.

## Visual direction

A small, used research workshop: pale metal panels, dark structural frames, visible fasteners, a few amber work lights and clearly labelled equipment. Outside, bright directional sunlight and dark crater shadows. Keep human scale and functional details. Use the existing rover's design language as the reference point.

The room can have the physical-console feel of the team's bunker-simulator inspiration. Give it a believable lunar service-bay layout rather than rows of decorative screens. Avoid copying another game's specific assets or interface.

## First milestone — generate/integrate these

| Priority / ID | Asset | Suggested dimensions | Required interaction | Reference |
|---|---|---|---|---|
| P0 / A01 | Modular workshop with operator area and rover service bay | Approximately 10 × 8 × 3 m; confirm rover turning space | Human can reach rack, pad and console; bay has a clear rover exit | R3 |
| P0 / A02 | Charging/service pad | Approximately 4 × 3 m; fit the current rover | Dock trigger and visible charger connection/status | R3, existing rover |
| P0 / A03 | Mission console | Desk approximately 1.2 × 0.65 × 0.9 m | One screen for Godot UI, visible interact prompt | R3 |
| P0 / A04 | Parts rack and labels | Wall rack approximately 2.5 × 0.5 × 1.8 m | Parts are separate selectable objects; readable labels | Existing parts |
| P0 / A05 | Disabled Kite rover | Reuse ROOK model, with a damaged/parked variant | Scan target and cartridge socket; never controllable | R4, existing rover |
| P0 / A06 | Diagnostic cartridge | Approximately 0.25 × 0.15 × 0.08 m | Separate mesh, pickup anchor, simple collision | Original design |
| P0 / A07 | Navigation/dock markers | Signs approximately 0.4 m wide | Base/route legibility; avoid collision clutter | Original design |
| P0 / A08 | Existing lunar terrain + collision | Use the declared source scale | Rover and loose-object contact | R1 |

These numbers are production targets. Measure the current rover before freezing the layout. A first-person character shouldn't have to squeeze between a tyre and the only usable console.

The service bay/airlock cycle can be visually abstracted. The operator stays in the pressurized area while the vehicle exits. Crew life support and pressure simulation are not gameplay requirements for this episode.

## Second sortie — only after first mission works

| Priority / ID | Asset | Suggested dimensions | Required interaction | Reference |
|---|---|---|---|---|
| P1 / A09 | IRIS research station | Equipment body roughly 2 × 1.5 × 1.3 m; mast roughly 3 m high | Service panel, antenna hinge, status indicator; repaired/idle states | R5 |
| P1 / A10 | Replacement radio-power module | Roughly 0.35 × 0.25 × 0.2 m | Cargo mount and matching service socket | Original design |
| P1 / A11 | Adapter fixture | Small bench tool/fixture | Fixed repair recipe with stock parts | R6 |
| P1 / A12 | Paper/service-note props | Small label/card surfaces | Short optional logs near their relevant equipment | Story script |

Station lights, the antenna's movement and module insertion carry the ending. They have higher value than a much larger base.

## Finish pass

- Ground detail material and a small set of rocks, keeping a record of their artistic origin.
- Workshop task lighting and a restrained exterior sky treatment.
- Interaction, docking, warning and restoration audio.
- Optional historical image cards with their exact source credits.
- Gloves/first-person hands only if existing interaction looks awkward without them.

Full astronaut bodies, animated NPCs, multiple bases, additional controllable vehicles and Mars models are deferred. A static seated operator silhouette is optional if a rover camera can see through a window; it does not require a rigged astronaut.

## Godot/Blender delivery contract

Each asset comes with an editable source and a game export, preferably `.blend` and `.glb`. If the current pipeline uses another format successfully, stay consistent.

- Author in metres with a scale reference cube. Apply intended object scale before export; imported static props should normally use unit scale.
- Name moving pieces separately: antenna, service door, cartridge and status-light mesh.
- Provide pivot locations for movement and explicitly mark pickup, cargo, charging and repair anchors.
- Do not bake UI text into a low-resolution console texture. Keep a clean screen surface and render the changing interface in Godot.
- Separate visible meshes from collision proxies. Use simple primitive/convex shapes for moving props and parts. Terrain collision must match the final gameplay mesh.
- Normal maps should follow the current material's convention. Their detail does not create physical height or collision.
- Keep source/credit notes with the asset. An AI-generated mesh still needs a provenance record and a scale/collision review.

Soft starting budgets: small props around 1–5k triangles, a station around 10–20k, and reusable base modules kept modest. These are targets for an ordinary laptop, not measured performance guarantees. Test exported performance rather than adding unnecessary subdivisions. Reuse materials and favour 1k/2k textures for small assets.

## Accurate lunar terrain scale

The previously supplied starter patch has 257 × 257 height samples with 2 m spacing. Outer vertices span 512 × 512 m. Its heights are already local metres after subtracting a constant reference. Its vertical range is approximately 36.322 m, not a normalized 0–1 intensity image.

For column c and row r, place the vertex at `(2*c, height[r,c], 2*r)`. Use the matching source crop for the surface image. Don't place the full patch on a 10 m plane or multiply its heights by an arbitrary artistic strength and still call the slopes measured.

Blender colour/image interpretation of a scientific TIFF is not a data-validation step. For displacement workflows, preserve float values and their offset/units. Bake/apply physical displacement to actual geometry before building collision. The float binary and metadata in the starter pack avoid relying on a TIFF's grayscale display.

Added small bumps can be shading detail. If they become collision geometry, they are authored terrain changes. Keep the original NASA-derived mesh/metadata and disclose that distinction. Check slope/collision against the intended routes. The source confidence information still matters; a visually valid crop is not automatically suitable for scientific slope certification.

The orthophoto already contains shadows from its original lighting. It is not pure albedo. Use it as a site image or align lighting reasonably for the prototype; generating normal detail does not remove those shadows or turn it into a calibrated PBR material.

## Sky and lighting

Use the NASA SVS celestial `starmap_2020_4k.exr` as a panorama reference if needed, starting with 4k rather than larger files. Godot's PanoramaSkyMaterial supports an equirectangular EXR. Use a directional light for sunlight and configure ambient/reflected light separately; a bright star panorama should not become the main illumination of the lunar ground.

The current bright Milky Way is an artistic presentation choice. For a camera exposing the sunlit surface, reduce star visibility. A star-exposure inspection mode can show it more strongly. Do not claim that the background is date/latitude-aligned astronomy unless you implement that orientation.

Keep the workshop readable. Avoid hiding the part silhouettes in darkness to make the scene feel like space. Strong directional shadows and quiet sound do more for the lunar setting than an over-bright sky.

## Reference list

**R1 — LRO/LROC Apollo 12 terrain**

https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO12

Use for measured terrain and matching imagery. Keep product IDs, crop/scale and processing notes. The earlier `Tandborste-NASA-Moon-Terrain-Starter.zip` contains the originals and prepared crop; no need to build a second competing terrain pipeline.

**R2 — NASA SVS Deep Star Maps 2020**

https://svs.gsfc.nasa.gov/4851/

Use a 4k celestial EXR for the sky. Follow the requested NASA/Goddard SVS and relevant star-catalog credits, including ESA/Gaia/DPAC. It is a sky visualization, not a replacement for a lunar light model.

**R3 — NASA habitat/human-factors references**

https://www.nasa.gov/centers-and-facilities/johnson/designing-space-exploration-with-the-human-in-mind/

Use the pictured mockups and workstation/stowage arrangements as spatial references. They are Earth-based test/analog facilities and concepts, not evidence of an operating lunar workshop. Build our fictional compact bay from reusable modules.

**R4 — NASA Curiosity 3D model reference**

https://science.nasa.gov/3d-resources/curiosity-rover-msl/

Useful for mechanical silhouette, mast and arm reference. Curiosity is a Mars vehicle; do not present a copied model as a tested lunar rover. Our existing model should remain the first choice.

**R5 — Apollo experiment-station history/reference**

https://www.nasa.gov/wp-content/uploads/static/history/alsj/HamishALSEP.html

Use equipment layout, cables, antenna and instrument-box references. IRIS is an original future design; don't model a historic ALSEP package as salvage stock or pretend it has a reusable current power source.

**R6 — Earth-sent manufacturing instructions**

https://www.nasa.gov/missions/station/solving-the-challenges-of-long-duration-space-flight-with-3d-printing/

Background for a design file being used away from Earth. It supports the information/manufacturing concept; our lunar adapter fixture and its capability are fictional.

**R7 — NASA history and heritage**

https://science.nasa.gov/mission/surveyor-3/

https://www.nasa.gov/wp-content/uploads/static/history/humanartifacts.html

Use for factual cards and preservation context. Our collectible cartridges/modules belong to a later fictional program.

**R8 — Optional detail materials**

https://polyhaven.com/textures

https://polyhaven.com/license

Poly Haven assets are CC0. Choose a specific rock/soil asset if needed and record its URL. It remains artistic detail, not a measured lunar-regolith material.

## Focused asset-generation prompt

Build only asset [ID] from this brief. Inspect the existing rover and Godot scale first. Deliver separate named meshes, metre dimensions, applied intended transforms, simple collision proxies, required anchors/pivots and editable source plus game export. Use the stated references for form and function. Keep screens blank for engine UI. List any borrowed assets and their source/licence. Validate import, interaction and collision in the designated scene before generating the next asset. Do not edit the vehicle controller as part of an art task.
