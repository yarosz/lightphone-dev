#!/usr/bin/env bash
# Check that it is safe to send input to a Tool: the device is awake, not locked, and the Tool has focus.
#
#   lp3-guard.sh <serial> <pkg>                # before a tap, swipe, key or text
#   lp3-guard.sh --pre-launch <serial> <pkg>   # before launching <pkg>: LightOS may have focus
#
# Checks, in order:
#   1. `dumpsys power` mWakefulness is Awake (not Asleep, Dozing or Dreaming).
#   2. No keyguard is showing (`dumpsys window`), and the focused window isn't a keyguard or
#      NotificationShade.
#   3. `dumpsys window` mCurrentFocus names <pkg>. Skipped with --pre-launch.
#
# Exit 0 = safe. Exit 3 = not safe, with the reason on stderr: stop and ask the human to wake or unlock
# the phone or bring the Tool forward. Never wake or unlock it with key events. Exit 64 = usage.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

prelaunch=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --pre-launch) prelaunch=1; shift ;;
esac
[ $# -eq 2 ] || { usage >&2; exit 64; }
serial="$1" pkg="$2"

unsafe() { echo "unsafe ($serial): $*" >&2; exit 3; }

power=$(adb -s "$serial" shell dumpsys power </dev/null 2>/dev/null | tr -d '\r') \
  || unsafe "adb can't reach the device (screen off, unplugged, or wireless debugging off)"
# Here-strings, not pipes from printf: grep -q exits early, and with pipefail a big dumpsys output
# would then fail the pipeline and skip the check.
wake=$(sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' <<<"$power" | sed -n 1p)
[ -n "$wake" ] || unsafe "no mWakefulness in dumpsys power"
[ "$wake" = Awake ] || unsafe "wakefulness is $wake, not Awake: ask the human to wake the phone"

window=$(adb -s "$serial" shell dumpsys window </dev/null 2>/dev/null | tr -d '\r') \
  || unsafe "adb can't read dumpsys window"
if grep -Eq '(mShowingLockscreen|mDreamingLockscreen|mKeyguardShowing|isKeyguardShowing|keyguardShowing)=true' <<<"$window"; then
  unsafe "the keyguard is showing: ask the human to unlock the phone"
fi
focus=$(sed -n 's/.*mCurrentFocus=//p' <<<"$window" | sed -n 1p)
[ -n "$focus" ] || unsafe "no mCurrentFocus in dumpsys window"
case "$focus" in
  *Keyguard*|*keyguard*) unsafe "focus is a keyguard ($focus)" ;;
  *NotificationShade*) unsafe "focus is NotificationShade ($focus)" ;;
  null|*"=null"*) unsafe "nothing has focus" ;;
esac
if [ "$prelaunch" -eq 0 ]; then
  case "$focus" in
    *" $pkg/"*) ;;
    *) unsafe "focus is not $pkg: $focus" ;;
  esac
fi
exit 0
