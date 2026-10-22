#!/bin/bash
# Removes the app, the shell hook and the VS Code themes. Keeps ~/AnimeThemes (your downloads).
set -uo pipefail

echo "Tip: choose \"Restore original app icons\" in the 🍥 menu before uninstalling if you used themed icons."
pkill -x AnimeThemes 2>/dev/null
rm -rf "$HOME/Applications/Anime Themes.app"
rm -rf "$HOME/.config/anime-themes"
if [[ -f "$HOME/.zshrc" ]]; then
  sed -i '' -e '/# Anime Themes (prompt, aliases, greeting)/d' -e '/anime-themes\/anime-themes.zsh/d' "$HOME/.zshrc"
fi
for code in /usr/local/bin/code /opt/homebrew/bin/code "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
  [[ -x "$code" ]] && "$code" --uninstall-extension local.anime-themes >/dev/null 2>&1 && break
done
rm -rf "$HOME/.vscode/extensions/local.anime-themes-1.0.0"
rm -rf "$HOME/AnimeThemes/.generated"

echo "Removed Anime Themes. Your files in ~/AnimeThemes are still there."
echo "VS Code settings backup: ~/Library/Application Support/Code/User/settings.before-anime-themes.json"
echo "Terminal profiles named 'Anime · …' can be deleted in Terminal → Settings → Profiles."
