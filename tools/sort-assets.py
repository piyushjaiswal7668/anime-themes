#!/usr/bin/env python3
"""
Copy downloaded assets from ~/Downloads/anime-assets/<variant>/ into your theme packs
(~/AnimeThemes/<anime>/<variant>/), keeping only files that are new.

  wallpapers/*            -> <pack>/wallpapers/
  live/*.mp4|.mov         -> <pack>/live/
  sticker*.png (+gif/webp)-> <pack>/sticker.png, sticker-2.png, ... (next free number)
  voice/*                 -> <pack>/voice/<ja|en|hi>/<switch|random|build-pass|build-fail|login>/

Duplicates are skipped:
  * the exact same file (same SHA-256) already in the pack or earlier in this run
  * images that look the same at a different size or format (perceptual hash, needs ffmpeg)
  * voice clips whose file name already exists anywhere in the pack's voice folder

Originals are copied, never moved or deleted. Run again any time; it only adds what's new.
Writes a report to ~/AnimeThemes/asset-report.md.

Usage:  python3 sort-assets.py [--src DIR] [--packs DIR] [--only a,b] [--dry-run]
"""
import argparse, hashlib, os, re, shutil, subprocess, sys, json
from datetime import datetime

IMG = {".jpg", ".jpeg", ".png", ".heic", ".webp"}
VID = {".mp4", ".mov", ".m4v"}
AUD = {".mp3", ".m4a", ".wav", ".aac", ".aif", ".aiff", ".caf", ".ogg"}
STK = {".png", ".gif", ".webp"}
TARGET = {"wallpapers": (15, 20), "live": (2, 4), "stickers": (2, 3), "voice": (20, None)}
HAVE_FFMPEG = shutil.which("ffmpeg") is not None
HAVE_FFPROBE = shutil.which("ffprobe") is not None


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dhash(path):
    """64-bit difference hash of an image, or None if it can't be read."""
    if not HAVE_FFMPEG:
        return None
    try:
        raw = subprocess.run(
            ["ffmpeg", "-nostdin", "-loglevel", "quiet", "-i", path, "-frames:v", "1",
             "-vf", "scale=9:8:flags=area,format=gray", "-f", "rawvideo", "-"],
            capture_output=True, timeout=60).stdout
    except Exception:
        return None
    if len(raw) < 72:
        return None
    bits = 0
    for y in range(8):
        for x in range(8):
            bits = (bits << 1) | (raw[y * 9 + x] > raw[y * 9 + x + 1])
    return bits


def similar(h, hashes, limit=4):
    return h is not None and any(bin(h ^ o).count("1") <= limit for o in hashes)


def files(d, exts):
    if not os.path.isdir(d):
        return []
    out = []
    for root, _, names in os.walk(d):
        for n in names:
            if not n.startswith(".") and not n.endswith(".part") and os.path.splitext(n)[1].lower() in exts:
                out.append(os.path.join(root, n))
    return sorted(out)


def audio_title(path):
    if not HAVE_FFPROBE:
        return ""
    try:
        r = subprocess.run(["ffprobe", "-v", "quiet", "-show_entries", "format_tags=title",
                            "-of", "json", path], capture_output=True, timeout=30)
        return json.loads(r.stdout or b"{}").get("format", {}).get("tags", {}).get("title", "")
    except Exception:
        return ""


def voice_slot(path):
    """(language, event) from the clip's title tag and file/folder names."""
    title = audio_title(path)
    text = (path + " " + title).lower()
    if re.search(r"/hi/|hindi", text):
        lang = "hi"
    elif re.search(r"/en/|english|[-_ ]en[-_ ]", text):
        lang = "en"
    elif re.search(r"/ja/|japanese|[぀-ヿ一-鿿]", text):
        lang = "ja"
    elif title and re.search(r"[a-z]{3,}.*[!?.]?\s*$", title.split(" - ")[-1].lower()):
        lang = "en"          # title ends in an English sentence
    else:
        lang = "ja"
    for ev in ("switch", "random", "build-pass", "build-fail", "login"):
        if f"/{ev}/" in text:
            return lang, ev
    rules = [
        (r"titlecall|title-call|characterselect|character-select|beforebattle|before-battle|_ready|ready\b|appear|entry|intro|_start|v_start|battle_start", "switch"),
        (r"result|afterbattle|after-battle|victory|v_win|_win|\bwin\b", "build-pass"),
        (r"dmg|damage|_die|-die|\bdie\b|hurt|defeat|_lose|v_lose|_down|knockout|\bko\b", "build-fail"),
        (r"atk|skill|special|attack|_awk|sp_|ougi|jutsu", "build-pass"),
    ]
    for pat, ev in rules:
        if re.search(pat, text):
            return lang, ev
    return lang, "random"


def find_packs(packs_root):
    out = {}
    for anime in sorted(os.listdir(packs_root)):
        a = os.path.join(packs_root, anime)
        if not os.path.isdir(a):
            continue
        for v in sorted(os.listdir(a)):
            if os.path.isfile(os.path.join(a, v, "variant.json")):
                out[v] = os.path.join(a, v)
    return out


def stickers_in(pack):
    return sorted(os.path.join(pack, n) for n in os.listdir(pack)
                  if re.fullmatch(r"sticker(-\d+)?\.(png|gif|webp)", n, re.I))


def next_sticker_name(pack, ext, reserved=()):
    taken = {os.path.splitext(os.path.basename(p))[0].lower() for p in stickers_in(pack)} | set(reserved)
    if "sticker" not in taken:
        return "sticker" + ext
    n = 2
    while f"sticker-{n}" in taken:
        n += 1
    return f"sticker-{n}{ext}"


def unique_dest(folder, name):
    dest = os.path.join(folder, name)
    base, ext = os.path.splitext(name)
    n = 2
    while os.path.exists(dest):
        dest = os.path.join(folder, f"{base}-{n}{ext}")
        n += 1
    return dest


def count(pack):
    v = [p for p in files(os.path.join(pack, "voice"), AUD) if "/login/" not in p]
    return {
        "wallpapers": len(files(os.path.join(pack, "wallpapers"), IMG)),
        "live": len(files(os.path.join(pack, "live"), VID)),
        "stickers": len(stickers_in(pack)),
        "voice": len(v),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.expanduser("~/Downloads/anime-assets"))
    ap.add_argument("--packs", default=os.path.expanduser("~/AnimeThemes"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", help="comma-separated variant names to copy (report still covers all)")
    a = ap.parse_args()

    packs = find_packs(a.packs)
    if not packs:
        sys.exit(f"No theme packs found in {a.packs}")
    if not HAVE_FFMPEG:
        print("ffmpeg not found: only exact duplicates are detected ('brew install ffmpeg' for look-alike checks).")

    added = {}      # variant -> {kind: n}
    skipped = {}    # variant -> {reason: n}
    unknown = []

    def skip(v, why):
        skipped.setdefault(v, {}).setdefault(why, 0)
        skipped[v][why] += 1

    def add(v, kind):
        added.setdefault(v, {}).setdefault(kind, 0)
        added[v][kind] += 1

    def copy(src, dest):
        if a.dry_run:
            return
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".part"          # never leaves a half-copied file under the real name
        shutil.copy2(src, tmp)
        os.replace(tmp, dest)

    for v in sorted(os.listdir(a.src)) if os.path.isdir(a.src) else []:
        sdir = os.path.join(a.src, v)
        if not os.path.isdir(sdir) or v.startswith("."):
            continue
        if a.only and v not in a.only.split(","):
            continue
        pack = packs.get(v)
        if not pack:
            unknown.append(v)
            continue

        # What the pack already has
        existing = files(pack, IMG | VID | AUD | STK)
        shas = {sha(p) for p in existing}
        wall_h = [h for h in (dhash(p) for p in files(os.path.join(pack, "wallpapers"), IMG)) if h is not None]
        stk_h = [h for h in (dhash(p) for p in stickers_in(pack)) if h is not None]
        voice_names = {os.path.splitext(os.path.basename(p))[0].lower()
                       for p in files(os.path.join(pack, "voice"), AUD)}

        # Wallpapers
        for f in files(os.path.join(sdir, "wallpapers"), IMG):
            s = sha(f)
            if s in shas:
                skip(v, "wallpaper already there"); continue
            h = dhash(f)
            if similar(h, wall_h):
                skip(v, "wallpaper looks the same as one already there"); continue
            copy(f, unique_dest(os.path.join(pack, "wallpapers"), os.path.basename(f)))
            shas.add(s); h is not None and wall_h.append(h); add(v, "wallpapers")

        # Live videos
        for f in files(os.path.join(sdir, "live"), VID):
            s = sha(f)
            if s in shas:
                skip(v, "video already there"); continue
            copy(f, unique_dest(os.path.join(pack, "live"), os.path.basename(f)))
            shas.add(s); add(v, "live")

        # Stickers (in the variant folder itself, or a stickers/ subfolder)
        cands = [os.path.join(sdir, n) for n in sorted(os.listdir(sdir))
                 if os.path.isfile(os.path.join(sdir, n)) and re.match(r"sticker", n, re.I)
                 and os.path.splitext(n)[1].lower() in STK]
        cands += files(os.path.join(sdir, "stickers"), STK)
        reserved = set()
        for f in cands:
            s = sha(f)
            if s in shas:
                skip(v, "sticker already there"); continue
            h = dhash(f)
            if similar(h, stk_h, limit=3):
                skip(v, "sticker looks the same as one already there"); continue
            ext = os.path.splitext(f)[1].lower()
            dest = os.path.join(pack, next_sticker_name(pack, ext, reserved))
            reserved.add(os.path.splitext(os.path.basename(dest))[0].lower())
            copy(f, dest)
            shas.add(s); h is not None and stk_h.append(h); add(v, "stickers")

        # Voice
        for f in files(os.path.join(sdir, "voice"), AUD):
            s = sha(f)
            stem = os.path.splitext(os.path.basename(f))[0].lower()
            if s in shas or stem in voice_names:
                skip(v, "voice clip already there"); continue
            lang, ev = voice_slot(f)
            copy(f, unique_dest(os.path.join(pack, "voice", lang, ev), os.path.basename(f)))
            shas.add(s); voice_names.add(stem); add(v, "voice")

        # Make sure "login" has a clip: borrow one from "switch"
        if not a.dry_run:
            for lang in ("ja", "en", "hi"):
                login = os.path.join(pack, "voice", lang, "login")
                sw = files(os.path.join(pack, "voice", lang, "switch"), AUD)
                if sw and not files(login, AUD):
                    os.makedirs(login, exist_ok=True)
                    shutil.copy2(sw[0], os.path.join(login, os.path.basename(sw[0])))

    # ---- Report ----
    order = {"wallpapers": "Wallpapers", "live": "Videos", "stickers": "Stickers", "voice": "Voice"}
    rows, done_all, totals_added = [], 0, {k: 0 for k in order}
    need = {k: 0 for k in order}
    for v, pack in sorted(packs.items(), key=lambda kv: (kv[1].split(os.sep)[-2], kv[0])):
        c = count(pack)
        ad = added.get(v, {})
        cells, ok_all = [], True
        for k in order:
            lo, hi = TARGET[k]
            missing = max(0, lo - c[k])
            need[k] += missing
            ok_all &= missing == 0
            totals_added[k] += ad.get(k, 0)
            plus = f" (+{ad[k]})" if ad.get(k) else ""
            cells.append(f"{c[k]}/{lo}{plus}" + (" ✅" if missing == 0 else ""))
        done_all += ok_all
        rows.append(f"| {pack.split(os.sep)[-2]} / {v} | " + " | ".join(cells) + f" | {'✅ done' if ok_all else 'needs more'} |")

    sk_total = {}
    for d in skipped.values():
        for why, n in d.items():
            sk_total[why] = sk_total.get(why, 0) + n

    lines = [
        f"# Asset report — {datetime.now():%Y-%m-%d %H:%M}",
        "",
        f"Themes complete: **{done_all} of {len(packs)}** (meet every minimum: "
        "15 wallpapers, 2 videos, 2 stickers, 20 voice clips).",
        "",
        "## This run",
        "",
        "Added: " + ", ".join(f"{totals_added[k]} {order[k].lower()}" for k in order)
        + (" (dry run, nothing copied)" if a.dry_run else ""),
        "",
        "Skipped as duplicates: " + (", ".join(f"{n} × {why}" for why, n in sorted(sk_total.items())) or "none"),
    ]
    if unknown:
        lines += ["", "Folders with no matching theme (not copied): " + ", ".join(unknown)]
    lines += [
        "",
        "## Still needed across all themes",
        "",
        ", ".join(f"{need[k]} {order[k].lower()}" for k in order),
        "",
        "## Per theme (have / minimum, + = added now)",
        "",
        "| Theme | Wallpapers | Videos | Stickers | Voice | Status |",
        "|---|---|---|---|---|---|",
        *rows,
    ]
    report = "\n".join(lines) + "\n"
    if not a.dry_run:
        with open(os.path.join(a.packs, "asset-report.md"), "w") as f:
            f.write(report)
    print(report)


if __name__ == "__main__":
    main()
