# shellcheck shell=bash disable=SC2016  # literal $ and backticks are the point here
# Docs and test-runner hygiene. Sourced by run.sh.
PLUGIN="$(cd "$TESTS/.." && pwd)"
new_state

# lp3-device: check awake and unlocked with the guard before an install, not a grep one-liner
check "device SKILL: no grep mWakefulness one-liner" sh -c "! grep -q 'grep mWakefulness' '$PLUGIN/skills/lp3-device/SKILL.md'"
check "device SKILL: pre-launch guard before an install" grep -q 'scripts/lp3-guard.sh --pre-launch <serial> <pkg>' "$PLUGIN/skills/lp3-device/SKILL.md"
# README names the tests relative to the plugin
check "README: tests/run.sh relative to the plugin" grep -qx 'tests/run.sh' "$PLUGIN/README.md"
check "README: no repo-relative test path" sh -c "! grep -q 'plugins/lp3/tests/run.sh' '$PLUGIN/README.md'"
# release: stop when the merge commit isn't there yet
check "release SKILL: empty merge commit stops" grep -qF '[ -n "$m" ] || { echo "no merge commit yet; wait and retry"; exit 1; }' "$PLUGIN/skills/lp3-release/SKILL.md"

# run.sh removes its temp directories, and stale ones from runs that died
tmp="$WORK/tmp"; mkdir -p "$tmp/lp3-test.dead" "$tmp/lp3-test.live" "$tmp/lp3-test.legacy/adb" "$tmp/lp3-test.other"
sh -c 'echo $$' > "$tmp/lp3-test.dead/pid"          # a process that has exited
echo $$ > "$tmp/lp3-test.live/pid"                  # this run: alive
touch -t 202601010000 "$tmp/lp3-test.legacy/adb" "$tmp/lp3-test.legacy"   # old per-test layout, no pid
TMPDIR="$tmp" "$TESTS/run.sh" p90 >/dev/null 2>&1
check "run.sh: inner run passed" test $? -eq 0
check "run.sh: stale dir of a dead run removed" test ! -e "$tmp/lp3-test.dead"
check "run.sh: old per-test dir removed" test ! -e "$tmp/lp3-test.legacy"
check "run.sh: a live run's dir kept" test -d "$tmp/lp3-test.live"
check "run.sh: a dir it didn't make kept" test -d "$tmp/lp3-test.other"
check "run.sh: its own temp dirs removed" sh -c "[ \$(ls -d '$tmp'/lp3-test.* | wc -l) -eq 2 ]"
