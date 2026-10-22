#!/usr/bin/env python3
"""
Copies your downloaded media from ~/AnimeThemes into this repo's packs/ folder, so
`git add packs && git commit && git push` backs it up to GitHub.

  python3 tools/collect-assets.py            copy new or changed media into packs/
  python3 tools/collect-assets.py --dry-run  only show what would be copied

Only media is copied: wallpapers/, live/, voice/, icons/ and sticker*.png|gif|webp.
Theme settings (variant.json, aliases.zsh, lines.txt, logo.txt) are left alone: edit
those in packs/ and run ./install.sh to send them to ~/AnimeThemes.
"""
import os, re, shutil, sys, filecmp

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.expanduser("~/AnimeThemes")
DST = os.path.join(REPO, "packs")
MEDIA_DIRS = ("wallpapers", "live", "voice", "icons")
STICKER = re.compile(r"sticker(-\d+)?\.(png|gif|webp)$", re.I)


def wanted(rel):
    parts = rel.split(os.sep)
    name = parts[-1]
    if name.startswith(".") or name.endswith((".part", ".dryrun")):
        return False
    # <anime>/<variant>/<media dir>/...   or   <anime>/<variant>/sticker*.png
    if len(parts) >= 4 and parts[2] in MEDIA_DIRS:
        return True
    return len(parts) == 3 and bool(STICKER.fullmatch(name))


def main():
    global SRC
    dry = "--dry-run" in sys.argv
    if "--src" in sys.argv:
        SRC = os.path.expanduser(sys.argv[sys.argv.index("--src") + 1])
    if not os.path.isdir(SRC):
        sys.exit(f"Nothing to collect: {SRC} doesn't exist.")
    copied = size = 0
    for root, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            src = os.path.join(root, f)
            rel = os.path.relpath(src, SRC)
            if not wanted(rel):
                continue
            dst = os.path.join(DST, rel)
            if os.path.exists(dst) and filecmp.cmp(src, dst, shallow=False):
                continue
            copied += 1
            size += os.path.getsize(src)
            if dry:
                print("  would copy", rel)
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    verb = "would be copied" if dry else "copied"
    print(f"{copied} files ({size / 1e6:.0f} MB) {verb} into packs/")


if __name__ == "__main__":
    main()
