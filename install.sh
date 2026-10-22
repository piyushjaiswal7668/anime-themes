#!/bin/bash
# Anime Themes installer. Safe to run again: it updates the app and theme packs
# and never deletes wallpapers, videos or voice clips you added.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

WITH_SKETCHYBAR=0
for arg in "$@"; do
  case "$arg" in
    --with-sketchybar) WITH_SKETCHYBAR=1 ;;
    *) echo "Unknown option: $arg (the only option is --with-sketchybar)"; exit 1 ;;
  esac
done

echo "==> Anime Themes installer"

if [[ "$(uname)" != "Darwin" ]]; then echo "This only runs on macOS."; exit 1; fi
ver="$(sw_vers -productVersion)"
if (( ${ver%%.*} < 15 )); then echo "macOS 15 or newer is needed (this Mac has $ver)."; exit 1; fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's command line tools are needed to build the app. A window will open to install them."
  echo "When that finishes, run ./install.sh again."
  xcode-select --install || true
  exit 1
fi

# 1. Theme packs -> ~/AnimeThemes
PACKS="$HOME/AnimeThemes"
mkdir -p "$PACKS"
# Itachi moved from naruto/akatsuki to the Akatsuki group; bring your downloads along.
if [[ -d "$PACKS/naruto/akatsuki" && ! -d "$PACKS/akatsuki/itachi" ]]; then
  mkdir -p "$PACKS/akatsuki"
  mv "$PACKS/naruto/akatsuki" "$PACKS/akatsuki/itachi"
  echo "==> Moved Itachi (and your files) to the new Akatsuki group"
fi
rsync -a --update "$ROOT/packs/" "$PACKS/"
for vdir in "$PACKS"/*/*/; do
  [[ -f "$vdir/variant.json" ]] || continue
  mkdir -p "$vdir/wallpapers" "$vdir/live" "$vdir/icons"
  for lang in ja en hi; do
    for ev in switch random build-pass build-fail login; do mkdir -p "$vdir/voice/$lang/$ev"; done
  done
done
cp "$ROOT/packs/README.md" "$PACKS/README.md" 2>/dev/null || true
echo "==> Theme packs ready in $PACKS"

# 2. Shell hook
CFG="$HOME/.config/anime-themes"
mkdir -p "$CFG/active"
cp "$ROOT/shell/anime-themes.zsh" "$CFG/anime-themes.zsh"
touch "$HOME/.zshrc"
if ! grep -qF 'anime-themes/anime-themes.zsh' "$HOME/.zshrc"; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.before-anime-themes"
  printf '\n# Anime Themes (prompt, aliases, greeting)\n[[ -r ~/.config/anime-themes/anime-themes.zsh ]] && source ~/.config/anime-themes/anime-themes.zsh\n' >> "$HOME/.zshrc"
  echo "==> Added one line to ~/.zshrc (backup: ~/.zshrc.before-anime-themes)"
fi

# 3. Maple Mono font
if ls "$HOME/Library/Fonts"/MapleMono* >/dev/null 2>&1 || ls /Library/Fonts/MapleMono* >/dev/null 2>&1; then
  echo "==> Maple Mono already installed"
elif command -v brew >/dev/null 2>&1; then
  echo "==> Installing Maple Mono"
  brew install --cask font-maple-mono || echo "   Couldn't install it with Homebrew. Download it from https://github.com/subframe7536/maple-font/releases"
else
  echo "==> Install Maple Mono from https://github.com/subframe7536/maple-font/releases (Homebrew wasn't found)"
fi

# 4. Optional SketchyBar menu bar
if (( WITH_SKETCHYBAR )); then
  if ! command -v brew >/dev/null 2>&1; then
    echo "==> Skipping SketchyBar: it installs with Homebrew (https://brew.sh), which wasn't found."
  else
    echo "==> Installing SketchyBar"
    brew tap FelixKratz/formulae >/dev/null
    brew install sketchybar
    SB="$HOME/.config/sketchybar"
    mkdir -p "$SB"
    if [[ -f "$SB/sketchybarrc" ]] && ! grep -q "Anime Themes" "$SB/sketchybarrc"; then
      mv "$SB/sketchybarrc" "$SB/sketchybarrc.before-anime-themes"
      echo "   Your old SketchyBar config was saved as sketchybarrc.before-anime-themes"
    fi
    cp "$ROOT/sketchybar/sketchybarrc" "$SB/sketchybarrc"
    chmod +x "$SB/sketchybarrc"
    brew services restart sketchybar >/dev/null
    echo "   To see it, hide the macOS menu bar: System Settings → Control Center → Automatically hide and show the menu bar → Always"
  fi
fi

# 5. App
"$ROOT/build.sh"
open "$HOME/Applications/Anime Themes.app"

cat <<'EOF'

All set. Click the 🍥 in the menu bar and pick a theme.
The first time, macOS asks whether Anime Themes may control Terminal: click OK.
Then open a new Terminal window to see the greeting.
EOF
