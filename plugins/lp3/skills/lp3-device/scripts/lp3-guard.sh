#!/usr/bin/env bash
# Check that it is safe to send input to a Tool: the device is awake, not locked, and the Tool has focus.
#
#   lp3-guard.sh <serial> <pkg>                # before a tap, swipe, key or text
#   lp3-guard.sh --pre-launch <serial> <pkg>   # before launching <pkg>: LightOS may have focus
#
# Checks, in order:
#   1. `dumpsys power` mWakefulness is Awake (not Asleep, Dozing or Dreaming).
#   2. The phone is confirmed unlocked: `dumpsys window policy` prints isKeyguardShowing=false, and no
#      source says a keyguard is showing: isKeyguardShowing, KeyguardServiceDelegate showing or
#      KeyguardStateMonitor mIsShowing in `dumpsys window policy`, or KeyguardController
#      mKeyguardShowing in `dumpsys activity activities` (spaces around = allowed). Older field names
#      (mShowingLockscreen, mDreamingLockscreen, keyguardShowing) count too. Without
#      isKeyguardShowing=false (empty or unfamiliar output) it is unsafe: "can't confirm the phone is
#      unlocked". The focused window must not be a keyguard or NotificationShade. --pre-launch runs this
#      check as well: LightOS focus is fine before a launch, a locked phone isn't.
#   3. The global mCurrentFocus (the last one in `dumpsys window displays`, after any per-display ones)
#      is a window whose component is <pkg>: `u<n> <pkg>/<class>}`. A window title that merely contains
#      <pkg> doesn't count. Skipped with --pre-launch.
#
# Only live sections are read. The full `dumpsys window` starts with a saved LAST ANR section (checked
# on a real LP3, 2026-10-09), so after an ANR its stale mCurrentFocus would come first.
#
# Fields seen on a real LP3 (LightOS 582, Android 14, unlocked, 2026-10-09): mWakefulness=Awake,
# mCurrentFocus=Window{... u0 com.lightos/com.lightos.MainActivity}, isKeyguardShowing=false,
# mDreamingLockscreen=false. The locked state wasn't captured, so the keyguard fields above are what
# Android 14 prints, not yet confirmed on a locked LP3.
#
# Exit 0 = safe. Exit 3 = not safe, with the reason on stderr: stop and ask the human to wake or unlock
# the phone or bring the Tool forward. Never wake or unlock it with key events. Exit 64 = usage.
set -euo pipefail

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

prelaunch=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --pre-launch) prelaunch=1; shift ;;
esac
[ $# -eq 2 ] || { usage >&2; exit 64; }
serial="$1" pkg="$2"
[[ $pkg =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] || { echo "bad package name: $pkg" >&2; usage >&2; exit 64; }

unsafe() { echo "unsafe ($serial): $*" >&2; exit 3; }
dumpsys() { adb -s "$serial" shell dumpsys "$@" </dev/null 2>/dev/null | tr -d '\r'; }

power=$(dumpsys power) \
  || unsafe "adb can't reach the device (screen off, unplugged, or wireless debugging off)"
# Here-strings, not pipes from printf: grep -q exits early, and with pipefail a big dumpsys output
# would then fail the pipeline and skip the check.
wake=$(sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' <<<"$power" | sed -n 1p)
[ -n "$wake" ] || unsafe "no mWakefulness in dumpsys power"
[ "$wake" = Awake ] || unsafe "wakefulness is $wake, not Awake: ask the human to wake the phone"

# On a real LP3 (Android 14) isKeyguardShowing and mDreamingLockscreen print under `dumpsys window
# displays` (DISPLAY CONTENTS), and the KeyguardServiceDelegate lines under `dumpsys window policy`.
displays=$(dumpsys window displays) || unsafe "adb can't read dumpsys window displays"
policy=$(dumpsys window policy) || unsafe "adb can't read dumpsys window policy"
activities=$(dumpsys activity activities) || unsafe "adb can't read dumpsys activity activities"
locked='(isKeyguardShowing|mKeyguardShowing|mShowingLockscreen|mDreamingLockscreen|keyguardShowing|mIsShowing|(^|[^A-Za-z])showing)[[:space:]]*=[[:space:]]*true'
if grep -Eq "$locked" <<<"$displays" || grep -Eq "$locked" <<<"$policy" || grep -Eq "$locked" <<<"$activities"; then
  unsafe "the keyguard is showing: ask the human to unlock the phone"
fi
grep -Eq 'isKeyguardShowing[[:space:]]*=[[:space:]]*false' <<<"$displays" \
  || grep -Eq 'isKeyguardShowing[[:space:]]*=[[:space:]]*false' <<<"$policy" \
  || unsafe "can't confirm the phone is unlocked (no isKeyguardShowing=false in dumpsys window displays or policy): ask the human"
focus=$(sed -n 's/.*mCurrentFocus=//p' <<<"$displays" | sed -n '$p')   # the global focus is last
[ -n "$focus" ] || unsafe "no mCurrentFocus in dumpsys window displays"
case "$focus" in
  *Keyguard*|*keyguard*) unsafe "focus is a keyguard ($focus)" ;;
  *NotificationShade*) unsafe "focus is NotificationShade ($focus)" ;;
  null|*"=null"*) unsafe "nothing has focus" ;;
esac
if [ "$prelaunch" -eq 0 ]; then
  # The whole record must be Window{<hash> u<n> <pkg>/<class>}, so a window title can't mimic it.
  component="^[[:space:]]*Window\{[0-9a-f]+[[:space:]]+u[0-9]+[[:space:]]+${pkg//./\\.}/[^[:space:]}]+\}[[:space:]]*$"
  [[ $focus =~ $component ]] || unsafe "focus is not $pkg: $focus"
fi
exit 0
