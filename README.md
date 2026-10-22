# 🍥 Anime Themes

A macOS menu bar app that turns your whole Mac into a Naruto or Demon Slayer theme.
Pick a character from the 🍥 menu and everything changes to match their colors:

| | What happens |
|---|---|
| Wallpaper | A random image from the character's folder (a palette gradient if there are none) |
| Live wallpaper | A looping, muted video behind your desktop icons |
| Accent color | The closest macOS accent color |
| Terminal | Colors and the Maple Mono font in the built-in Terminal, including open windows |
| Shell | Themed prompt, aliases (`rasengan` = `git push`), ASCII logo and a motivational line in new windows |
| VS Code | Custom color theme, Maple Mono, a character sticker and a faint wallpaper, in every VS Code profile |
| App icons | Your apps get icons in the palette with the character's motif |
| Voice | Character lines (Japanese, English or Hindi) when you switch, at login, on a timer, and when builds pass or fail |
| Desktop widgets | Clock, system stats, dev/git, now playing, character portrait and a quote card, all in the theme's colors |
| Menu bar | SketchyBar recolors to match (optional) |
| Theme rotation | Keep one theme, or get a random one at login / every hour / every day, from all anime or only the current one |

75 characters: **Naruto** (Team 7, Konoha 11, Sensei & Kage, Sand & Other Villages, Uchiha,
Others, Akatsuki) and **Demon Slayer** (Tanjiro & Friends, Hashira, Demons, Others).
The full list with colors is in [`packs/CHARACTERS.md`](packs/CHARACTERS.md); every alias is in
[`packs/ALIASES.md`](packs/ALIASES.md).

---

## Contents

1. [Install on a Mac (from GitHub)](#1-install-on-a-mac-from-github)
2. [First run and permissions](#2-first-run-and-permissions)
3. [Using it](#3-using-it)
4. [Adding wallpapers, videos, stickers and voices](#4-adding-wallpapers-videos-stickers-and-voices)
5. [Backing up to GitHub](#5-backing-up-to-github)
6. [How the repo is laid out](#6-how-the-repo-is-laid-out)
7. [Troubleshooting](#7-troubleshooting)
8. [Uninstall](#8-uninstall)

---

## 1. Install on a Mac (from GitHub)

Needs **macOS 15 or newer** (Apple Silicon or Intel).

```bash
# 1. Tools (once per Mac). Homebrew: https://brew.sh
xcode-select --install          # Apple's command line tools, if you don't have them
brew install git git-lfs
git lfs install                 # turns on large-file support for git

# 2. Get the code and all the assets (about 2.5 GB)
git clone https://github.com/<your-username>/anime-themes.git ~/anime-themes
cd ~/anime-themes

# 3. Install
chmod +x install.sh build.sh uninstall.sh
./install.sh                      # everything except SketchyBar
# or
./install.sh --with-sketchybar    # also installs the SketchyBar menu bar
```

> If `git clone` finishes but the images are tiny text files, LFS wasn't on when you cloned.
> Run `git lfs install && git lfs pull` inside the folder.

The installer:
- copies the theme packs (settings **and** your assets) to `~/AnimeThemes`
- adds one line to `~/.zshrc` (a backup is saved first)
- installs the Maple Mono font with Homebrew if it's missing
- builds the app into `~/Applications/Anime Themes.app` and opens it

It's safe to run again any time. It never deletes files from `~/AnimeThemes`.

### Updating later

```bash
cd ~/anime-themes
git pull
./install.sh
```

---

## 2. First run and permissions

Click 🍥 in the menu bar and pick a character. macOS asks for a few things the first time:

| Prompt | Why | Where to change it later |
|---|---|---|
| **Control Terminal?** → OK | Switches Terminal colors in open windows | System Settings → Privacy & Security → Automation |
| **Accessibility** | The ⏮ ⏯ ⏭ buttons on the Now playing widget | System Settings → Privacy & Security → Accessibility |
| **Control your browser / Spotify / Music?** → OK | Now playing widget shows the song | Automation (same place as above) |

For browser music (YouTube etc.) to show the time bar and seek, turn on
**View → Developer → Allow JavaScript from Apple Events** in Chrome, Brave, Arc or Edge
(Safari: Settings → Advanced → Show features for web developers, then Develop → Allow JavaScript from Apple Events).

VS Code: the app installs its theme extension and the free **background** extension (by shalldie)
for you. Restart VS Code once. If you see "installation appears to be corrupt", choose
**Don't show again**; that's how the background extension works.

Then open a **new Terminal window** to see the greeting and prompt.

---

## 3. Using it

### Menu

| Item | What it does |
|---|---|
| Naruto / Demon Slayer → group → character | Apply that theme |
| Next wallpaper (⌘N) | Another image and video from the folder |
| Pause live wallpaper | Keep the video still (saves battery) |
| New line now | New quote on the card, plus a random voice clip |
| Re-apply theme | Run the current theme again (after adding files) |
| **Theme rotation** | **Keep the same theme**, **Random from all anime** or **Random from <current anime> only**; change **each time you log in**, **every hour**, **every 3 hours** or **every day**; **Shuffle now** (⌘R) |
| Voice | On/off, language (Japanese / English / Hindi), volume, read lines aloud when there are no clips, play a test clip |
| Desktop widgets | Show/hide, turn each widget on/off, **Edit layout** to drag them, **Reset positions**, how often the quote changes |
| What a theme changes | Turn any part off; **Restore original app icons** |
| Open at login | Start with your Mac (needed for "rotate each time you log in") |
| Open theme packs folder / Reload theme packs | Open `~/AnimeThemes` / pick up new characters |

### Terminal commands

| Command | What it does |
|---|---|
| `anime-aliases` | List the current theme's aliases |
| `anime-greet` | Show the logo and a line again |
| `anime-line` | Print one random line |
| `anime-voice build-pass` | Play a clip (`switch`, `random`, `build-pass`, `build-fail`, `login`) |

Build sounds play for commands like `npm test`, `npm run build`, `jest`, `pytest`,
`cargo build`, `flutter build`, `gradlew`, `swift build` and `make` that run 2 seconds or more.
Ctrl-C stays silent. Each project's last result shows on the Dev widget.

Options for `~/.zshrc`, **above** the Anime Themes line:

```zsh
ANIME_PROMPT=0              # keep your own prompt
ANIME_GREETING=0            # no greeting in new windows
ANIME_BUILD_MIN_SECONDS=5   # only longer builds get a sound
ANIME_BUILD_PATTERN='...'   # your own list of build commands (zsh regex)
```

### Aliases

Every theme gets its anime's shared aliases plus a few of the character's own.
Run `anime-aliases`, or see [`packs/ALIASES.md`](packs/ALIASES.md) for all of them.
Edit them in `packs/<anime>/aliases.zsh` (shared) or `packs/<anime>/<character>/aliases.zsh`,
then run `./install.sh` and pick the theme again.

---

## 4. Adding wallpapers, videos, stickers and voices

Everything lives in `~/AnimeThemes/<anime>/<character>/`:

```
wallpapers/                    still images (.jpg .png .heic), 1920x1080 or larger
live/                          looping videos (.mp4 .mov; not .webm)
sticker.png, sticker-2.png …   transparent character PNGs for the VS Code corner (one is picked at random)
voice/ja|en|hi/switch/         when you pick this theme
voice/ja|en|hi/random/         on the timer and "Play a test clip"
voice/ja|en|hi/build-pass/     build or tests passed
voice/ja|en|hi/build-fail/     build or tests failed
voice/ja|en|hi/login/          when the Mac starts
icons/                         optional: your own app icon as "<App Name>.png"
```

If a language or a moment has no clips, the app falls back to another language, then to any
clip that character has. After adding files, choose **Re-apply theme**.

### Helper scripts (in `tools/`)

Downloads normally go to `~/Downloads/anime-assets/<character>/` with the same layout
(`wallpapers/`, `live/`, `voice/`, `sticker*.png`). Then:

```bash
# Loose voice clips sitting in ~/Downloads: file the ones with a character name in the
# file name, delete the rest (and duplicates)
python3 tools/file-loose-voices.py --delete-unmatched

# Copy everything new from ~/Downloads/anime-assets into your themes.
# Skips duplicates (same file, or the same picture at another size) and writes
# ~/AnimeThemes/asset-report.md: what each theme has and what's still missing.
python3 tools/sort-assets.py              # add --dry-run to preview

# Wallpapers straight from Wallhaven's free API
python3 tools/fetch-wallpapers.py --only kakashi,minato --count 6 --min 2560x1440
```

Targets per character: 15–20 wallpapers, 2–4 videos, 2–3 stickers, 20+ voice clips.
`brew install ffmpeg` makes the duplicate check smarter (look-alike images) and sorts voice clips by their title tag.

---

## 5. Backing up to GitHub

Your assets live in `~/AnimeThemes` while you use the app. To save them in this repo:

```bash
cd ~/anime-themes
python3 tools/collect-assets.py     # copies new media from ~/AnimeThemes into packs/
git add -A
git commit -m "Add new assets"
git push
```

`collect-assets.py` only copies media (wallpapers, videos, voices, icons, stickers);
it never touches the theme settings in `packs/`.

### First push (once)

1. On github.com, create a new **private** repository called `anime-themes`
   (no README, no .gitignore; this folder already has them).
2. In Terminal:

```bash
cd ~/anime-themes                # wherever this folder is
git lfs install
git init -b main
git add -A
git commit -m "Anime Themes app and assets"
git remote add origin https://github.com/<your-username>/anime-themes.git
git push -u origin main
```

The first push uploads about 2.5 GB, so give it time. When asked for a password, use a
[personal access token](https://github.com/settings/tokens), or sign in once with
`brew install gh && gh auth login`.

Keep the repo **private**: the wallpapers, voices and stickers are fan art and game audio for
personal use, not yours to redistribute.

### Large files

Images, videos and audio go through **Git LFS** (set up in `.gitattributes`). GitHub's free plan
includes 10 GB of LFS storage and 10 GB of download per month. A full clone uses about 2.5 GB
of that, so a few fresh clones a month is fine; `git pull` only downloads what changed.
Check usage at github.com → Settings → Billing.

---

## 6. How the repo is laid out

```
anime-themes/
├── install.sh / uninstall.sh / build.sh
├── Package.swift, Resources/, Sources/AnimeThemes/   the Swift app
│   ├── Modules/        wallpaper, accent, Terminal, shell, VS Code, icons, voice, live wallpaper, SketchyBar
│   └── Widgets/        desktop widgets
├── shell/anime-themes.zsh   prompt, aliases, greeting, build sounds (copied to ~/.config/anime-themes)
├── sketchybar/sketchybarrc  optional menu bar
├── packs/                   all themes: settings + your assets (copied to ~/AnimeThemes)
│   ├── CHARACTERS.md, ALIASES.md, icons.json
│   └── naruto/ akatsuki/ demon-slayer/
│       ├── anime.json, aliases.zsh
│       └── <character>/ variant.json, aliases.zsh, lines.txt, logo.txt,
│                        wallpapers/, live/, voice/, sticker*.png
└── tools/                   asset scripts (sort, collect, file voices, fetch wallpapers)
```

Theme settings you can edit in `packs/<anime>/<character>/`:
- `variant.json`: colors, icon motif, prompt name, macOS accent
- `lines.txt`: one motivational line per row
- `logo.txt`: ASCII art for the greeting
- `aliases.zsh`: the character's extra aliases

Run `./install.sh` after editing so `~/AnimeThemes` gets the changes.

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| No 🍥 in the menu bar | `open ~/Applications/"Anime Themes.app"`. On a notched MacBook with many icons it can hide behind the notch; quit a few menu bar apps. |
| Voice doesn't play | Menu → Voice → **Voice on**; check that character has clips (Voice menu shows the count). |
| ⏯ buttons ask for Accessibility every time | `tccutil reset Accessibility local.animethemes.app`, then allow it again. Rebuilds keep the permission thanks to the local signing identity. |
| VS Code theme or sticker not showing | Make sure you're in a profile the app knows about (it covers all of them after a theme switch), restart VS Code, and check the **background** extension is enabled. |
| Widgets overlap or are off-screen | Desktop widgets → **Reset positions** |
| Terminal opens a window on switch | Update to the latest code; that was fixed |
| Images are tiny text files after cloning | `git lfs install && git lfs pull` |
| Build error | Run `./build.sh` and read the first `error:` line; `xcode-select --install` if the compiler is missing |

---

## 8. Uninstall

Choose **Restore original app icons** in the menu first, then:

```bash
./uninstall.sh
```

It removes the app, the shell hook and the VS Code themes. `~/AnimeThemes` (your assets) stays,
and so does this repo.
