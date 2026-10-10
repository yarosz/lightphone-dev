#!/usr/bin/env bash
# Run every test for the lp3 plugin's scripts. No device or emulator is touched: adb is a fake on PATH.
#
#   tests/run.sh            # all tests (paths relative to the plugin)
#   tests/run.sh lease      # only test-lease.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
SKILLS="$(cd "$TESTS/../skills" && pwd)"
DEVICE="$SKILLS/lp3-device/scripts"
export TESTS SKILLS DEVICE

pass=0 fail=0
failed_names=()

# Every temp directory lives under one lp3-test.* directory per run, removed on exit. Its pid file lets a
# later run remove what a killed run left behind; an older layout (an adb/ directory, no pid file) is
# removed once it is an hour old.
tmp_root="${TMPDIR:-/tmp}"; tmp_root="${tmp_root%/}"
for d in "$tmp_root"/lp3-test.*; do
  [ -d "$d" ] || continue
  if [ -f "$d/pid" ]; then
    kill -0 "$(cat "$d/pid")" 2>/dev/null || rm -rf "$d"
  elif [ -d "$d/adb" ] && [ -n "$(find "$d" -maxdepth 0 -mmin +60)" ]; then
    rm -rf "$d"
  fi
done
RUN_DIR=$(mktemp -d "$tmp_root/lp3-test.XXXXXX")
echo $$ > "$RUN_DIR/pid"
trap 'rm -rf "$RUN_DIR"' EXIT

# One temp directory per test; FAKE_ADB_STATE points into it.
new_state() {
  WORK=$(mktemp -d "$RUN_DIR/t.XXXXXX")
  export FAKE_ADB_STATE="$WORK/adb"
  mkdir -p "$FAKE_ADB_STATE/dev"
  : > "$FAKE_ADB_STATE/log"
  printf 'List of devices attached\n' > "$FAKE_ADB_STATE/devices"
}

# add_device <serial> [model] [serialno]
add_device() {
  local d="$FAKE_ADB_STATE/dev/$1"
  mkdir -p "$d/settings"
  printf '%s\tdevice\n' "$1" >> "$FAKE_ADB_STATE/devices"
  [ -z "${2:-}" ] || printf '%s\n' "$2" > "$d/model"
  [ -z "${3:-}" ] || printf '%s\n' "$3" > "$d/serialno"
}

# set_screen <serial> <wakefulness> <focus> [window keyguard true|false] [activity keyguard true|false]
# The window and power lines follow `dumpsys` output read from a real LP3 (LightOS 582, Android 14,
# unlocked), which prints isKeyguardShowing=false: every unlocked fixture carries it, because the guard
# needs that positive evidence. On the real LP3, isKeyguardShowing and mDreamingLockscreen print under
# `dumpsys window displays`; the KeyguardServiceDelegate lines under `dumpsys window policy`. The locked
# state wasn't captured; it flips isKeyguardShowing, or KeyguardController's mKeyguardShowing in `dumpsys
# activity activities`. The fake adb serves
# window.policy for `dumpsys window policy`, window.displays for `dumpsys window displays`, and
# window.lastanr (if any), then policy, then displays for the full `dumpsys window`, the order a real
# LP3 prints them in.
set_screen() {
  local d="$FAKE_ADB_STATE/dev/$1"
  printf 'POWER MANAGER (dumpsys power)\n  mWakefulness=%s\r\n  mWakefulnessChanging=false\n' "$2" > "$d/power"
  {
    printf 'WINDOW MANAGER POLICY STATE (dumpsys window policy)\n'
    printf '    mKeyguardOccluded=false mKeyguardOccludedChanged=false mPendingKeyguardOccluded=false\n'
    printf '    mAllowLockscreenWhenOnDisplays=false mLockScreenTimeout=60000 mLockScreenTimerActive=false\n'
    printf '    KeyguardServiceDelegate\n      showing=false\n      deviceHasKeyguard=true\n      KeyguardStateMonitor\n'
    printf '        mIsShowing=false\n'
  } > "$d/window.policy"
  {
    printf 'WINDOW MANAGER DISPLAY CONTENTS (dumpsys window displays)\n'
    printf '  Display: mDisplayId=0 rotation=0\n'
    printf '  mCurrentFocus=%s\r\n' "$3"
    printf '    mKeyguardDrawComplete=true mWindowManagerDrawComplete=true\n'
    printf '    mShowingDream=false mDreamingLockscreen=false\n'
    printf '    isKeyguardShowing=%s\n' "${4:-false}"
  } > "$d/window.displays"
  printf 'ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)\n  KeyguardController:\n    mKeyguardShowing=%s\n    mAodShowing=false\n' \
    "${5:-false}" > "$d/activity"
}

# set_last_anr <serial> <focus>: a saved LAST ANR section, printed before the live ones
set_last_anr() {
  printf 'WINDOW MANAGER LAST ANR (dumpsys window lastanr)\n  ANR time: 2026-10-09 12:00:00\n  mCurrentFocus=%s\n  isKeyguardShowing=false\n' \
    "$2" > "$FAKE_ADB_STATE/dev/$1/window.lastanr"
}

focus_of() { echo "Window{1a2b3c u0 $1/$1.MainActivity}"; }

check() {  # check <description> <command...>: passes when the command exits 0
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); failed_names+=("$CURRENT: $name"); echo "  FAIL: $name" >&2; fi
}
expect_exit() {  # expect_exit <code> <description> <command...>
  local want="$1" name="$2" got; shift 2
  "$@" >"$WORK/out" 2>"$WORK/err"; got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); failed_names+=("$CURRENT: $name (exit $got, want $want)")
    echo "  FAIL: $name (exit $got, want $want)" >&2; sed 's/^/    /' "$WORK/err" >&2
  fi
}
out_has() { grep -q -- "$1" "$WORK/out"; }
err_has() { grep -q -- "$1" "$WORK/err"; }
log_has() { grep -q -- "$1" "$FAKE_ADB_STATE/log"; }
log_lacks() { ! grep -q -- "$1" "$FAKE_ADB_STATE/log"; }
# Every adb call except `adb devices` must name its device with -s.
all_calls_addressed() { ! grep -v -e '^adb -s ' -e '^adb devices' "$FAKE_ADB_STATE/log" | grep -q .; }

export PATH="$TESTS/fake-adb:$PATH"
export LP3_FIND_POLL=1 LP3_FOCUS_WAIT=2 LP3_OFFLINE=1

for f in "$TESTS"/test-*.sh; do
  CURRENT=$(basename "$f" .sh)
  [ $# -eq 0 ] || [ "test-$1" = "$CURRENT" ] || continue
  echo "== $CURRENT"
  # shellcheck source=/dev/null
  . "$f"
done

echo
echo "passed: $pass  failed: $fail"
for n in "${failed_names[@]+"${failed_names[@]}"}"; do echo "  $n"; done
[ "$fail" -eq 0 ]
