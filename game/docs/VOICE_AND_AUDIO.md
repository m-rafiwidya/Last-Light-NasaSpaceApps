# LAST LIGHT — voice and audio production

**Recommendation: use your own performances for the final chapter.**

The team needs two short radio roles and one archive performance, not a fully voiced cast. Self-recording gives you control of phrasing, timing and revisions. It can make the expedition feel personal; clear delivery matters more than the recording method. It does not automatically earn judging points.

## Exact recording scope

The current [script](STORY_SCRIPT.md) has **44 numbered entries**: **17 Mira**, **11 Hana**, and **16 System**. Record the **28 character entries**, plus Evan's one optional archived message. System entries remain text/UI feedback. The other two service notes are text props. Recount if the script changes.

Suggested cast:

- Mira: calm, practical systems lead; sound like someone helping a colleague complete a job.
- Hana: precise science lead, warmer when she recognises the earlier crew's work. Underplay the final thanks.
- Evan: one matter-of-fact field recording, with a little dry humour. No dramatic death message.

Natural accents fit an international programme. English is the proposed game language; pronounce Kite and IRIS consistently. One person can play a second role if necessary, but different performers are simpler to distinguish. No voice is required for the player.

## Recording session

1. Confirm the line triggers in the playable scenes before recording the final takes.
2. Use the quietest soft-furnished room available. Turn off nearby fans/notifications. A phone is sufficient for a test.
3. Keep the microphone roughly 15–25 cm away and slightly off-axis. Use a consistent position. Do not clip peaks.
4. Record a little room tone, then three natural takes of each line. Pause between lines. Prefer conversational clarity over an exaggerated “radio voice.”
5. Keep the original recording. If supported, use WAV at a consistent 48 kHz and 16/24 bit; do not invent extra quality by upsampling a poor recording.
6. Name takes `LL-002_Mira_take01.wav`; use `ARCHIVE-LOGGER_Evan_take01.wav` for the archive. Faiq selects deliveries and checks wording against the script.
7. Trim, remove obvious noise carefully and match perceived loudness. Apply only a light radio treatment to Earth voices. Keep an unfiltered original.
8. Export through the project's current Godot audio pipeline. Test intelligibility with music, effects and subtitles in the actual build.

A heavily filtered line that sounds cinematic but is hard to understand is worse than a clean phone recording. Do not wait for a studio setup before testing.

## In-game playback

Use one dialogue queue and the existing resource system. Store content ID, speaker, subtitle, audio path, trigger, replay policy and priority. Do not invent a second narrative manager just for voice.

- Critical instructions also appear in the objective/checklist.
- Subtitles are on by default, with speaker names and readable contrast.
- Skip/mute/review work; mute does not stop mission progression.
- Play one voice at a time. A reserve warning takes priority over an optional archive, with a cooldown.
- Duck music lightly during speech. Do not block driving or force the player to stare at a console until a line finishes.
- Use state events rather than arbitrary timers. Do not play the ending while the logger is still onboard outside the base.

## Sound palette

| Location/action | Useful audio |
|---|---|
| Workshop | Quiet ventilation, close footsteps, latch/part placement and console confirmation |
| Rover control | Optional onboard contact/vibration pickup or declared UI sonification for motors/wheels; subtle tyre-contact feedback |
| IRIS repair | Module latch, electrical/status confirmation and one clear online cue |
| Sample/logger | Scoop/contact cue, container latch, cargo secure confirmation |
| Warnings | Distinct short battery/thermal alerts with matching text; no continuous siren |
| Ending | A restrained musical change as the received archive and docked rover appear |

Do not use terrestrial wind or rain outdoors. Exterior mechanical feedback is not sound travelling through lunar air to a distant listener. Use the viewpoint's onboard pickup/interface convention. Avoid overloading every metre of travel with dialogue.

## When ElevenLabs helps

Use it for temporary timing placeholders or a missing performance only if that improves the build. Keep final subtitles/content IDs unchanged when replacing audio.

Check the actual plan and current publication terms before including generated audio. [ElevenLabs' official publication guidance](https://help.elevenlabs.io/hc/en-us/articles/13313564601361-Can-I-publish-the-content-I-generate-on-the-platform) currently says free-plan output lacks a commercial licence and requires attribution when published; paid-plan conditions and exceptions also matter. Record the source/plan/date and required credits with the chosen file. Do not clone someone else's voice without their permission.

For this team, self-recording is the simpler final-production choice. Use the saved time to test whether players understand a line while driving.
