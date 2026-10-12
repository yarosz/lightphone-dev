# shellcheck shell=bash disable=SC2016  # literal $ and backticks are the point here
# Tests for lightos-type.sh. Sourced by run.sh.
T="$DEVICE/lightos-type.sh"
OS=com.lightos
S=SER-ONE
taps() { grep -o 'input tap [0-9]* [0-9]*' "$FAKE_ADB_STATE/log" | sed 's/input tap //' | paste -sd, -; }
taps_are() { [ "$(taps)" = "$1" ]; }

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $OS)"

export LP3_ALLOW_LIGHTOS=1
expect_exit 0 "type: -h" "$T" -h
check "type: -h omits set -euo" test -z "$(grep 'set -euo' "$WORK/out")"
check "type: -h ends with the exit codes" grep -q 'Exit 64' "$WORK/out"
check "type: -h prints usage" out_has "lightos-type.sh <serial>"
expect_exit 64 "type: no arguments" "$T"
expect_exit 64 "type: empty text" "$T" $S ""
expect_exit 64 "type: extra argument" "$T" $S ab cd

# one letter per row end, plus the first key of each row
: > "$FAKE_ADB_STATE/log"
expect_exit 0 "type: letters map to key centres" "$T" $S qpaLzm
check "type: taps in order" taps_are "72 662,1008 662,125 800,957 800,228 935,852 935"
check "type: every call names the device" all_calls_addressed

: > "$FAKE_ADB_STATE/log"
expect_exit 0 "type: case-insensitive" "$T" $S "HeLLo"
check "type: HeLLo taps h e l l o" taps_are "644 800,280 662,957 800,957 800,903 662"

: > "$FAKE_ADB_STATE/log"
expect_exit 0 "type: space and double space" "$T" $S "a  b"
check "type: space taps the space bar" taps_are "125 800,540 1055,540 1055,644 935"

for bad in "a1" "hi!" "a.b" "é" "a-b" 'a$b'; do
  : > "$FAKE_ADB_STATE/log"
  expect_exit 64 "type: rejects '$bad'" "$T" $S "$bad"
  check "type: '$bad' taps nothing and reads nothing" log_lacks "adb"
done
expect_exit 64 "type: bad character after good ones" "$T" $S "ab7"
check "type: bad character named" err_has "'7'"

: > "$FAKE_ADB_STATE/log"
( unset LP3_ALLOW_LIGHTOS; expect_exit 3 "type: refuses without LP3_ALLOW_LIGHTOS" "$T" $S ab )
check "type: no LP3_ALLOW_LIGHTOS: no input sent" log_lacks "input"
LP3_ALLOW_LIGHTOS=yes expect_exit 3 "type: LP3_ALLOW_LIGHTOS must be exactly 1" "$T" $S ab
check "type: refusal says to ask the human" err_has "ask the human"

# screen geometry: the table was measured at 1080x1240
printf 'Physical size: 1080x1240\nOverride size: 1080x2000\n' > "$FAKE_ADB_STATE/dev/$S/wm.size"
: > "$FAKE_ADB_STATE/log"
expect_exit 3 "type: size mismatch exits 3" "$T" $S ab
check "type: size mismatch: zero taps" log_lacks "input tap"
check "type: size mismatch says to re-measure" err_has "measured at 1080x1240"
printf 'Physical size: 1080x2000\nOverride size: 1080x1240\n' > "$FAKE_ADB_STATE/dev/$S/wm.size"
: > "$FAKE_ADB_STATE/log"
expect_exit 0 "type: override size is the effective size" "$T" $S ab
check "type: override size matches: taps sent" taps_are "125 800,644 935"
check "type: wm size read once" [ "$(grep -c 'wm size' "$FAKE_ADB_STATE/log")" = 1 ]
rm -f "$FAKE_ADB_STATE/dev/$S/wm.size"
: > "$FAKE_ADB_STATE/log"
expect_exit 0 "type: default size matches" "$T" $S ab
check "type: density read" grep -q "wm density" "$FAKE_ADB_STATE/log"
printf 'Physical density: 480\nOverride density: 320\n' > "$FAKE_ADB_STATE/dev/$S/wm.density"
: > "$FAKE_ADB_STATE/log"
expect_exit 3 "type: density override mismatch exits 3" "$T" $S ab
check "type: density mismatch: zero taps" log_lacks "input tap"
rm -f "$FAKE_ADB_STATE/dev/$S/wm.density"

# a guard failure before the first tap sends nothing
set_screen $S Awake "$(focus_of com.example.tool)"
: > "$FAKE_ADB_STATE/log"
expect_exit 3 "type: LightOS not focused" "$T" $S ab
check "type: not focused: no input sent" log_lacks "input"

# the phone falls asleep after two taps: the third is refused and the run stops there
set_screen $S Awake "$(focus_of $OS)"
mkdir -p "$WORK/wrap"
cat > "$WORK/wrap/adb" <<EOF
#!/usr/bin/env bash
"$TESTS/fake-adb/adb" "\$@" || exit \$?
case "\$*" in *"input tap"*)
  n=\$(grep -c 'input tap' "$FAKE_ADB_STATE/log")
  if [ "\$n" -ge 2 ]; then printf 'POWER MANAGER (dumpsys power)\n  mWakefulness=Asleep\n' > "$FAKE_ADB_STATE/dev/$S/power"; fi ;;
esac
EOF
chmod +x "$WORK/wrap/adb"
: > "$FAKE_ADB_STATE/log"
PATH="$WORK/wrap:$PATH" expect_exit 3 "type: stops on the first failed tap, exit code passed on" "$T" $S abcd
check "type: only the taps before the failure were sent" taps_are "125 800,644 935"
check "type: failure reason shown" err_has "Asleep"
unset LP3_ALLOW_LIGHTOS
