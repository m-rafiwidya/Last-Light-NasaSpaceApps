# LAST LIGHT — science, data and simulation assumptions

**11 October 2026 · authoritative source facts are separate from original fiction.**

This brief explains what can be defended to judges and what is a declared game model. A near-future lunar workshop is a plausible fictional setting, not a NASA promise for 2058. IRIS, Kite, crew, mission logs, delivery services and displayed field observations are authored unless linked to a specific source measurement.

## What NASA data does in the game

| Input | Source and use | Limit |
|---|---|---|
| Lunar elevation | [LROC Apollo 12 DTM](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO12); measured terrain determines slopes, routes and line of sight | 2 m sampling cannot resolve every wheel-scale rock or grain |
| Matching image | [Apollo 12 orthophoto](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO12_M120005333_2M); aligned site reference/minimap | Contains acquisition illumination/shadows; not pure albedo |
| Lunar gravity | [NASA Moon by the Numbers](https://science.nasa.gov/moon/by-the-numbers/); 1.624 m/s² informs rover gravity/contact | Correct gravity alone does not validate the entire vehicle model |
| Thermal context | [LRO/Diviner instrument description](https://science.nasa.gov/mission/lro/spacecraft-and-instruments/); explain why sun/shade observations matter | An orbital observation is not an exact temperature forecast for a fictional 2058 sortie |
| Regional composition | [Lunar Prospector GRS collection](https://pds.nasa.gov/ds-view/pds/viewCollection.jsp?identifier=urn%3Anasa%3Apds%3Alp_grs_derived%3Adata&version=1.0), with [NASA catalogue description](https://data.nasa.gov/dataset/lunar-prospector-grs-elemental-abundance-v1-0) | Regional products have coarse bins; do not turn them into precise chemistry for one scoop |
| Environment | [NASA weather](https://science.nasa.gov/moon/weather-on-the-moon/) and [lunar atmosphere](https://science.nasa.gov/moon/lunar-atmosphere/) | No ordinary wind/rain or breathable outdoor air; trace exosphere studies need appropriate instruments |
| Optional sky | [NASA SVS Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/) | Use the actual downloaded file/credits; a sky panorama is not a validated date/site lighting solution |

The elevation and matching image are the required source assets for this chapter. Extra datasets are useful only when properly integrated. It is stronger to show how one real slope changed a rover decision than to list ten sources that do nothing.

The NASA GRS catalogue describes 2°, 5° and 20° products and currently does not itself provide a populated downloadable data resource. Use the PDS collection for any actual integration and inspect its labels/documentation. This pack does not contain a newly downloaded composition dataset or validated conversion.

## Terrain conversion and physical scale

1. Save original product identifiers and metadata with the raw input outside the shipped build.
2. Read elevation as numerical height, including units, scale/offset and no-data rules. A stretched grayscale preview is not usable physical elevation.
3. Choose a documented crop. Preserve projected pixel spacing, origin, orientation and height reference. Subtracting a constant height reference preserves relief; multiplying heights changes slopes.
4. Generate vertices/collision in metres. Align the image through the matching geospatial transform rather than eyeballing its UV orientation.
5. Compare known sample points and dimensions against metadata. Confirm north/east orientation, axis conversion and physical mesh/collision agreement.
6. Record any resampling and authored additions. Normal maps add shading, not physical terrain.

For a grid with `N` height samples and spacing `s_m`, the outer-vertex span is `(N - 1) * s_m`. The earlier 257 × 257 starter at 2 m therefore spans 512 × 512 m. Its previous vertical range was about 36.322 m after a reference subtraction; use that number only when the actual crop metadata matches.

The source site is near the equatorial Apollo 12 region. Use ordinary crater/boulder shade, not south-pole permanently shadowed ice conditions. Keep Sun direction stable for the short field shift. A fast day/night cycle would be an explicit artistic time model, not literal lunar timing.

Added rocks, loose-regolith zones and wheel-scale details are authored geometry/material assumptions. If they affect collision or traction, show them in the route forecast and credit them as additions. Do not claim they were measured by the 2 m DTM.

## Field science that is both playable and defensible

| Activity | Player action | Record and gameplay result |
|---|---|---|
| Inspection image | Aim at IRIS's labelled panel and capture | Position/time/target and diagnostic image; unlocks the correct repair work order |
| Regolith sample | Park stably, choose a clean target, run assisted scoop into container | Site, mass, context image, disturbance and container ID; enables a near/far comparison |
| Ground temperature | Aim the radiometer at a valid surface; record paired contexts | Surface temperature with unit, time/location and Sun/shade state; informs the cold-route plan |
| Logger recovery | Secure one physical logger as cargo | Added mass plus a stored past measurement record; receipt completes the archive |

A sampling interaction can also capture its context image and temperature when the appropriate sensors are fitted. Avoid making the player repeat three nearly identical aiming actions. A few seconds of meaningful animation/feedback are enough; do not add a real-time laboratory wait.

For the minimum chapter, the workshop's sample review is an **authored, simplified imaging/classification report** on grain appearance and context. Reuse the console and a sample tray. Do not claim an ordinary camera identifies exact elemental concentrations. If the team later adds a composition analyser, name and model the relevant instrument and its limitations; label its fictional outputs explicitly.

The point of the comparison is to document two sites against the older campaign, not prove the Moon has changed from one photograph. Multiple sites and illumination conditions introduce confounding factors. Describe what was observed rather than making an unsupported causal claim.

Physical samples remain sealed and stored at the outpost. Earth receives images, metadata and local reports. A radio link cannot transport the soil itself. A later physical sample-return mission would require its own cargo/launch plan.

### Temperature is not one universal number

A radiometer estimates a surface temperature from emitted radiation; a plausible full model also considers calibration/emissivity. For this game use a declared field-value approximation or properly processed source observations. Store Kelvin when appropriate and convert display using `C = K - 273.15`.

Ground temperature, rover skin temperature and internal battery temperature are different. A shaded ground reading does not instantly freeze a battery. Thermal response has inertia. If using a simplified body model, document its configured response time, heater effect and limits. If it is not ready, keep thermal gameplay to a forecast and explicit heater energy allocation.

A short surface scan is not lunar heat flow. Historical heat-flow work used subsurface probes: see [NASA's Apollo data-restoration account](https://astrobiology.nasa.gov/news/restoring-data-from-the-apollo-missions/). Do not call a radiometer reading a subsurface measurement.

### What about air?

The Moon has an extremely sparse exosphere. Helium, neon and argon are among the studied species; ordinary outdoor air-temperature/oxygen gameplay would be misleading. A future trace-gas mission can use an appropriate detector, blanks/calibration and a measurement site away from lander contamination. NASA notes that lander exhaust can dominate the nearby atmosphere. This is optional, not another mandatory instrument for M1–M3.

Cabin pressure/oxygen are real habitat concerns but add a different survival game. Keep them background context. On a later Mars chapter, its thin mainly carbon-dioxide atmosphere supports a distinct atmospheric-measurement task; see [NASA Mars facts](https://science.nasa.gov/mars/facts/).

## Engineering calculations and their boundaries

### Surface resources

`charge_Wh = clamp(charge_Wh + (generation_W - load_W) * dt_s / 3600, 0, capacity_Wh)`

Use one simulation clock. Include drive losses/idle electronics, camera, sensor, heater and transmitter loads. Shaft power is not the full electrical draw, especially at a stall. A tuned proxy is acceptable when identified as a game model. Solar generation is optional; if present, orientation and shadow must affect it.

`total_mass_kg = chassis + installed_parts + tools + current_cargo`

Mass remains mass on the Moon. Weight is mass times local gravity. A rough traction ceiling is proportional to contact normal force, so more motor torque cannot create unlimited grip. Wheel slip, rolling losses, clearance, centre of mass and actual controller behaviour all matter. Effective traction coefficients for regolith are gameplay assumptions unless calibrated against an appropriate model/source.

Show a measured-route reserve estimate/range, not an exact return guarantee. Account for loaded return and heater use. Grip may reduce energy wasted slipping; do not hard-code every better wheel as consuming more energy in every situation.

### Parts-delivery mission

The player selects a fictional service/manifest with capacity, credit cost, declared staging/orbit assumptions and a descent-reserve check. Essential completion equipment remains available for every allowed selection. Include packaging and structural/dry mass; service capacity and delta-v margin are separate constraints.

For one declared ideal stage:

`available_delta_v_mps = Isp_s * 9.80665 * ln(wet_mass_kg / dry_plus_payload_mass_kg)`

`margin_mps = available_delta_v_mps - required_delta_v_mps - reserve_mps`

Wet mass includes propellant, stage dry mass and payload. Use standard gravity for the seconds-of-specific-impulse convention, not lunar surface gravity. Reference: [NASA ideal rocket equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/).

This ideal estimate omits real flight dynamics and many losses. State how required delta-v/loss allowances and delivery-service values were authored or sourced. Earth ascent, transfer and orbital arrival can be prevalidated service phases; display the assumed arrival orbit and delivery window in details. Do not claim to simulate a complete real launch vehicle or orbit propagator.

The 15–25 second presentation compresses story days. Its outcome changes actual stock. Physical crew arrival is already complete; this is a parts-resupply mission. The competition build should visibly support objective selection, vehicle/payload configuration, delivery constraints, surface operation, communications and evaluation.

#### The M2 cargo order as built (`res/story/cargo.json`)

The console's Planning tab offers two fictional services. Every value below is a **game assumption** unless a source is given.

| Value | Used | Status |
|---|---|---|
| Courier lander: 30 kg delivered payload, arrives story day 4 | Mass check, M3 timing | Game assumption |
| Freighter lander: 40 kg delivered payload, arrives story day 11 | Mass check, M3 timing | Game assumption |
| Packaging and structure: 2 kg per order | Counted in the mass total | Game assumption |
| Item masses (module 12 kg, wheel 5 kg each, cover 0.9 kg, heater 0.6 kg, scoop 0.4 kg, containers 0.5 kg each, thermal turret 5.3 kg) | Read from the part scenes | Authored part data, the same values the rover physics uses |
| Descent from low lunar orbit: delta-v 1,900 m/s | Shown in the flight panel only; it doesn't constrain the order | Declared game assumption, of the order of published lunar descent budgets. No rocket-equation margin is computed in this build |
| Flight phases (launch, transfer, lunar arrival, delivery) and their days | Flight panel, 18 s, skippable | Game assumption; story days compressed and labelled |
| Lunar day: 708.7 hours, about 29.5 Earth days | Local time of M3 | [NASA Moon by the Numbers](https://science.nasa.gov/moon/by-the-numbers/) |
| Daylight: about 14.75 Earth days | Local time of M3 | Half the lunar day near the equator, derived from the figure above |
| Order on local day 1.4 | Start of the timeline | Derived: the Moon level's sun is 16.7 degrees up in the east (JPL Horizons, see the game README), and the Sun climbs about 12.2 degrees per Earth day (180 degrees over 14.77 days) |
| M3 starts 1 story day after the delivery; "near nightfall" means within 3 days of sunset | Late-arrival rule | Game assumption |
| Sun elevation shown on the cards and in the forecast | A uniform 180 degree arc over the daylight half | Game assumption (ignores the site's 3 degree latitude and libration). The level's lighting doesn't change |
| Cold zones (a 32 m radius on the short route, which is cold in daylight; a 24 m radius at the far rim, cold only near nightfall) | Positions of the shade | Authored. They are not derived from the DTM or Diviner |
| Cold shutdown after 20 s in an active cold zone without the cover and heater fitted, followed by the existing emergency recovery | M3 consequence | Game assumption, with time compressed. It is not a thermal model: it checks only whether the parts are fitted, and the heater's power draw belongs to the rover physics |

The Courier arrives early, so M3 falls on local day 6.4 with the Sun about 78 degrees up, and only the short route's shade is cold. The Freighter arrives late, so M3 falls on local day 13.4, about 1.4 days before sunset with the Sun about 17 degrees up. The far rim is in shade on either route, so the thermal kit is required to confirm a Freighter order, and no manifest leads to a dead end. The Courier can't carry the 20 kg of high-grip wheels. The Freighter can carry them, but not together with every other item.

### Communications

The local human-to-Kite link is distinct from the Earth downlink. Local teleoperation need not impose an Earth round-trip delay. Records move from collected to queued to received; UI/storage and energy follow that state. The IRIS link can transmit its archive when restored; samples/logger use the outpost reader and report pipeline.

Data sizes, link rates and UI time compression are declared parameters. A downlink progress bar is a model, not live NASA telemetry. If a later Mars chapter is built, Earth support is asynchronous: [NASA Mars Relay Network](https://science.nasa.gov/mars/mars-relay-network/) describes one-way delays of roughly 3–22.4 minutes. Direct rover control at the local base can remain responsive.

## Source registry and judge-facing disclosure

For every source-derived asset record:

- Source organisation, product ID, original URL, acquisition date when given, access date and exact source filename.
- Variable, units, valid range, no-data rules, projection/coordinate reference and uncertainty/resolution.
- Crop/window, sample spacing, orientation, height reference, resampling and conversion script/version.
- Derived game path, authored collision/material additions and creator/credit/licence.
- Gameplay use and a limitation the viewer can understand.

For authored field values/parts/services record model version, units, chosen parameters and rationale. Avoid NASA badges beside fictional precise chemistry or operational telemetry. A useful in-game source card reads:

> Terrain derived from LRO/LROC Apollo 12 elevation data, 2 m sampling. Surface detail and future equipment are authored. Field readings use a simplified game model.

For judges, demonstrate the route on the source map, explain scale preservation, drive two configurations, and show a received report with provenance. This establishes consequential data use without pretending the game is an engineering-certification tool.

## History and future fiction

IRIS and the remote logger are invented future equipment. Do not place collectible historic Apollo items without checking their status. For example, [Surveyor 3](https://science.nasa.gov/mission/surveyor-3/) had its camera and scoop retrieved by Apollo 12; they should not appear waiting to be salvaged in 2058.

Near-future station reuse is the narrative's technical idea. Motors, batteries and thermal kits are designed for the stated setting; spare stock is finite. NASA facts support the world, while the proposed expedition remains clearly fictional.
