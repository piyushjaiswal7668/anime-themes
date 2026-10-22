#!/bin/bash
# Sorts downloaded voice clips into your theme packs.
#
# 1. Make a folder per variant inside ~/Downloads/anime-voices, named like the variant's
#    folder (e.g. kakashi, minato, gaara, giyu, akaza). The full list is in ~/AnimeThemes/CHARACTERS.md.
# 2. Download clips into them (any names are fine).
# 3. Run:  ./sort-voices.sh            (or ./sort-voices.sh /path/to/folder)
#
# Language comes from the file name ("english" -> en, "hindi" -> hi, otherwise ja).
# The event comes from the file name (TitleCall -> switch, Result -> build-pass,
# DMG -> build-fail, ...). To choose yourself, put clips in a subfolder named
# switch, random, build-pass, build-fail or login (optionally inside ja/en/hi).
# Originals are copied, never moved. With ffmpeg installed, clips are also trimmed
# and evened out in volume.

set -u
SRC="${1:-$HOME/Downloads/anime-voices}"
PACKS="$HOME/AnimeThemes"

if [ ! -d "$SRC" ]; then
  echo "Folder not found: $SRC"
  echo "Create it with one subfolder per theme, e.g.: mkdir -p \"$SRC\"/{nine-tails,uchiha,madara,obito,jiraiya,tsunade,sakura,hinata,itachi,pain,konan,kisame,deidara,sasori,hidan,kakuzu,zetsu,orochimaru,tanjiro,zenitsu,rengoku,nezuko,shinobu}"
  exit 1
fi

HAVE_FFMPEG=0
command -v ffmpeg >/dev/null 2>&1 && HAVE_FFMPEG=1
[ $HAVE_FFMPEG = 0 ] && echo "(ffmpeg not found: copying clips as they are. 'brew install ffmpeg' adds trimming and volume levelling.)"

copied=0
for vdir in "$SRC"/*/; do
  [ -d "$vdir" ] || continue
  variant=$(basename "$vdir")
  target=$(ls -d "$PACKS"/*/"$variant" 2>/dev/null | head -1)
  if [ -z "$target" ]; then
    echo "Skipping '$variant': no theme with that name"
    continue
  fi

  while IFS= read -r f; do
    name=$(basename "$f")
    lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
    case "$lower" in *.mp3|*.m4a|*.wav|*.aac|*.aiff|*.aif|*.caf) ;; *) continue ;; esac

    # Language: folder name or file name
    case "$lower" in
      */en/*|*english*) lang=en ;;
      */hi/*|*hindi*)   lang=hi ;;
      *)                lang=ja ;;
    esac

    # Event: folder name wins, then codes in the file name
    case "$lower" in
      */switch/*)     event=switch ;;
      */random/*)     event=random ;;
      */build-pass/*) event=build-pass ;;
      */build-fail/*) event=build-fail ;;
      */login/*)      event=login ;;
      *titlecall*|*title-call*|*characterselect*|*character-select*|*beforebattle*|*before-battle*) event=switch ;;
      *result*|*afterbattle*|*after-battle*|*victory*) event=build-pass ;;
      *dmg*|*damage*|*-die*|*_die*|*hurt*|*defeat*) event=build-fail ;;
      *atk*|*skill*|*special*|*attack*) event=build-pass ;;
      *) event=random ;;
    esac

    dest="$target/voice/$lang/$event"
    mkdir -p "$dest"
    base="${name%.*}"
    if [ $HAVE_FFMPEG = 1 ]; then
      if ! ffmpeg -nostdin -loglevel quiet -y -i "$f" \
          -af "silenceremove=start_periods=1:start_threshold=-45dB,loudnorm" "$dest/$base.m4a"; then
        rm -f "$dest/$base.m4a"
        cp "$f" "$dest/$name"
      fi
    else
      cp "$f" "$dest/$name"
    fi
    copied=$((copied + 1))
    echo "  $variant: $name -> $lang/$event"
  done < <(find "$vdir" -type f)

  # Make sure login has something: borrow a switch clip.
  for lang in ja en hi; do
    login="$target/voice/$lang/login"
    sw="$target/voice/$lang/switch"
    mkdir -p "$login"
    if [ -z "$(ls -A "$login" 2>/dev/null)" ] && [ -n "$(ls -A "$sw" 2>/dev/null)" ]; then
      first=$(ls "$sw" | head -1)
      cp "$sw/$first" "$login/$first"
    fi
  done
done

echo
echo "Copied $copied clips. Clips per theme (ja / en / hi):"
for t in "$PACKS"/*/*/; do
  [ -f "$t/variant.json" ] || continue
  line="  $(basename "$t"):"
  for lang in ja en hi; do
    n=$(find "$t/voice/$lang" -type f 2>/dev/null | wc -l | tr -d ' ')
    line="$line $n"
  done
  echo "$line"
done
echo
echo "Missing events get a fallback: an empty language uses Japanese, then English."
echo "Pick the theme again in the 🍥 menu, then Voice → Play a test clip."
