#!/bin/bash
# Install OmaAmp as an application: a launcher tile, a command on PATH, and
# Hyprland rules that let the window keep Winamp's own chrome.
#
# The player runs as its own process rather than inside omarchy-shell, so this
# is an app install, not just a plugin drop. Re-running it is safe.
#
#   ./install.sh            install
#   ./install.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
HYPR="$HOME/.config/hypr/hyprland.lua"
MARK_BEGIN="-- >>> OmaAmp"
MARK_END="-- <<< OmaAmp"

# A path is only ever replaced or removed when it is provably ours; anything
# else is the user's work and gets moved to a timestamped .bak instead of
# being overwritten, and is left strictly alone on uninstall.
is_ours() {
  local path="$1" kind="$2"
  [[ -e $path || -L $path ]] || return 1
  case "$kind" in
    bin-link)   [[ -L $path && "$(readlink -f "$path")" == "$ROOT/bin/omaamp" ]] ;;
    theme-link) [[ -L $path && "$(readlink "$path")" == *"/omarchy/current/theme/cliamp.toml" ]] ;;
    desktop)    grep -q "omaamp" "$path" 2>/dev/null ;;
    marked)     grep -q "OmaAmp" "$path" 2>/dev/null ;;
  esac
}

place() {
  # place <kind> <dst> <install-command...>
  local kind="$1" dst="$2"; shift 2
  if [[ -e $dst || -L $dst ]] && ! is_ours "$dst" "$kind"; then
    local bak="$dst.bak.$(date +%s)"
    mv "$dst" "$bak"
    echo "kept your existing $(basename "$dst") as $bak"
  fi
  "$@"
}

remove_ours() {
  local kind="$1" dst="$2"
  if is_ours "$dst" "$kind"; then
    rm -f "$dst"
  elif [[ -e $dst || -L $dst ]]; then
    echo "left $dst in place (not installed by OmaAmp)"
  fi
}

uninstall() {
  remove_ours bin-link "$BIN/omaamp"
  remove_ours desktop "$APPS/omaamp.desktop"
  remove_ours marked "$HOME/.config/omarchy/themed/cliamp.toml.tpl"
  remove_ours theme-link "$HOME/.config/cliamp/themes/omarchy.toml"
  remove_ours marked "$HOME/.config/omarchy/hooks/theme-set.d/50-omaamp-cliamp"
  if [[ -f $HYPR ]] && grep -qF -- "$MARK_BEGIN" "$HYPR"; then
    cp "$HYPR" "$HYPR.bak.$(date +%s)"
    sed -i "/${MARK_BEGIN}/,/${MARK_END}/d" "$HYPR"
    echo "removed Hyprland rules (backup alongside $HYPR)"
  fi
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
  echo "OmaAmp uninstalled. Skins and themes were left in place."
  exit 0
}

[[ ${1:-} == --uninstall ]] && uninstall

mkdir -p "$BIN" "$APPS"

# --- command on PATH ------------------------------------------------------
place bin-link "$BIN/omaamp" ln -sf "$ROOT/bin/omaamp" "$BIN/omaamp"
echo "installed $BIN/omaamp"

# --- launcher tile --------------------------------------------------------
place desktop "$APPS/omaamp.desktop" true
cat >"$APPS/omaamp.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=OmaAmp
GenericName=Media Player
Comment=Winamp skins for whatever is playing
Exec=$ROOT/bin/omaamp
Icon=multimedia-audio-player
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=winamp;skin;music;mpris;
StartupNotify=true
EOF
echo "installed $APPS/omaamp.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true

# --- cliamp follows the Omarchy theme --------------------------------------
# cliamp is the one app in the Omarchy base set with no entry in the themed/
# template engine, so it is the only one that ignores theme switches. The
# template renders into the current-theme state dir on every switch; the
# symlink makes it selectable inside cliamp as "omarchy"; the hook re-applies
# it so a running player recolors without a restart.
mkdir -p "$HOME/.config/omarchy/themed" "$HOME/.config/cliamp/themes"          "$HOME/.config/omarchy/hooks/theme-set.d"
place marked "$HOME/.config/omarchy/themed/cliamp.toml.tpl" \
  cp "$ROOT/assets/cliamp.toml.tpl" "$HOME/.config/omarchy/themed/cliamp.toml.tpl"
place theme-link "$HOME/.config/cliamp/themes/omarchy.toml" \
  ln -sf "$HOME/.local/state/omarchy/current/theme/cliamp.toml" "$HOME/.config/cliamp/themes/omarchy.toml"
place marked "$HOME/.config/omarchy/hooks/theme-set.d/50-omaamp-cliamp" \
  cp "$ROOT/assets/cliamp-theme-set-hook" "$HOME/.config/omarchy/hooks/theme-set.d/50-omaamp-cliamp"
echo "installed cliamp theme template + theme-set hook"

# --- Hyprland rules -------------------------------------------------------
# Quickshell's appId is read-only, so every instance is class org.quickshell.
# The title is ours, so rules match on class *and* title -- the same approach
# Omarchy uses for its own Quickshell windows.
if [[ -f $HYPR ]]; then
  block="$(cat <<EOF

$MARK_BEGIN — no forced float: OmaAmp opens as its own tile like any app,
-- so it never hovers over other windows uninvited. Toggle floating with the
-- usual binding when you want it parked on top; the skin scales to its tile
-- in whole-pixel steps either way. No rounding (Winamp corners are square)
-- and no border: the letterbox is transparent, so a border would outline an
-- invisible rectangle instead of the skin.
o.window({ class = "^org.quickshell\$", title = "^OmaAmp.*\$" }, { rounding = 0 })
o.window({ class = "^org.quickshell\$", title = "^OmaAmp.*\$" }, { border_size = 0 })
$MARK_END
EOF
)"
  # Rebuild the file with the current block, then touch the real config only
  # when it actually changed -- reinstalls stop minting hyprland.lua.bak
  # copies of an identical file.
  next="$(sed "/${MARK_BEGIN}/,/${MARK_END}/d" "$HYPR")"
  # Strip the blank line the block carries so repeated runs stay stable.
  next="${next%$'\n'}$block"
  if [[ "$next" == "$(cat "$HYPR")" ]]; then
    echo "Hyprland rules already current"
  else
    cp "$HYPR" "$HYPR.bak.$(date +%s)"
    printf '%s\n' "$next" >"$HYPR"
    echo "refreshed Hyprland rules in $HYPR (backup alongside it)"
  fi
else
  echo "note: $HYPR not found — add the float rule yourself if you want it undecorated" >&2
fi

if command -v hyprctl >/dev/null; then
  hyprctl reload >/dev/null 2>&1 || true
  errors="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -n $errors && $errors != *"no errors"* ]]; then
    echo "WARNING: Hyprland reported config errors:" >&2
    echo "$errors" >&2
  fi
fi

cat <<'EOF'

OmaAmp installed. Pick a skin from the Winamp Skins bar widget, or:

    omaamp --skin <md5>     wear a specific museum skin
    omaamp --zoom 3         bigger pixels
    omaamp --quit

EOF
