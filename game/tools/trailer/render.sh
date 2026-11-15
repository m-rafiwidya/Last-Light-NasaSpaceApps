#!/usr/bin/env bash
# Renders the LAST LIGHT trailer from the game (Movie Maker, a window per clip) and assembles it.
#   tools/trailer/render.sh                     full: build/trailer/last_light_trailer.mp4 (+ .srt, thumbnail)
#   tools/trailer/render.sh --contact           every clip at 960x540, a preview video and contact_sheet.png
#   tools/trailer/render.sh --shot 5 [--preview]   one shot (5 renders 5; 3 renders 3a and 3b), then reassembles
#   --assemble   reassemble only
# GODOT=<binary> overrides the Godot path. Run from anywhere.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$(cd "$HERE/../.." && pwd)"
BUILD="$(cd "$GAME/.." && pwd)/build/trailer"
if [[ -z "${GODOT:-}" ]]; then
	for app in "$HOME/Downloads/Godot.app" "/Applications/Godot.app"; do
		[[ -x "$app/Contents/MacOS/Godot" ]] && GODOT="$app/Contents/MacOS/Godot" && break
	done
fi
[[ -x "${GODOT:-}" ]] || { echo "Godot 4.7 not found: set GODOT=<binary>"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found: brew install ffmpeg"; exit 1; }

PREVIEW=0; CONTACT=0; SHOT=""; ASSEMBLE_ONLY=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--preview) PREVIEW=1 ;;
		--contact) CONTACT=1; PREVIEW=1 ;;
		--shot) SHOT="$2"; shift ;;
		--assemble) ASSEMBLE_ONLY=1 ;;
		*) echo "unknown option $1"; exit 1 ;;
	esac
	shift
done

if [[ $PREVIEW == 1 ]]; then RES=960x540; WORK="$BUILD/preview"; else RES=1920x1080; WORK="$BUILD/full"; fi
mkdir -p "$WORK/clips" "$BUILD/logs"
CLIPS=($(python3 -c "import json;print(' '.join(c['id'] for c in json.load(open('$HERE/timeline.json'))['clips']))"))
if [[ -n "$SHOT" ]]; then
	SELECTED=()
	for c in "${CLIPS[@]}"; do [[ "$c" == "$SHOT" || "${c%[a-z]}" == "$SHOT" ]] && SELECTED+=("$c"); done
	[[ ${#SELECTED[@]} -gt 0 ]] || { echo "no clip '$SHOT' (clips: ${CLIPS[*]})"; exit 1; }
else
	SELECTED=("${CLIPS[@]}")
fi

godot_clip() {
	local id="$1" log="$BUILD/logs/clip_$1.log"
	echo "clip $id ($RES)"
	"$GODOT" --path "$GAME" --write-movie "$WORK/clips/clip_$id.avi" --fixed-fps 30 --resolution "$RES" \
		-s res://tools/trailer/trailer.gd -- "clip=$id" >"$log" 2>&1 || true
	grep -q "TRAILER clip $id done" "$log" || { echo "clip $id failed: see $log"; grep -E "SCRIPT ERROR|trailer:" "$log" | head -5; exit 1; }
	grep -E "^TRAILER (battery|grip|pair|iris|astronaut)" "$log" || true
}

if [[ $ASSEMBLE_ONLY == 0 ]]; then
	"$GODOT" --path "$GAME" --resolution 640x360 -s res://tools/trailer/render_text.gd -- "out=$BUILD/text" >"$BUILD/logs/text.log" 2>&1
	for id in "${SELECTED[@]}"; do godot_clip "$id"; done
fi

ARGS=(--build "$BUILD")
[[ $PREVIEW == 1 ]] && ARGS+=(--preview)
[[ $CONTACT == 1 ]] && ARGS+=(--contact)
if [[ -n "$SHOT" ]]; then
	for id in "${SELECTED[@]}"; do python3 "$HERE/assemble.py" "${ARGS[@]}" --only "$id"; echo "segment: $WORK/seg_$id.mkv"; done
fi
python3 "$HERE/assemble.py" "${ARGS[@]}"
