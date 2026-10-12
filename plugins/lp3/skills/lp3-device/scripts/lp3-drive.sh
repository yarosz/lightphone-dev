#!/usr/bin/env bash
# Drive one Tool on an LP3 or LightOS emulator, running lp3-guard.sh before every input.
#
#   lp3-drive.sh <serial> <pkg> launch <activity>        # .MainActivity, MainActivity or <pkg>/.MainActivity
#   lp3-drive.sh <serial> <pkg> tap <x> <y>
#   lp3-drive.sh <serial> <pkg> swipe <x1> <y1> <x2> <y2> [ms]
#   lp3-drive.sh <serial> <pkg> key <keycode>            # number or KEYCODE_* name
#   lp3-drive.sh <serial> <pkg> text <string>
#   lp3-drive.sh <serial> <pkg> shot <file.png>          # screenshot, no guard
#   lp3-drive.sh <serial> <pkg> stop                     # force-stop <pkg> only, no guard
#   lp3-drive.sh <serial> <pkg> wake                     # wake and unlock (no PIN) if asleep or locked
#
# launch checks the phone is awake and unlocked first, then waits up to LP3_FOCUS_WAIT seconds
# (0-9999, default 10) for <pkg> to take focus. The other input verbs need <pkg> focused before they run.
# wake does nothing if `lp3-guard.sh --pre-launch` already passes. Otherwise it sends KEYCODE_WAKEUP and
# `wm dismiss-keyguard`, then waits up to LP3_WAKE_WAIT seconds (0-9999, default 5) for that guard to
# pass. A PIN or pattern keeps the phone locked: exit 3, and ask the human.
# key refuses POWER (26), ENDCALL (6), TV_POWER (177), SLEEP (223), WAKEUP (224) and SOFT_SLEEP (276)
# in every spelling (number, with or without leading zeros, KEYCODE_ name or bare name): these can sleep
# the LP3 (ENDCALL does when no call is up) and drop adb. Wake the phone with `wake` instead.
# <pkg> may be com.lightos to drive LightOS itself (only when the human has allowed it): the input verbs
# then need LightOS focused. stop refuses com.lightos, since force-stopping it kills the home screen.
#
# Exit 3 = a guard failed, a key was refused, or wake couldn't unlock (reason on stderr); stop and ask
# the human. Exit 64 = usage.
set -euo pipefail

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 64; }

here=$(cd "$(dirname "$0")" && pwd)
serial="$1" pkg="$2" verb="$3"; shift 3
[[ $pkg =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] || { echo "bad package name: $pkg" >&2; usage >&2; exit 64; }
num='^[0-9]+$'

guard() { "$here/lp3-guard.sh" "$@" "$serial" "$pkg"; }
sh_quote() { printf '%q' "$1"; }   # adb shell joins arguments into one remote command line

case "$verb" in
  launch)
    [ $# -eq 1 ] || { usage >&2; exit 64; }
    # A number before it reaches $(( )), where a[$(...)] would run a command.
    wait_s="${LP3_FOCUS_WAIT:-10}"
    [[ $wait_s =~ ^[0-9]{1,4}$ ]] || { echo "LP3_FOCUS_WAIT must be 0-9999 seconds" >&2; usage >&2; exit 64; }
    # .Cls, Cls (gets a leading dot) or <pkg>/<cls>, where the part before / must be <pkg>.
    cls="$1"
    case "$cls" in
      */*) [ "${cls%%/*}" = "$pkg" ] || { echo "launch: $1 is not in $pkg" >&2; exit 64; }; cls="${cls#*/}" ;;
    esac
    cls_re='^\.?[A-Za-z_][A-Za-z0-9_.$]*$'   # in a variable: written inline, \$ admitted a backslash
    [[ $cls =~ $cls_re ]] ||{ echo "launch: bad class name: $1" >&2; usage >&2; exit 64; }
    case "$cls" in .*|*.*) ;; *) cls=".$cls" ;; esac
    guard --pre-launch
    adb -s "$serial" shell am start -W -n "$(sh_quote "$pkg/$cls")" </dev/null >/dev/null
    deadline=$(( $(date +%s) + 10#$wait_s ))
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
    keycode="$1"
    # Strip KEYCODE_, then normalise numbers (0026 is 26), so no spelling slips past the refusal
    # below: Android's `input keyevent` also strips KEYCODE_ and then parses a number, so
    # KEYCODE_0026 would reach POWER.
    bare="${keycode#KEYCODE_}"
    case "$bare" in KEYCODE_*) echo "key: $1 has KEYCODE_ twice" >&2; usage >&2; exit 64 ;; esac
    if [[ $bare =~ ^0*([0-9]{1,6})$ ]]; then keycode=$((10#${BASH_REMATCH[1]}))
    elif [[ $bare =~ $num ]]; then usage >&2; exit 64; fi
    case "${keycode#KEYCODE_}" in
      6|26|177|223|224|276|ENDCALL|POWER|TV_POWER|SLEEP|WAKEUP|SOFT_SLEEP)
        echo "refused: $1 sleeps or wakes the phone. To wake or unlock it, run: $0 $serial $pkg wake" >&2; exit 3 ;;
    esac
    [[ $keycode =~ $num || $keycode =~ ^KEYCODE_[A-Z0-9_]+$ ]] || { usage >&2; exit 64; }
    guard; adb -s "$serial" shell input keyevent "$keycode" </dev/null
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
    [ "$pkg" != com.lightos ] || { echo "refused: stop would force-stop LightOS itself" >&2; exit 3; }
    adb -s "$serial" shell am force-stop "$pkg" </dev/null
    ;;
  wake)
    [ $# -eq 0 ] || { usage >&2; exit 64; }
    wait_s="${LP3_WAKE_WAIT:-5}"
    [[ $wait_s =~ ^[0-9]{1,4}$ ]] || { echo "LP3_WAKE_WAIT must be 0-9999 seconds" >&2; usage >&2; exit 64; }
    guard --pre-launch 2>/dev/null && exit 0   # already awake and unlocked: send no keys
    ask="Ask the human to wake or unlock the phone."
    adb -s "$serial" shell input keyevent KEYCODE_WAKEUP </dev/null >/dev/null \
      || { echo "wake: adb can't reach $serial. $ask" >&2; exit 3; }
    adb -s "$serial" shell wm dismiss-keyguard </dev/null >/dev/null \
      || { echo "wake: adb can't reach $serial. $ask" >&2; exit 3; }
    deadline=$(( $(date +%s) + 10#$wait_s ))
    until guard --pre-launch 2>/dev/null; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        reason=$(guard --pre-launch 2>&1 >/dev/null) || true
        reason="${reason%%: run lp3-drive.sh*}"   # the guard's "run wake" hint; wake already ran
        echo "wake: still not awake and unlocked after ${wait_s}s (a PIN or pattern, or another window has focus): ${reason:-unknown}" >&2
        echo "wake: $ask" >&2
        exit 3
      fi
      sleep 1
      # The first dismiss can land before the screen is fully awake; repeating it is harmless.
      adb -s "$serial" shell wm dismiss-keyguard </dev/null >/dev/null 2>&1 || true
    done
    ;;
  *) usage >&2; exit 64 ;;
esac
