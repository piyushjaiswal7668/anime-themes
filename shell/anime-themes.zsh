# Anime Themes — zsh hook. Installed to ~/.config/anime-themes/ and sourced from ~/.zshrc.
# The menu bar app writes ~/.config/anime-themes/active/*; this file reloads it at each prompt
# when it changes, so open terminal windows switch theme without restarting.
#
# Settings (put these in ~/.zshrc BEFORE the source line to change them):
#   ANIME_PROMPT=0    keep your own prompt
#   ANIME_GREETING=0  no logo and line when a terminal opens

[[ -o interactive ]] || return 0

typeset -g _ANIME_DIR="$HOME/.config/anime-themes/active"
typeset -g _anime_stamp=""
typeset -ga _anime_aliases=()

autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %b'
zstyle ':vcs_info:git:*' actionformats ' %b|%a'

_anime_load() {
  local stampfile="$_ANIME_DIR/stamp"
  [[ -r $stampfile ]] || return 0
  local stamp="$(<$stampfile)"
  [[ $stamp == $_anime_stamp ]] && return 0
  _anime_stamp=$stamp

  # Drop the previous theme's aliases, then load the new ones and remember their names.
  local a
  for a in $_anime_aliases; do unalias -- $a 2>/dev/null; done
  [[ -r $_ANIME_DIR/env.zsh ]] && source $_ANIME_DIR/env.zsh
  local -a before=(${(k)aliases})
  [[ -r $_ANIME_DIR/aliases.zsh ]] && source $_ANIME_DIR/aliases.zsh
  local -a after=(${(k)aliases})
  _anime_aliases=(${after:|before})

  if [[ ${ANIME_PROMPT:-1} == 1 ]]; then
    setopt prompt_subst
    PROMPT='%F{${ANIME_C_ACCENT}}${ANIME_EMOJI} ${ANIME_PROMPT_USER}%f%F{${ANIME_C_MUTED}}@${ANIME_PROMPT_HOST}%f %F{${ANIME_C_FG}}%~%f%F{${ANIME_C_ACCENT2}}${vcs_info_msg_0_}%f
%(?.%F{${ANIME_C_ACCENT}}.%F{${ANIME_C_RED}})❯%f '
    RPROMPT=''
  fi
}

_anime_vcs() { [[ ${ANIME_PROMPT:-1} == 1 ]] && vcs_info }

# Print a random motivational line from the active theme.
anime-line() {
  local file="$_ANIME_DIR/lines.txt"
  [[ -r $file ]] || return 0
  local -a lines=("${(@f)$(<$file)}")
  lines=(${lines:#})
  (( ${#lines} )) || return 0
  printf '\e[38;5;%sm  %s\e[0m\n' "${ANIME_C_ACCENT2:-7}" "${lines[RANDOM % ${#lines} + 1]}"
}

# Logo, theme name and a line. Runs when a terminal opens; type `anime-greet` to see it again.
anime-greet() {
  local logo="$_ANIME_DIR/logo.txt"
  [[ -r $logo ]] || return 0
  print
  printf '\e[38;5;%sm' "${ANIME_C_ACCENT:-7}"
  cat -- "$logo"
  printf '\e[0m\n'
  printf '\e[38;5;%sm  %s · %s\e[0m\n' "${ANIME_C_MUTED:-8}" "${ANIME_NAME}" "${ANIME_CHARACTER}"
  anime-line
  print
}

# List the current theme's aliases.
anime-aliases() {
  local a
  for a in ${(o)_anime_aliases}; do printf '  \e[38;5;%sm%-22s\e[0m %s\n' "${ANIME_C_ACCENT:-7}" "$a" "${aliases[$a]}"; done
}

# Play a random clip for an event (switch, random, build-pass, build-fail, login).
# Tries the chosen language first, then the others, so an empty Hindi folder falls back.
anime-voice() {
  [[ ${ANIME_VOICE:-0} == 1 && -n $ANIME_VOICE_ROOT ]] || return 0
  local event=${1:-random} lang
  local -a files
  for lang in ${=ANIME_VOICE_LANGS:-ja en hi}; do
    files=("$ANIME_VOICE_ROOT/$lang/$event"/*.(mp3|m4a|wav|aac|aiff|aif|caf)(N))
    (( ${#files} )) && break
  done
  # Nothing for this moment: any clip the character has, still in language order.
  if (( ! ${#files} )); then
    for lang in ${=ANIME_VOICE_LANGS:-ja en hi}; do
      files=("$ANIME_VOICE_ROOT/$lang"/*/*.(mp3|m4a|wav|aac|aiff|aif|caf)(N))
      (( ${#files} )) && break
    done
  fi
  (( ${#files} )) || return 0
  ( afplay -v "${ANIME_VOICE_VOLUME:-0.7}" "${files[RANDOM % ${#files} + 1]}" &>/dev/null & )
}

# Build/test commands that get a pass or fail clip when they finish.
# Change the list by setting ANIME_BUILD_PATTERN in ~/.zshrc (a zsh regex).
typeset -g _anime_cmd="" _anime_cmd_start=0
_anime_preexec() { _anime_cmd=$3; _anime_cmd_start=$SECONDS }
_anime_build_voice() {
  local code=$? cmd=$_anime_cmd
  _anime_cmd=""
  [[ -n $cmd ]] || return 0
  (( code == 130 )) && return 0                                  # stopped with Ctrl-C
  (( SECONDS - _anime_cmd_start >= ${ANIME_BUILD_MIN_SECONDS:-2} )) || return 0
  local pattern=${ANIME_BUILD_PATTERN:-'(^|[ /])(npm|pnpm|yarn|bun) (run )?(test|build|lint)|jest|vitest|pytest|cargo (build|test)|go (build|test)|swift (build|test)|xcodebuild|flutter (build|test)|gradlew?|mvn|make( |$)|tsc'}
  if [[ $cmd =~ $pattern ]]; then
    _anime_record_build $code "$cmd"
    if (( code == 0 )); then anime-voice build-pass; else anime-voice build-fail; fi
  fi
}

# Remember each project's last build for the Dev desktop widget:
# one line per project in state/builds.tsv (path, pass|fail, unix time, command).
_anime_record_build() {
  local code=$1 cmd=${2//$'\n'/ } root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  mkdir -p "$_ANIME_STATE" 2>/dev/null
  local file="$_ANIME_STATE/builds.tsv" result=pass
  (( code == 0 )) || result=fail
  {
    [[ -r $file ]] && awk -F'\t' -v r="$root" '$1 != r' "$file"
    print -r -- "$root"$'\t'"$result"$'\t'"$(date +%s)"$'\t'"${cmd//$'\t'/ }"
  } >| "$file.tmp" 2>/dev/null && mv -f "$file.tmp" "$file"
}

# Remember the git project you're in, for the Dev desktop widget. Runs only when the folder changes.
typeset -g _ANIME_STATE="$HOME/.config/anime-themes/state" _anime_last_pwd=""
_anime_track_repo() {
  [[ $PWD == $_anime_last_pwd ]] && return 0
  _anime_last_pwd=$PWD
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  mkdir -p "$_ANIME_STATE" 2>/dev/null
  print -r -- "$root" >| "$_ANIME_STATE/repo" 2>/dev/null
}

add-zsh-hook preexec _anime_preexec
add-zsh-hook precmd _anime_build_voice
add-zsh-hook precmd _anime_track_repo
add-zsh-hook precmd _anime_load
add-zsh-hook precmd _anime_vcs

_anime_load
[[ ${ANIME_GREETING:-1} == 1 ]] && anime-greet
