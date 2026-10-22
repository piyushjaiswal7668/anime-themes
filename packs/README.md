# Your theme packs

Each anime has a folder, and each variant (color palette) has a folder inside it:

```
naruto/        nine-tails · uchiha · madara · obito · jiraiya · tsunade · sakura · hinata
akatsuki/      itachi · pain · konan · kisame · deidara · sasori · hidan · kakuzu · zetsu · orochimaru
demon-slayer/  tanjiro · zenitsu · rengoku · nezuko · shinobu
```

## Where to put your downloads

Inside a variant folder, for example `demon-slayer/zenitsu/`:

| Folder | What goes in it |
|---|---|
| `wallpapers/` | Still images (.jpg, .png, .heic). A random one is used each time; "Next wallpaper" in the menu picks another. Until you add some, the app uses a gradient in the palette's colors. |
| `live/` | Looping .mp4 / .mov videos, played behind the desktop icons. |
| `voice/ja/`, `voice/en/`, `voice/hi/` | Voice clips by language. Inside each: `switch/`, `random/`, `build-pass/`, `build-fail/`, `login/`. If the chosen language is empty, Japanese and then English are used. |
| `icons/` | Optional: your own app icon as `<App Name>.png`, used instead of the generated one. |
| `sticker.png` | Optional character image (transparent PNG) shown in the bottom-right of VS Code. Needs the free "background" extension by shalldie. |

## Files you can edit

- `variant.json`: colors, icon motif (`swirl`, `cloud`, `fan`, `checks`, `bolt`, `flame`, `bamboo`, `butterfly`, `ripples`, `scroll`, `diamond`, `blossom`, `crescent`, `wave`, `burst`, `strings`, `triangle`, `stitch`, `leaf`, `snake`), prompt name (`promptUser@promptHost`), macOS accent (`red`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `graphite`).
- `lines.txt`: one motivational line per row.
- `logo.txt`: ASCII art for the terminal greeting.
- `aliases.zsh`: extra aliases for this variant. Shared ones live in the anime folder's `aliases.zsh`.

After editing, pick the theme again in the menu (or use "Re-apply theme").

## Adding a new anime

Copy a whole anime folder, rename it, and change the `id` and `name` in `anime.json` and each `variant.json`. Then choose "Reload theme packs" in the menu.

## App icons

`icons.json` (in this folder) lists which apps get themed icons, by bundle ID, with the SF Symbol drawn on each. Find an app's bundle ID with:

```bash
osascript -e 'id of app "Slack"'
```
