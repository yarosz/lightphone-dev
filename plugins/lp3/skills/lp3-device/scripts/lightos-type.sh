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
# Exit 3 = a guard failed (reason on stderr). A failed tap stops the run, and its exit code is passed on.
# Exit 64 = usage or an unsupported character.
set -euo pipefail
export LC_ALL=C   # A-Z must mean ASCII only, and ${msg:i:1} must be one byte per character

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 2 ] && [ -n "$2" ] || { usage >&2; exit 64; }

here=$(cd "$(dirname "$0")" && pwd)
serial="$1" msg="$2"
pkg=com.lightos

# Key centres in pixels. Measured 2026-10-11 on a real LP3 (1080 px wide), LightOS Messages compose
# screen, letter layer. Other screens or firmware may place the keys elsewhere: re-measure from a shot.
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
