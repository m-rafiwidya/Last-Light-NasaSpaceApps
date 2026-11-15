#!/usr/bin/env python3
"""Assembles the LAST LIGHT trailer from the Movie Maker clips (see render.sh).

    assemble.py --build build/trailer [--preview] [--contact] [--only <clip>]
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))


def run(cmd, quiet=True):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(" ".join(cmd) + "\n" + r.stderr[-4000:])
        sys.exit(r.returncode)
    return r


def probe(path, entry):
    r = run(["ffprobe", "-v", "error", "-show_entries", entry, "-of", "csv=p=0", path])
    return r.stdout.strip().splitlines()


def has_audio(path):
    return bool(probe(path, "stream=codec_type") and "audio" in probe(path, "stream=codec_type"))


def envelope(points):
    """Piecewise-linear gain over t from [(t, gain)], as an ffmpeg expression."""
    expr = "%f" % points[-1][1]
    for (t0, g0), (t1, g1) in reversed(list(zip(points, points[1:]))):
        if t1 <= t0:
            seg = "%f" % g1
        else:
            seg = "(%f+(%f)*(t-%f)/%f)" % (g0, g1 - g0, t0, t1 - t0)
        expr = "if(lt(t,%f),%s,%s)" % (t1, seg, expr)
    return "if(lt(t,%f),%f,%s)" % (points[0][0], points[0][1], expr)


def db(v):
    return 0.0 if v is None else 10 ** (v / 20.0)


def speech_segments(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af",
        "silencedetect=noise=-38dB:d=0.3", "-f", "null", "-"], capture_output=True, text=True)
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", r.stderr)]
    total = float(probe(path, "format=duration")[0])
    segments, cursor = [], 0.0
    for s, e in zip(starts, ends + [total] * (len(starts) - len(ends))):
        if s > cursor + 0.05:
            segments.append((cursor, s))
        cursor = e
    if total > cursor + 0.05:
        segments.append((cursor, total))
    return segments


def voice_cuts(timeline):
    cuts = []
    for v in timeline["voice"]:
        path = os.path.join(GAME, "res/audio/voice", v["file"] + ".ogg")
        segs = speech_segments(path)
        a, b = v["sentences"]
        start = max(segs[a - 1][0] - 0.04, 0.0)
        end = segs[b - 1][1] + 0.08
        cuts.append(dict(v, path=path, start=start, end=end, length=end - start))
    return cuts


def srt_time(t):
    ms = int(round(t * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", required=True)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--contact", action="store_true")
    ap.add_argument("--only")
    args = ap.parse_args()

    timeline = json.load(open(os.path.join(HERE, "timeline.json")))
    fps, xf, total = timeline["fps"], timeline["xfade"], timeline["length"]
    w, h = (960, 540) if args.preview else (1920, 1080)
    work = os.path.join(args.build, "preview" if args.preview else "full")
    text = os.path.join(args.build, "text")
    clips = timeline["clips"]

    # 1. Segments: the last (end - start + xfade) s of each Movie Maker clip, normalised
    for i, c in enumerate(clips):
        if args.only and c["id"] != args.only:
            continue
        src = os.path.join(work, "clips", "clip_%s.avi" % c["id"])
        seg = os.path.join(work, "seg_%s.mkv" % c["id"])
        if not os.path.exists(src):
            continue
        length = c["end"] - c["start"] + (xf if i < len(clips) - 1 else 0.0)
        frames = int(round(length * fps))
        duration = float(probe(src, "format=duration")[0])
        start = max(duration - length, 0.0)
        vf = "scale=%d:%d:flags=lanczos,fps=%d,format=yuv420p" % (w, h, fps)
        if c.get("zoom"):
            cx, cy, z1, z0 = (c["zoom"] + [1.0])[:4]
            k = "(on/%d)" % max(frames - 1, 1)
            vf = ("scale=%d:%d:flags=lanczos,zoompan=z='%f+%f*%s*%s*(3-2*%s)':x='%f*iw-iw/zoom/2':y='%f*ih-ih/zoom/2'"
                ":d=1:s=%dx%d:fps=%d,format=yuv420p") % (w * 2, h * 2, z0, z1 - z0, k, k, k, cx, cy, w, h, fps)
        if c.get("dim"):
            vf += ",colorlevels=romax={0}:gomax={0}:bomax={0}".format(c["dim"])
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", "%.4f" % start, "-i", src]
        if has_audio(src):
            af = ["-af", "aresample=48000,aformat=channel_layouts=stereo,apad,atrim=0:%.4f" % length]
        else:
            cmd += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
            af = ["-map", "0:v", "-map", "1:a", "-af", "atrim=0:%.4f" % length]
        run(cmd + ["-vf", vf, "-frames:v", str(frames)] + af + ["-c:v", "libx264", "-preset", "veryfast",
            "-crf", "12", "-c:a", "pcm_s16le", seg])
    if args.only:
        return
    missing = [c["id"] for c in clips if not os.path.exists(os.path.join(work, "seg_%s.mkv" % c["id"]))]
    if missing:
        print("assemble: clips not rendered yet: %s" % ", ".join(missing))
        return

    # 2. Cuts with short crossfades
    inputs, graph = [], []
    for c in clips:
        inputs += ["-i", os.path.join(work, "seg_%s.mkv" % c["id"])]
    v, a = "[0:v]", "[0:a]"
    for k in range(1, len(clips)):
        off = clips[k]["start"]
        graph.append("%s[%d:v]xfade=transition=fade:duration=%.3f:offset=%.3f[v%d]" % (v, k, xf, off, k))
        graph.append("%s[%d:a]acrossfade=d=%.3f:c1=tri:c2=tri[a%d]" % (a, k, xf, k))
        v, a = "[v%d]" % k, "[a%d]" % k
    n = len(clips)

    # 3. Text: captions, voice subtitles, title
    voices = voice_cuts(timeline)
    overlays = [(os.path.join(text, "caption_%d.png" % i), c["from"], c["to"]) for i, c in enumerate(timeline["captions"])]
    overlays += [(os.path.join(text, "voice_%d.png" % i), vc["at"], vc["at"] + vc["length"]) for i, vc in enumerate(voices)]
    overlays.append((os.path.join(text, "title.png"), timeline["title"]["from"], total + 1.0))
    for i, (png, t0, t1) in enumerate(overlays):
        inputs += ["-loop", "1", "-framerate", str(fps), "-t", "%.3f" % (total + 1), "-i", png]
        fade = 0.5 if png.endswith("title.png") else 0.22
        graph.append("[%d:v]scale=%d:%d,format=rgba,fade=t=in:st=%.3f:d=%.2f:alpha=1,fade=t=out:st=%.3f:d=%.2f:alpha=1[t%d]"
            % (n + i, w, h, t0, fade, max(t1 - fade, t0), fade, i))
        graph.append("%s[t%d]overlay=shortest=0:enable='between(t,%.3f,%.3f)'[o%d]" % (v, i, t0, t1, i))
        v = "[o%d]" % i
    graph.append("%sfade=t=in:st=0:d=%.2f,fade=t=out:st=%.3f:d=%.2f,trim=0:%.3f,setpts=PTS-STARTPTS[vout]"
        % (v, timeline["fade_in"], total - timeline["fade_out"], timeline["fade_out"], total))

    # 4. Audio: game sound, music with its envelope and ducking, voice lines
    base = n + len(overlays)
    ga = timeline["game_audio"]
    game_env = [(0.0, db(ga["db"]))]
    if ga.get("silence"):
        s0, s1 = ga["silence"]
        game_env += [(s0 - 0.05, db(ga["db"])), (s0, 0.0), (s1, 0.0), (s1 + 0.1, db(ga["db"]))]
    graph.append("%svolume='%s':eval=frame[game]" % (a, envelope(game_env)))
    m = timeline["music"]
    keys = [(t, db(d)) for t, d in m["keys"]]
    dip = m["dip"]
    fo0, fo1 = m["fade_out"]
    low = db(m["keys"][-1][1] + dip["db"])
    t0 = dip["at"]
    keys += [(t0, keys[-1][1]), (t0 + dip["down"], low), (t0 + dip["down"] + dip["hold"], low),
        (t0 + dip["down"] + dip["hold"] + dip["up"], db(m["return_db"])), (fo0, db(m["return_db"])), (fo1, 0.0)]
    duck = [(0.0, 1.0)]
    for vc in voices:
        duck += [(vc["at"] - 0.25, 1.0), (vc["at"], db(-m.get("duck_db", 8.0))), (vc["at"] + vc["length"], db(-m.get("duck_db", 8.0))),
            (vc["at"] + vc["length"] + 0.35, 1.0)]
    inputs += ["-i", os.path.join(GAME, m["file"])]
    graph.append("[%d:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:%.3f,volume='%s':eval=frame,volume='%s':eval=frame[music]"
        % (base, total, envelope(keys), envelope(duck)))
    mix = ["[game]", "[music]"]
    for i, vc in enumerate(voices):
        inputs += ["-i", vc["path"]]
        graph.append("[%d:a]atrim=%.3f:%.3f,asetpts=PTS-STARTPTS,afade=t=in:d=0.02,afade=t=out:st=%.3f:d=0.06,"
            "aresample=48000,aformat=channel_layouts=stereo,adelay=%d:all=1[voice%d]"
            % (base + 1 + i, vc["start"], vc["end"], vc["length"] - 0.06, int(vc["at"] * 1000), i))
        mix.append("[voice%d]" % i)
    graph.append("%samix=inputs=%d:normalize=0:duration=first,afade=t=out:st=%.3f:d=%.2f,atrim=0:%.3f,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]"
        % ("".join(mix), len(mix), total - timeline["fade_out"], timeline["fade_out"], total))

    out_dir = args.build if not args.preview else work
    name = "last_light_trailer" + ("_preview" if args.preview else "")
    mp4 = os.path.join(out_dir, name + ".mp4")
    script = os.path.join(work, "filter.txt")
    open(script, "w").write(";\n".join(graph))
    run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-/filter_complex", script, "-map", "[vout]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-r", str(fps),
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", "-t", "%.3f" % total, mp4])

    # 5. Subtitles (.srt) of every on-screen line
    entries = [(c["from"], c["to"], c["text"]) for c in timeline["captions"]]
    entries += [(vc["at"], vc["at"] + vc["length"], "%s: %s" % (vc["speaker"], vc["text"])) for vc in voices]
    entries.append((timeline["title"]["from"], total, "\n".join(timeline["title"]["lines"])))
    entries.sort()
    with open(os.path.join(out_dir, name + ".srt"), "w") as f:
        for i, (t0, t1, line) in enumerate(entries):
            f.write("%d\n%s --> %s\n%s\n\n" % (i + 1, srt_time(t0), srt_time(t1), line))

    # 6. Thumbnail: the title over its (dimmed) background clip
    last = os.path.join(work, "seg_%s.mkv" % clips[-1]["id"])
    run(["ffmpeg", "-v", "error", "-y", "-ss", "1.5", "-i", last, "-i", os.path.join(text, "title.png"), "-filter_complex",
        "[0:v]scale=1920:1080:flags=lanczos[b];[b][1:v]overlay", "-frames:v", "1", os.path.join(out_dir, name + "_thumbnail.png")])

    # 7. Contact sheet: one frame from the middle of each clip
    if args.contact:
        frames = []
        for i, c in enumerate(clips):
            png = os.path.join(work, "contact_%02d.png" % i)
            mid = c["start"] + (c["end"] - c["start"]) * 0.6
            run(["ffmpeg", "-v", "error", "-y", "-ss", "%.3f" % mid, "-i", mp4, "-frames:v", "1", "-vf", "scale=480:270", png])
            frames.append(png)
        cols = 4
        rows = math.ceil(len(frames) / cols)
        cmd = ["ffmpeg", "-v", "error", "-y"]
        for p in frames:
            cmd += ["-i", p]
        layout = "|".join("%d_%d" % ((i % cols) * 484, (i // cols) * 274) for i in range(len(frames)))
        cmd += ["-filter_complex", "%sxstack=inputs=%d:layout=%s:fill=0x202020" % ("".join("[%d:v]" % i for i in range(len(frames))),
            len(frames), layout), "-frames:v", "1", os.path.join(out_dir, "contact_sheet.png")]
        run(cmd)

    length = float(probe(mp4, "format=duration")[0])
    print("assemble: %s  %.3f s  %s" % (mp4, length, "OK (< 30.0 s)" if length < 30.0 else "TOO LONG"))
    for vc in voices:
        print("voice %-16s sentences %s: %.2f-%.2f s in the file, %.2f s long, on screen %.2f-%.2f"
            % (vc["file"], vc["sentences"], vc["start"], vc["end"], vc["length"], vc["at"], vc["at"] + vc["length"]))
    for prev, nxt in zip(voices, voices[1:]):
        if prev["at"] + prev["length"] > nxt["at"]:
            print("WARNING: %s overlaps %s by %.2f s" % (prev["file"], nxt["file"], prev["at"] + prev["length"] - nxt["at"]))


if __name__ == "__main__":
    main()
