# LAST LIGHT — final asset brief

**11 October 2026 · one workshop, Kite, IRIS, and one far reference site.**

Reuse the current rover, part models, arm, cameras, UI and terrain before generating replacements. This is a production specification, not a claim that the imports already meet it. Keep asset work tied to a mission interaction.

## Visual direction and layout

A small working lunar outpost: pale equipment panels, dark structural members, labelled stowage, practical lighting and a few signs of use. Outside, use strong directional sunlight, readable rover silhouettes, crater shadows and restrained material detail. Match the existing project's visual language.

Home base and IRIS must look different. The base is a habitable workshop. IRIS is an uncrewed instrument box, service panel and antenna. The far site is a marker, logger and reference soil area. No second large building is required.

Give the operator a compact triangle of rack, rover pad and console. The human works in a pressurized area; the rover exits through an abstracted service-airlock cycle. A blank interface screen should use Godot UI, not baked text. Crew quarters, a full lander interior and visible walking astronauts are outside the current build.

## P0 — complete inspection sortie first

| ID | Asset / quantity | Function and minimum deliverable |
|---|---|---|
| A01 | Workshop kit / one room | Floor, walls, operator area and service bay; usable route between rack, pad and console |
| A02 | Dock/charging pad / one | Fits the current rover; trigger, charging indicator and clear parking boundary |
| A03 | Mission console / one | Readable display surface, interact anchor, Mission/Kite/Downlink interface |
| A04 | Parts rack / one | Stores separate selectable batteries/wheels/motors; labels visible at interaction distance |
| A05 | Kite / existing rover | Stored/unready and operational states of the same vehicle; no separate lost-rover prop |
| A06 | Part variants / reuse current set | Two battery choices and two wheel-set choices, with existing motor; correct sockets and collision |
| A07 | IRIS / one | Equipment body, service panel, module socket, antenna pivot and off/on indicator states |
| A08 | Navigation markers / small reusable set | Home/dock, IRIS and route legibility; avoid obstacles made of signs |
| A09 | Terrain and collision / existing patch | Source scale preserved; ground supports actual rover contacts |

Production starting sizes: workshop about 10 × 8 × 3 m, pad about 4 × 3 m, console about 1.2 × 0.65 × 0.9 m, IRIS body about 2 × 1.5 × 1.3 m with a roughly 3 m mast. These are fictional design targets. Measure the actual rover and leave turning/access space before freezing them.

## P1 — restoration and science objects

| ID | Asset / quantity | Function and minimum deliverable |
|---|---|---|
| A10 | Replacement radio-power module / one | Separate cargo mesh, pickup/mount anchor and matching IRIS insertion pose |
| A11 | Module cradle/adapter / one | Shows how stock parts fit the station; fixed compatible assembly rather than a crafting tree |
| A12 | Sampling kit / one reusable kit | Gripper-compatible scoop/tool, sealed container mesh, small lab inspection tray and assisted collection poses |
| A13 | Sample containers / two functional instances | Near/far IDs; empty/full state; cargo/storage anchors; optional extra instance for contracts |
| A14 | Surface-temperature sensor / one | Small radiometer housing on the rover or kit; scan point and UI reading |
| A15 | Reference sample targets / two | Near IRIS and far rim; readable surface/context; a nearby clean fallback target |
| A16 | Field logger / one | Single pickup, visible cargo attachment, two service labels, stored-record interaction |
| A17 | Thermal kit / one | Reusable insulating cover and small heater component; readable installed state |
| A18 | Logs/labels / three short entries | Kite storage note, IRIS field note and logger note; text remains readable in engine |

The gripper can handle the module and hold a scoop tool during an assisted action. Do not require a new robotic-arm controller or physically simulated loose soil. A brief scoop/fill/close sequence is enough. A temperature sensor can reuse the camera housing style.

IRIS's light and antenna movement are priority feedback. Logger cargo and full sample containers must be visible so the player understands the changed load.

## P2 — finish pass after all missions work

- A few reusable rocks and readable rough-ground patches. Physical added obstacles are recorded as authored geometry.
- Optional higher-torque motor and higher-quality camera using existing part schemas.
- Charge/module/scoop/log-transfer feedback, warning tones and restrained ambience.
- 28 radio lines plus one optional archive performance; 16 System entries remain text/UI feedback. Recount if the script changes.
- Optional first-person gloves if the current interaction needs them.
- Optional historical/source cards, using genuine images with exact credits.
- Optional IRIS charging point, only when route/energy design needs it.

Do not spend P0/P1 time on full astronaut bodies, walking NPCs, another rover, large base corridors, weapons, a winch or freeform mining.

## Export and collision contract

Deliver editable source plus game export, preferably `.blend` and `.glb`, following the current successful pipeline. Author in metres, include a scale reference and apply intended transforms. Imported static pieces should normally use unit scale.

Name moving pieces and pivots: antenna, service door, module, scoop, container lid and status indicator. Supply interaction, cargo, socket and charging anchors. Use simple primitive/convex collision proxies for moving parts; terrain collision matches its physical gameplay geometry. Read/document the project's real collision layer names. Do not guess layer indices or edit the controller during an art ticket.

Soft starting budgets for an ordinary laptop: small props roughly 1–5k triangles; station roughly 10–20k; modest reusable workshop modules; small assets normally 1k/2k textures. These are art budgets, not measured performance guarantees. Test the export and reuse materials. The source-derived terrain has its own mesh budget.

Never bake essential objective text into a texture. Use engine text for labels needing translation or status changes. Screens, markers and sockets should remain usable under both bright exterior exposure and workshop lighting.

## NASA terrain and imagery

Use the single existing LROC pipeline, with these source products:

- [Elevation: NAC_DTM_APOLLO12](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO12)
- [Matching orthophoto: NAC_DTM_APOLLO12_M120005333_2M](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO12_M120005333_2M)

Both products declare 2 m spacing. If using the previously supplied starter, 257 × 257 height samples span 512 × 512 m between outer vertices. Its earlier metadata records approximately 36.322 m vertical range after subtracting a constant reference. Confirm the actual crop before applying those numbers to the current import.

Keep float height values and metadata. Scientific TIFF display brightness is not elevation. Preserve the height reference, crop origin, CRS/orientation, no-data handling and image alignment. Normal maps affect shading, not collision. Added wheel-scale bumps are art unless explicitly built into the authored collision mesh.

The orthophoto includes its acquisition lighting/shadows; it is not pure albedo. Use it for a site image/minimap or an aligned prototype surface. A separate artistic regolith material can improve ground shading while source geometry remains preserved. Label that material as authored detail.

Do not silently exaggerate vertical scale to make a route more exciting. Pick real slopes, add declared obstacles, and test them with the rover. The map is near the equatorial Apollo 12 region; do not present it as a south-pole ice crater.

## Sky, light and sound

[NASA SVS Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/) is the existing sky reference. Reuse the team's downloaded panorama when available. A fresh fetch timed out in this review; this pack does not claim a newly downloaded sky asset. Preserve the credit information bundled with the actual file, including relevant catalogue credits.

Use sunlight from a directional light and control ambient/reflected light separately. An excessively bright star panorama should not light the ground. Reduce visible stars when exposing the sunlit surface; stronger star visibility can be a declared artistic camera mode. Date/site-aligned astronomy is an optional additional implementation.

Do not add terrestrial wind or rain to the Moon. Workshop sounds are local air/structure sounds. Rover sounds can be onboard contact/vibration pickup or UI sonification. See [voice/audio](VOICE_AND_AUDIO.md).

## Other reference sources

- [NASA human-centred exploration design](https://www.nasa.gov/centers-and-facilities/johnson/designing-space-exploration-with-the-human-in-mind/): workstation/stowage reference. Concepts and terrestrial test facilities, not an existing lunar workshop.
- [NASA 3D resources](https://science.nasa.gov/3d-resources/): reference library; inspect each chosen asset and credit individually.
- [Curiosity rover model](https://science.nasa.gov/3d-resources/curiosity-rover-msl/): mast/arm/silhouette reference. It is a Mars rover; keep Kite an original lunar design and reuse the team's model.
- [Apollo experiment layout](https://www.nasa.gov/wp-content/uploads/static/history/alsj/HamishALSEP.html): box/cable/antenna reference. IRIS is fictional future equipment, not an ALSEP salvage target.
- [Surveyor 3 history](https://science.nasa.gov/mission/surveyor-3/): factual discovery card if used. Its camera and scoop were retrieved by Apollo 12; do not leave those parts in a future collectible scene.

Custom or AI-assisted workshop models are appropriate for a fictional setting. Their origin is recorded separately from NASA measurements. A terrain dataset is valuable because it changes routes and constraints, not because every prop must be a NASA asset.

## Provenance and focused generation request

For each item store ID, creator/origin, source URL where relevant, licence/credit, editable source, export path, scale, collision and interaction checks. Keep authored, generated and NASA-derived categories clear. An AI-generated mesh still needs human scale/collision review.

Prompt template:

> Make only asset [ID]. Read the existing rover scale and this brief. Reuse the project style. Deliver separate named meshes, metre dimensions, intended applied transforms, simple collision, required anchors/pivots and editable source plus export. Keep dynamic screens blank. List borrowed inputs/credits. Validate the import and this asset's interaction in the current scene. Do not change the vehicle controller or generate the next asset yet.
