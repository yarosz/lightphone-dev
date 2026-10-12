#!/usr/bin/env bash
# Type letters and spaces on LightOS's in-app keyboard by guarded taps. That keyboard ignores
# `input text` (see lp3-drive.sh text), so each character is one `lp3-drive.sh <serial> com.lightos tap`.
#
#   lightos-type.sh <serial> "<letters and spaces>"
#
# Only A-Z, a-z and space. Case is ignored: the keyboard capitalises the first letter, then shows
# lowercase, and a tap types whatever case the layer shows. Two spaces in a row type ". " (the
# keyboard's auto-punctuation). Digits and punctuation sit on the "123" layer, which isn't mapped: they
# exit 64, naming the character, before anything is tapped. Sending the message is a separate tap.
#
# Needs LP3_ALLOW_LIGHTOS=1 set by the caller, only after the human allowed driving LightOS. The script
# runs lp3-guard.sh first (awake, unlocked, LightOS focused, the variable set) and then every tap is
# guarded again by lp3-drive.sh. The text field must already be focused with the letter layer showing.
#
# The guard only proves com.lightos has focus. LightOS draws its keyboard in-app (not an IME, so it is
# invisible to uiautomator): this script cannot detect a missing keyboard or a navigation mid-run. Take a
# screenshot first and confirm the compose keyboard (letter layer) is showing; taps on any other screen
# do whatever that screen's buttons do.
#
# Before the first tap it reads `wm size` (and `wm density` if LIGHTOS_TYPE_DENSITY is set), using the
# override value when an "Override size/density" line is present. A size other than 1080x1240 exits 3:
# the key table was measured at that size, so re-measure.
#
# Exit 3 = a guard or the screen-geometry check failed (reason on stderr). A failed tap stops the run, and its exit code is passed on.
# Exit 64 = usage or an unsupported character.
set -euo pipefail
export LC_ALL=C   # A-Z must mean ASCII only, and ${msg:i:1} must be one byte per character

usage() { sed -n '2,$p' "$0" | sed '/^[^#]/,$d; s/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 2 ] && [ -n "$2" ] || { usage >&2; exit 64; }

here=$(cd "$(dirname "$0")" && pwd)
serial="$1" msg="$2"
pkg=com.lightos

# Key centres in pixels. Measured 2026-10-11 on a real LP3 (1080 px wide), LightOS Messages compose
# screen, letter layer. Other screens or firmware may place the keys elsewhere: re-measure from a shot.
# Screen geometry at measurement time. Size is enforced; density was not recorded then, so it is only
# checked when LIGHTOS_TYPE_DENSITY (e.g. 420) is set in the environment.
table_size=1080x1240
LIGHTOS_TYPE_DENSITY="${LIGHTOS_TYPE_DENSITY:-}"
rows=(QWERTYUIOP ASDFGHJKL ZXCVBNM)
ys=(662 800 935)
xs=("72 177 280 385 488 592 695 800 903 1008" "125 228 332 437 540 644 747 852 957" "228 332 437 540 644 747 852")
space_x=540 space_y=1055

# Validate the whole string before the first tap.
for ((i = 0; i < ${#msg}; i++)); do
  ch="${msg:i:1}"
  case "$ch" in
    [A-Za-z' ']) ;;
    *) echo "unsupported character: '$ch' (position $((i + 1))): letters and spaces only" >&2; usage >&2; exit 64 ;;
  esac
done

"$here/lp3-guard.sh" "$serial" "$pkg"

# Effective value of `wm size` / `wm density`: the Override line if present, else the Physical one.
wm_value() {  # wm_value size|density
  local out
  out=$(adb -s "$serial" shell wm "$1" </dev/null 2>/dev/null | tr -d '\r') || true
  printf '%s\n' "$out" | awk -F': *' '/^Override/ {o=$2} /^Physical/ {p=$2} END {print (o != "" ? o : p)}'
}
size=$(wm_value size)
if [ "$size" != "$table_size" ]; then
  echo "screen size is '${size:-unknown}', but the key table was measured at $table_size: re-measure the keys from a screenshot" >&2
  exit 3
fi
if [ -n "$LIGHTOS_TYPE_DENSITY" ]; then
  density=$(wm_value density)
  if [ "$density" != "$LIGHTOS_TYPE_DENSITY" ]; then
    echo "screen density is '${density:-unknown}', but LIGHTOS_TYPE_DENSITY=$LIGHTOS_TYPE_DENSITY (table measured at size $table_size): re-measure the keys" >&2
    exit 3
  fi
fi

for ((i = 0; i < ${#msg}; i++)); do
  ch=$(printf '%s' "${msg:i:1}" | tr '[:lower:]' '[:upper:]')
  if [ "$ch" = " " ]; then
    x=$space_x y=$space_y
  else
    for r in 0 1 2; do
      pre="${rows[r]%%"$ch"*}"
      [ ${#pre} -lt ${#rows[r]} ] || continue
      read -r -a col <<<"${xs[r]}"
      x=${col[${#pre}]} y=${ys[r]}
      break
    done
  fi
  "$here/lp3-drive.sh" "$serial" "$pkg" tap "$x" "$y"
done
