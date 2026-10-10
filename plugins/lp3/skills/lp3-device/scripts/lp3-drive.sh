#!/usr/bin/env bash
# Drive one Tool on an LP3 or LightOS emulator, running lp3-guard.sh before every input.
#
#   lp3-drive.sh <serial> <pkg> launch <activity>        # e.g. .MainActivity or <pkg>/.MainActivity
#   lp3-drive.sh <serial> <pkg> tap <x> <y>
#   lp3-drive.sh <serial> <pkg> swipe <x1> <y1> <x2> <y2> [ms]
#   lp3-drive.sh <serial> <pkg> key <keycode>            # number or KEYCODE_* name
#   lp3-drive.sh <serial> <pkg> text <string>
#   lp3-drive.sh <serial> <pkg> shot <file.png>          # screenshot, no guard
#   lp3-drive.sh <serial> <pkg> stop                     # force-stop <pkg> only, no guard
#
# launch checks the phone is awake and unlocked first, then waits up to LP3_FOCUS_WAIT seconds
# (default 10) for <pkg> to take focus. The other input verbs need <pkg> focused before they run.
# key refuses POWER, SLEEP and WAKEUP: POWER sleeps the LP3 and drops adb, and waking or unlocking is
# the human's job. Exit 3 = a guard failed (reason on stderr); stop and ask the human. Exit 64 = usage.
set -euo pipefail

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 64; }

here=$(cd "$(dirname "$0")" && pwd)
serial="$1" pkg="$2" verb="$3"; shift 3
num='^[0-9]+$'

guard() { "$here/lp3-guard.sh" "$@" "$serial" "$pkg"; }
sh_quote() { printf '%q' "$1"; }   # adb shell joins arguments into one remote command line

case "$verb" in
  launch)
    [ $# -eq 1 ] || { usage >&2; exit 64; }
    component="$1"; case "$component" in */*) ;; *) component="$pkg/$1" ;; esac
    guard --pre-launch
    adb -s "$serial" shell am start -W -n "$component" </dev/null >/dev/null
    deadline=$(( $(date +%s) + ${LP3_FOCUS_WAIT:-10} ))
    until guard 2>/dev/null; do
      if [ "$(date +%s)" -ge "$deadline" ]; then guard; fi   # prints the reason and exits 3
      sleep 1
    done
    ;;
  tap)
    [ $# -eq 2 ] && [[ $1 =~ $num && $2 =~ $num ]] || { usage >&2; exit 64; }
    guard; adb -s "$serial" shell input tap "$1" "$2" </dev/null
    ;;
  swipe)
    { [ $# -eq 4 ] || [ $# -eq 5 ]; } || { usage >&2; exit 64; }
    for a in "$@"; do [[ $a =~ $num ]] || { usage >&2; exit 64; }; done
    guard; adb -s "$serial" shell input swipe "$@" </dev/null
    ;;
  key)
    [ $# -eq 1 ] || { usage >&2; exit 64; }
    case "$1" in
      26|223|224|KEYCODE_POWER|KEYCODE_SLEEP|KEYCODE_WAKEUP|POWER|SLEEP|WAKEUP)
        echo "refused: $1 sleeps or wakes the phone. Ask the human to wake or unlock it." >&2; exit 3 ;;
    esac
    [[ $1 =~ $num || $1 =~ ^KEYCODE_[A-Z0-9_]+$ ]] || { usage >&2; exit 64; }
    guard; adb -s "$serial" shell input keyevent "$1" </dev/null
    ;;
  text)
    [ $# -eq 1 ] || { usage >&2; exit 64; }
    guard; adb -s "$serial" shell input text "$(sh_quote "${1// /%s}")" </dev/null
    ;;
  shot)
    [ $# -eq 1 ] || { usage >&2; exit 64; }
    adb -s "$serial" exec-out screencap -p </dev/null > "$1"
    echo "saved $1. Look at it for personal data (numbers, names, places) before sharing it." >&2
    ;;
  stop)
    [ $# -eq 0 ] || { usage >&2; exit 64; }
    adb -s "$serial" shell am force-stop "$pkg" </dev/null
    ;;
  *) usage >&2; exit 64 ;;
esac
