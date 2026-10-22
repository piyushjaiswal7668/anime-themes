#!/usr/bin/env python3
"""
Download wallpapers for each theme variant from Wallhaven's official public API
(https://wallhaven.cc/help/api). Safe-for-work anime images only.

Saves into ~/Downloads/anime-assets/<variant>/wallpapers/, the layout Claude sorts from.
Already-downloaded images are skipped, so you can run it again any time.

Usage:
  python3 fetch-wallpapers.py                         # every variant, 4 images each, >= 1920x1080
  python3 fetch-wallpapers.py --only kakashi,minato   # just these variants
  python3 fetch-wallpapers.py --count 6 --min 3840x2160
  python3 fetch-wallpapers.py --list                  # show the variants and search terms

Uses only Python's standard library; nothing to install.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://wallhaven.cc/api/v1/search"
USER_AGENT = "AnimeThemes-wallpaper-fetcher/1.0 (personal use)"
REQUEST_GAP = 1.5          # seconds between API calls; Wallhaven allows 45 per minute
OUT = os.path.expanduser("~/Downloads/anime-assets")

# variant folder -> search terms (character name as Wallhaven tags it)
VARIANTS = {
    # Naruto
    "nine-tails": "Uzumaki Naruto", "uchiha": "Uchiha Sasuke", "sakura": "Haruno Sakura",
    "kakashi": "Hatake Kakashi", "sai": "Sai (Naruto)", "yamato": "Yamato (Naruto)",
    "hinata": "Hyuuga Hinata", "shikamaru": "Nara Shikamaru", "ino": "Yamanaka Ino",
    "choji": "Akimichi Chouji", "kiba": "Inuzuka Kiba", "shino": "Aburame Shino",
    "rock-lee": "Rock Lee", "neji": "Hyuuga Neji", "tenten": "Tenten",
    "might-guy": "Might Guy", "asuma": "Sarutobi Asuma", "kurenai": "Yuuhi Kurenai",
    "minato": "Namikaze Minato", "hiruzen": "Sarutobi Hiruzen", "hashirama": "Senju Hashirama",
    "tobirama": "Senju Tobirama", "jiraiya": "Jiraiya", "tsunade": "Tsunade",
    "gaara": "Gaara", "temari": "Temari", "kankuro": "Kankuro", "killer-bee": "Killer Bee",
    "raikage": "Raikage A", "mei": "Terumi Mei", "onoki": "Oonoki",
    "madara": "Uchiha Madara", "obito": "Uchiha Obito", "shisui": "Uchiha Shisui",
    "indra": "Indra Otsutsuki", "kushina": "Uzumaki Kushina", "haku": "Haku (Naruto)",
    "zabuza": "Momochi Zabuza", "kabuto": "Yakushi Kabuto", "kaguya": "Otsutsuki Kaguya",
    # Akatsuki
    "itachi": "Uchiha Itachi", "pain": "Pain (Naruto)", "konan": "Konan",
    "kisame": "Hoshigaki Kisame", "deidara": "Deidara", "sasori": "Sasori",
    "hidan": "Hidan", "kakuzu": "Kakuzu", "zetsu": "Zetsu", "orochimaru": "Orochimaru",
    # Demon Slayer
    "tanjiro": "Kamado Tanjirou", "nezuko": "Kamado Nezuko", "zenitsu": "Agatsuma Zenitsu",
    "inosuke": "Hashibira Inosuke", "kanao": "Tsuyuri Kanao", "genya": "Shinazugawa Genya",
    "giyu": "Tomioka Giyuu", "rengoku": "Rengoku Kyoujurou", "shinobu": "Kochou Shinobu",
    "tengen": "Uzui Tengen", "mitsuri": "Kanroji Mitsuri", "muichiro": "Tokitou Muichirou",
    "obanai": "Iguro Obanai", "sanemi": "Shinazugawa Sanemi", "gyomei": "Himejima Gyoumei",
    "muzan": "Kibutsuji Muzan", "kokushibo": "Kokushibou", "akaza": "Akaza (Kimetsu no Yaiba)",
    "doma": "Douma", "daki": "Daki (Kimetsu no Yaiba)", "rui": "Rui (Kimetsu no Yaiba)",
    "enmu": "Enmu", "yoriichi": "Tsugikuni Yoriichi", "urokodaki": "Urokodaki Sakonji",
    "kagaya": "Ubuyashiki Kagaya",
}


def api_search(query, min_res, page=1):
    params = {
        "q": query,
        "categories": "010",      # anime only
        "purity": "100",          # safe for work only
        "atleast": min_res,
        "ratios": "16x9,16x10",
        "sorting": "relevance",
        "page": str(page),
    }
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r).get("data", [])
        except urllib.error.HTTPError as e:
            if e.code == 429:   # rate limited: wait and try again
                time.sleep(15 * (attempt + 1))
                continue
            raise
    return []


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    tmp = dest + ".part"
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, dest)


def main():
    ap = argparse.ArgumentParser(description="Download Wallhaven wallpapers for each theme variant.")
    ap.add_argument("--only", help="comma-separated variant folder names")
    ap.add_argument("--count", type=int, default=4, help="images per variant (default 4)")
    ap.add_argument("--min", default="1920x1080", help="minimum resolution, e.g. 3840x2160")
    ap.add_argument("--list", action="store_true", help="list variants and search terms")
    args = ap.parse_args()

    if args.list:
        for k, q in VARIANTS.items():
            print(f"{k:14} {q}")
        return

    names = list(VARIANTS)
    if args.only:
        wanted = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in wanted if n not in VARIANTS]
        if unknown:
            sys.exit(f"Unknown variant(s): {', '.join(unknown)}. Run with --list to see names.")
        names = wanted

    summary = []
    for name in names:
        folder = os.path.join(OUT, name, "wallpapers")
        os.makedirs(folder, exist_ok=True)
        have = [f for f in os.listdir(folder) if f.startswith("wallhaven-") and not f.endswith(".part")]
        need = args.count - len(have)
        if need <= 0:
            summary.append((name, len(have), "already complete"))
            continue

        got, note = 0, ""
        try:
            time.sleep(REQUEST_GAP)
            results = api_search(VARIANTS[name], args.min)
        except Exception as e:
            summary.append((name, len(have), f"search failed: {e}"))
            continue

        for item in results:
            if got >= need:
                break
            ext = os.path.splitext(item.get("path", ""))[1] or ".jpg"
            dest = os.path.join(folder, f"wallhaven-{item['id']}-{item.get('resolution', '')}{ext}")
            if os.path.exists(dest):
                continue
            try:
                time.sleep(REQUEST_GAP)
                download(item["path"], dest)
                got += 1
                print(f"  {name}: {os.path.basename(dest)}")
            except Exception as e:
                note = f"some downloads failed ({e})"
        if not results:
            note = "no matches; try a different search term or a lower --min"
        summary.append((name, len(have) + got, note or "ok"))

    print("\nVariant         images  note")
    for name, n, note in summary:
        print(f"{name:15} {n:>6}  {note}")
    print(f"\nSaved under {OUT}. Tell Claude when you're ready to sort them.")


if __name__ == "__main__":
    main()
