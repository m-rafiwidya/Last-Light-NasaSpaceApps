# LAST LIGHT — complete Moon chapter script

**Original fiction · 11 October 2026 · canonical player rover: Kite.**

English is the proposed in-game language. These lines are editable performances, not NASA transcripts. Story equipment, telemetry and characters are fictional. NASA history/source cards remain separate. This script replaces the older lost-Kite/two-rover opening.

## Situation, cast and ending

In 2058, a small Surface Research Programme crew begins a rotation at an existing lunar field outpost. The player is its astronaut/robotics engineer. The outpost has been prepared before their arrival; crew transport uses a spacecraft and lunar lander. The player repairs Kite, a stored rover, with the available field kit.

IRIS, a nearby uncrewed research unit, lost its radio-power module during the earlier campaign. Replacement stock did not arrive before that crew's departure. Its surviving stored records belong to real people doing ordinary work, including field technician Evan. No one is missing. An independent remote logger contains the last undelivered comparison record.

Mira supports systems work from Earth. Hana leads the science work from Earth and knows the earlier campaign. Evan is heard only in recorded notes. The other current expedition members are off-screen context; the player is the only playable person. No walking NPC or AI conversation is required.

Three outings restore IRIS and recover the logger. End only when the station is active, the required records are received, and Kite is docked. The final view is the rover home in its bay and a live IRIS indicator on the console.

## Dialogue implementation

Use the existing dialogue resource/queue after inspecting its schema. The LL IDs below identify content, not a new code framework. Critical instructions also appear as UI objectives. The player does not need to listen to an optional log to know what to do.

Play one voice at a time. Allow skip/mute/review. Mark one-time triggers after presentation; repeated warnings use a cooldown and the current state. No line blocks vehicle controls. Normal player acknowledgements can be buttons rather than additional voice work.

### Prologue — arrival and incoming kit

Place: workshop console. A short arrival card establishes the year, crew and existing outpost. The player can skip it. Show Kite waiting on the pad and the IRIS sector on a map. Do not introduce a second rover.

| ID | Speaker | Trigger | Line / text |
|---|---|---|---|
| LL-001 | System | New chapter | “2058. Lunar field rotation. Your crew has arrived; the rover workshop is ready.” |
| LL-002 | Mira | Workshop introduction | “Welcome to the workshop. Kite's frame is sound. Start with the battery.” |
| LL-003 | Hana | Assignment | “IRIS still has records we never received. We need a look at its service panel.” |
| LL-004 | Mira | Cargo manifest opens | “The outpost has the basics. Choose any extra kit within the delivery limit.” |
| LL-005 | System | Invalid delivery | “Delivery not ready. Check the highlighted mass, budget or descent-reserve limit.” |
| LL-006 | Mira | Valid manifest confirmed | “Manifest approved. We'll add that crate to the field stock.” |

Show the short parts-flight sequence, labelled with the story-time advance. Hardware appears only when delivery completes. The animation is skippable; validation and inventory changes are not. Crew arrival is already complete and separate from this parts delivery.

### M1 — Wake Kite

Required objective: fit the essentials, photograph IRIS's service panel, return, and downlink. The initial safe approach is visible. Introduce no thermal-failure or random hazard event in this tutorial.

| ID | Speaker | Trigger | Line / text |
|---|---|---|---|
| LL-010 | Mira | Assembly objective | “Fit the battery, check the wheels, then take control from the console.” |
| LL-011 | System | Missing essential part | “Kite isn't ready. Fit the highlighted part.” |
| LL-012 | Mira | First extended-battery selection | “More reserve, more mass. Check what else you're carrying.” |
| LL-013 | Mira | First rover control | “Kite control is yours. Follow the marked gentle approach.” |
| LL-014 | Hana | IRIS becomes visible | “That's IRIS. The service panel is below the antenna.” |
| LL-015 | System | Valid panel image | “Diagnostic image recorded. Return to the outpost.” |
| LL-016 | Hana | Service label revealed | “Evan's handwriting. He always labelled the connectors twice.” |
| LL-017 | Mira | First return-reserve warning | “You're using the return reserve. Head home before taking more observations.” |
| LL-018 | System | First successful dock | “Kite docked. Inspection report ready to send.” |
| LL-019 | Mira | M1 report received | “The radio-power module has failed. The storage record is still readable.” |
| LL-020 | Hana | M1 diagnosis | “Good. We can restore the link without replacing the whole station.” |

Workshop note, optional text-only prop:

> KITE — STORAGE CHECK
> Battery isolated. Frame and gripper inspected. Test the next wheel set under load before taking the crater-side approach.
> — Evan

After the report, show the M1 result with the image received and rover recovered. Make the next action clear: prepare the replacement module. A compatibility work order may reveal stock/adapter instructions; physical hardware comes from the inventory.

### M2 — First Signal

Required objective: carry the correct module, restore IRIS, receive its initial archive, return. The station is the same location, now approached with a different payload. Offer a short loaded climb and a longer gentle route. A near-site sample is optional preparation for M3.

| ID | Speaker | Trigger | Line / text |
|---|---|---|---|
| LL-030 | Mira | Replacement work order | “Load the replacement module. It changes the weight of this trip.” |
| LL-031 | Mira | Route forecast | “The short approach climbs harder. The longer track gives the loaded rover more room.” |
| LL-032 | Hana | Sampling kit available | “If you fit the sampler, collect the marked reference soil beside IRIS.” |
| LL-033 | System | Invalid repair attempt | “Repair requires the correct module onboard and Kite stable beside the panel.” |
| LL-034 | Mira | Module installed | “Module seated. Start the station check.” |
| LL-035 | System | IRIS restored | “IRIS online. Initial archive transmission started.” |
| LL-036 | Hana | First current packet | “That's the first new reading we've had from IRIS in four years.” |
| LL-037 | System | Near-site sample collected | “Reference sample sealed. Location and context image saved.” |
| LL-038 | Mira | M2 dock and initial archive received | “The main archive is here. One remote logger is still missing.” |
| LL-039 | Hana | Far-site objective revealed | “That's Evan's last comparison site. We can finish the record if we bring it back.” |

Restoration feedback: module enters its socket, an indicator turns on, the antenna tracks through a modest movement, and the console receives a packet. Avoid fireworks or a large cutscene. These changes persist.

Archived IRIS service note, available after the initial archive arrives:

> IRIS — FINAL FIELD CHECK
> Radio supply is out. Stored observations verified. The comparison logger is secured beside the far-rim marker, near the shade boundary. Its location is attached to this record. Replacement stock missed this rotation; leave the mounts intact for the next crew.
> — Evan

The old logger preserves a past measurement series; it has not magically stayed powered and recording for four unattended years. Its stored memory and physical recovery are fictional, declared capabilities of the programme's hardware.

### M3 — Beyond the Rim

Required objective: retrieve the far logger, complete near/far sample records and paired ground-temperature observations, then dock and deliver the records. If the near-site sample was skipped, the route/checklist includes it. The reference-site coordinates are now known; condition and traversal remain the problem.

The shorter route crosses harder ground and a temporary shadow region. The longer route reduces that exposure while spending more travel energy. The logger sits near the shade boundary rather than deep inside an unavoidable cold trap. Show the forecast before departure. Tools, thermal choices and return reserve are readable.

| ID | Speaker | Trigger | Line / text |
|---|---|---|---|
| LL-040 | Mira | M3 preparation | “This trip goes farther. Leave room for the logger and your samples.” |
| LL-041 | Hana | Science checklist | “We need both sites, with locations and temperature context. The checklist shows what's missing.” |
| LL-042 | Mira | Cold-route forecast | “The short route crosses shade. Check the heater reserve before choosing it.” |
| LL-043 | System | Sampling at disturbed target | “This spot was disturbed. Use the nearby clean reference marker.” |
| LL-044 | System | Temperature pair complete | “Paired surface-temperature record complete.” |
| LL-045 | Hana | Far logger discovered | “There it is. Both labels still attached.” |
| LL-046 | System | Logger collected | “Field logger secured. Return with the records.” |
| LL-047 | Mira | Return after collection | “You have what we need. Keep the return reserve.” |
| LL-048 | Hana | Logger and valid comparison received | “The last record is here. The sample context matches. We can finish the report.” |
| LL-049 | Mira | Final dock and full requirements | “Kite recovered. IRIS online. Field assignment complete.” |
| LL-050 | Hana | Ending | “Evan left everything ready for someone to finish. Thank you.” |

Optional archived audio at the logger, short enough to skip:

> “If you're collecting this, check the shade marker before the return climb. I put a second label underneath. The first one always gets dusty.”
> — Evan

It gives a usable hint and a recognisable habit. Do not turn it into a death message. Its actionable instruction also appears on the mission checklist.

### Common recovery and partial-result lines

| ID | Speaker | Trigger | Line / text |
|---|---|---|---|
| LL-060 | System | Return missing an inspection record | “Inspection incomplete. The service-panel image is still needed.” |
| LL-061 | Mira | Low power, parked rover | “Kite is parked. Review the route or loadout, then retry from the workshop checkpoint.” |
| LL-062 | System | M2 restored but initial archive pending | “IRIS is active. Archive receipt is still pending.” |
| LL-063 | System | M3 incomplete return | “Some required records are missing. The checklist shows the remaining targets.” |
| LL-064 | System | Data ready onboard | “Records stored onboard. Dock and send them to complete the trip.” |
| LL-065 | System | Assistance used | “Assisted recovery recorded. You can continue or retry.” |

Do not repeatedly award restoration or sample items on interaction. Preserve correct campaign state and make retries consistent with the pre-sortie checkpoint.

## Ending presentation and expansion

Return control to the human at the console. Kite remains physically in its service bay. The map shows IRIS active. Display: station restored, archive complete, comparison records received, rover recovered, energy used and any assistance. Optional screenshots appear in the report with their simulated-scene label.

## Script editing rules

- Keep canon names, equipment origins and mission gates aligned with [gameplay](../README_GAMEPLAY.md) and [mission data](examples/MISSIONS.json).
- Change the final checklist and ending condition together if M3 is deliberately reduced.
- One brief prompt beats several paragraphs while the player is driving.
- Radio lines react to actual state. A line does not itself prove a sample, repair or data transfer happened.
- Preserve the distinction between fictional programme records and real NASA history.

Voice work follows [VOICE_AND_AUDIO.md](VOICE_AND_AUDIO.md). Record final deliveries after the scene timing is stable.
