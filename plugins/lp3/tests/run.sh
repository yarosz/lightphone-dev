#!/usr/bin/env bash
# Run every test for the lp3 plugin's scripts. No device or emulator is touched: adb is a fake on PATH.
#
#   plugins/lp3/tests/run.sh            # all tests
#   plugins/lp3/tests/run.sh lease      # only test-lease.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
SKILLS="$(cd "$TESTS/../skills" && pwd)"
DEVICE="$SKILLS/lp3-device/scripts"
export TESTS SKILLS DEVICE

pass=0 fail=0
failed_names=()

# One temp directory per test; FAKE_ADB_STATE points into it.
new_state() {
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/lp3-test.XXXXXX")
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

# set_screen <serial> <wakefulness> <focus> [keyguard true|false]
set_screen() {
  local d="$FAKE_ADB_STATE/dev/$1"
  printf 'POWER MANAGER (dumpsys power)\n  mWakefulness=%s\r\n  mWakefulnessChanging=false\n' "$2" > "$d/power"
  printf 'WINDOW MANAGER WINDOWS (dumpsys window windows)\n  mShowingLockscreen=%s mShowingDream=false\n  mCurrentFocus=%s\r\n  mFocusedApp=null\n' \
    "${4:-false}" "$3" > "$d/window"
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
