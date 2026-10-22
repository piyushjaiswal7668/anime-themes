#!/usr/bin/env python3
"""
Files loose voice clips from a folder (default ~/Downloads, top level only) into
~/Downloads/anime-assets/<variant>/voice/, by the character named in the file name
(or, failing that, in the clip's title tag). Then run sort-assets.py to copy them into
the themes.

  matched + new        -> moved into anime-assets/<variant>/voice/
  matched + duplicate  -> deleted (same file already filed, or already in the theme)
  no character found   -> deleted (with --delete-unmatched), otherwise left alone

Usage: python3 file-loose-voices.py [--src DIR] [--assets DIR] [--delete-unmatched] [--dry-run]
"""
import argparse, hashlib, json, os, re, shutil, subprocess

AUD = {".mp3", ".m4a", ".wav", ".aac", ".ogg", ".aif", ".aiff", ".caf", ".flac", ".opus"}

# variant -> names / codes that identify it (lowercase, matched as whole words)
NAMES = {
    "nine-tails": ["naruto", "uzumaki naruto", "naruto uzumaki", "snrt", "nrt", "nrx"],
    "uchiha": ["sasuke", "saski", "ssk", "uchiha"],
    "sakura": ["sakura", "haruno"], "kakashi": ["kakashi", "hatake", "kks"], "sai": ["sai"],
    "yamato": ["yamato", "ymt"], "hinata": ["hinata"], "shikamaru": ["shikamaru"],
    "ino": ["ino", "yamanaka"], "choji": ["choji", "chouji", "akimichi"], "kiba": ["kiba", "inuzuka"],
    "shino": ["shino", "aburame"], "rock-lee": ["rock lee", "lee"], "neji": ["neji"],
    "tenten": ["tenten"], "might-guy": ["might guy", "guy", "gai"], "asuma": ["asuma"],
    "kurenai": ["kurenai"], "minato": ["minato", "namikaze"], "hiruzen": ["hiruzen", "sarutobi"],
    "hashirama": ["hashirama"], "tobirama": ["tobirama"], "jiraiya": ["jiraiya", "jiraya"],
    "tsunade": ["tsunade"], "gaara": ["gaara"], "temari": ["temari"], "kankuro": ["kankuro"],
    "killer-bee": ["killer bee", "killerbee", "bee"], "raikage": ["raikage"], "mei": ["mei", "terumi"],
    "onoki": ["onoki", "oonoki"], "madara": ["madara", "mdr"], "obito": ["obito", "tobi"],
    "shisui": ["shisui"], "indra": ["indra"], "kushina": ["kushina"], "haku": ["haku"],
    "zabuza": ["zabuza"], "kabuto": ["kabuto"], "kaguya": ["kaguya"],
    "itachi": ["itachi", "itc"], "pain": ["pain", "nagato"], "konan": ["konan"],
    "kisame": ["kisame"], "deidara": ["deidara"], "sasori": ["sasori"], "hidan": ["hidan"],
    "kakuzu": ["kakuzu"], "zetsu": ["zetsu"], "orochimaru": ["orochimaru"],
    "tanjiro": ["tanjiro", "tanjirou"], "nezuko": ["nezuko"], "zenitsu": ["zenitsu", "agatsuma"],
    "inosuke": ["inosuke", "hashibira"], "kanao": ["kanao", "tsuyuri"], "genya": ["genya"],
    "giyu": ["giyu", "giyuu", "tomioka"], "rengoku": ["rengoku", "kyojuro", "kyoujurou"],
    "shinobu": ["shinobu", "kocho", "kochou"], "tengen": ["tengen", "uzui"],
    "mitsuri": ["mitsuri", "kanroji"], "muichiro": ["muichiro", "tokito"], "obanai": ["obanai", "iguro"],
    "sanemi": ["sanemi"], "gyomei": ["gyomei", "himejima"], "muzan": ["muzan", "kibutsuji"],
    "kokushibo": ["kokushibo", "kokushibou"], "akaza": ["akaza"], "doma": ["doma", "douma"],
    "daki": ["daki", "gyutaro"], "rui": ["rui"], "enmu": ["enmu"], "yoriichi": ["yoriichi"],
    "urokodaki": ["urokodaki"], "kagaya": ["kagaya", "ubuyashiki"],
}
# Series names that contain a character name; removed before matching.
SERIES = r"naruto[\s_-]*(shippuden|shippuuden|ultimate|storm|x[\s_-]*boruto)|ultimate[\s_-]*ninja[\s_-]*storm|demon[\s_-]*slayer|kimetsu"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def title(p):
    try:
        r = subprocess.run(["ffprobe", "-v", "quiet", "-show_entries", "format_tags=title",
                            "-of", "json", p], capture_output=True, timeout=30)
        return json.loads(r.stdout or b"{}").get("format", {}).get("tags", {}).get("title", "")
    except Exception:
        return ""


def match(text):
    """Variant whose name appears earliest in text (whole words), or None."""
    t = re.sub(SERIES, " ", text.lower())
    t = " " + re.sub(r"[^a-z0-9]+", " ", t) + " "
    best = None
    for v, names in NAMES.items():
        for n in names:
            i = t.find(" " + n + " ")
            if i >= 0 and (best is None or i < best[0] or (i == best[0] and len(n) > best[2])):
                best = (i, v, len(n))
    return best[1] if best else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.expanduser("~/Downloads"))
    ap.add_argument("--assets", default=os.path.expanduser("~/Downloads/anime-assets"))
    ap.add_argument("--packs", default=os.path.expanduser("~/AnimeThemes"))
    ap.add_argument("--delete-unmatched", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    # Everything already filed or in a theme, by content and by file name
    known_sha, known_stem = {}, {}
    for root in (a.assets, a.packs):
        for d, _, names in os.walk(root):
            for n in names:
                if os.path.splitext(n)[1].lower() in AUD and "/voice" in d:
                    p = os.path.join(d, n)
                    known_sha[sha(p)] = p
                    known_stem[os.path.splitext(n)[0].lower()] = p

    moved, dup, unmatched = {}, [], []
    for n in sorted(os.listdir(a.src)):
        p = os.path.join(a.src, n)
        if not os.path.isfile(p) or os.path.splitext(n)[1].lower() not in AUD:
            continue
        v = match(os.path.splitext(n)[0])
        how = "name"
        if not v:
            v, how = match(title(p)), "title tag"
        if not v:
            unmatched.append(n)
            if a.delete_unmatched and not a.dry_run:
                os.remove(p)
            continue
        s = sha(p)
        stem = re.sub(r"\s*\(\d+\)$", "", os.path.splitext(n)[0]).lower()
        if s in known_sha or stem in known_stem:
            dup.append((n, v))
            if not a.dry_run:
                os.remove(p)
            continue
        dest_dir = os.path.join(a.assets, v, "voice")
        dest = os.path.join(dest_dir, n)
        if not a.dry_run:
            os.makedirs(dest_dir, exist_ok=True)
            shutil.move(p, dest)
        known_sha[s] = dest
        known_stem[stem] = dest
        moved.setdefault(v, []).append((n, how))

    print(f"Filed {sum(len(x) for x in moved.values())} new clips:")
    for v in sorted(moved):
        print(f"  {v:12} {len(moved[v]):4}")
        for n, how in moved[v]:
            if how != "name":
                print(f"               (by {how}) {n}")
    print(f"Duplicates removed: {len(dup)}")
    by = {}
    for _, v in dup:
        by[v] = by.get(v, 0) + 1
    for v in sorted(by):
        print(f"  {v:12} {by[v]:4}")
    print(f"No character found ({'deleted' if a.delete_unmatched else 'left alone'}): {len(unmatched)}")
    for n in unmatched:
        print("  " + n)
    if a.dry_run:
        print("(dry run: nothing moved or deleted)")


if __name__ == "__main__":
    main()
