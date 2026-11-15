# Credits screen text

The text of the in-game credits roll (`game/src/ui/credits/`, board `docs/ui/boards/Credits.dc.html`),
read by the game from here (`res://res/credits.md`; an exported build needs `*.md` in the export
preset's resource filters). Each `###` heading is a section title of the roll, shown in capitals.
Under it, blocks separated by a blank line are centred entries; a block whose every line reads
`NAME | small line` is a list of name rows, any other block is shown as written, line breaks kept.
`CLOSING NOTE` is shown without a title. Keep the team and the special thanks up to date.
The root `CREDITS.md` points here and keeps the full provenance record.
The last section, GODOT ENGINE LICENCE, is not written here: `CreditsData.engine_section()` builds it
at run time from `Engine.get_license_text()` and `Engine.get_copyright_info()`, so it always matches
the engine build that is running.

### A GAME BY

TANDBORSTE | Made for the NASA Space Apps Challenge 2026

### TEAM

FAHD MUHAMMAD ZAHID | Institut Teknologi Bandung · Indonesia
MUHAMMAD RAFI WIDYATAMA | Universiti Malaya · Malaysia
FAIQ HAIDAR DZIKRULLAH SATRIAWAN | Monash University · Australia

### ORIGINAL PROTOTYPE

RAYHAN SATRIO ADI NURDJAMAN | Former team member (first-person base, October 2026)

### REAL DATA

Apollo 12 site terrain and imagery
NASA Lunar Reconnaissance Orbiter · LROC, Arizona State University

Wider lunar terrain
NASA LOLA · SLDEM2015

Star map
NASA/Goddard Scientific Visualization Studio, Deep Star Maps 2020
Gaia data: ESA/Gaia/DPAC

Earth
NASA Blue Marble

Sun, Earth and sky positions
NASA JPL Horizons

Head crater name and position
USGS Gazetteer of Planetary Nomenclature

### NASA SPACE APPS CHALLENGE RESOURCES

Design and Develop Science Missions
NASA Systems Engineering Webinar, 2025

Concept Maturity Levels
NASA JPL

Mission Design Lab
NASA Goddard

Build It Yourself: A Learning Game About Telescopes
NASA Webb

Public NASA material that the missions follow.
NASA does not endorse this game.

### BUILT WITH

Godot Engine
Blender

### AI TOOLS

Claude Opus 5.5 and Claude Sonnet 5.5
by Anthropic, used through Claude Code

Code, the Blender scripts that build the
3D models, and the music composition

Voices: ElevenLabs text to speech,
reading lines written by the team

Images: Claude Code, through Blender
and render scripts

Sound effects: Claude Code synthesis scripts,
Kenney CC0 samples, GeneralUser GS soundfont

Title logo: AI-generated silhouette, drawn
as SVG by Claude, based on NASA's photograph
of Bruce McCandless II, STS-41-B, 1984
(NASA S84-27017)

### TYPE

Michroma by Vernon Adams
Exo 2 by Natanael Gama
IBM Plex Mono by IBM
Caveat by The Caveat Project Authors

Copyright 2011 The Michroma Project Authors
Copyright 2013 The Exo 2 Project Authors
Copyright 2017 IBM Corp. All rights reserved.
Copyright 2014 The Caveat Project Authors

All four are licensed under the
SIL Open Font License, Version 1.1
openfontlicense.org

### MUSIC AND SOUND

Tandborste

Impact sounds by Kenney (kenney.nl)
Creative Commons Zero, CC0 1.0

Piano tone: GeneralUser GS soundfont
by S. Christian Collins

### SPECIAL THANKS

NASA Space Apps Challenge 2026,
the Melbourne local event organisers,
and everyone who playtested Last Light.

### CLOSING NOTE

The Apollo 12 site, Surveyor 3 and the sky are recreated from real NASA data for the second moonwalk of Apollo 12, November 1969. The workshop, Kite, IRIS and their mission are fiction.
