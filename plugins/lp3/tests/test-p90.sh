# Tests for p90.py. Sourced by run.sh.
P="$SKILLS/lp3-measure/scripts/p90.py"

new_state
seq 1 10 > "$WORK/ten"
expect_exit 0 "1..10" python3 "$P" "$WORK/ten"
check "1..10: nearest rank P50=5 P90=9 P99=10" out_has "value n=10 p50=5 p90=9 p99=10 max=10"

seq 1 20 | python3 "$P" > "$WORK/out"
check "1..20 from stdin: P50=10 P90=18 P99=20" out_has "n=20 p50=10 p90=18 p99=20 max=20"

echo 42 | python3 "$P" > "$WORK/out"
check "one sample: every percentile is it" out_has "n=1 p50=42 p90=42 p99=42 max=42"

printf '%s\n' 900 800 1 2 3 4 5 6 7 8 9 10 > "$WORK/warm"
expect_exit 0 "--drop 2" python3 "$P" --drop 2 "$WORK/warm"
check "--drop drops the first samples, not the largest" out_has "n=10 p50=5 p90=9 p99=10 max=10"

cat > "$WORK/log" <<'EOF'
10-09 12:00:00.000  1234  1250 I ToolPerf: open_ms=120 bytes=3000
10-09 12:00:01.000  1234  1250 I ToolPerf: open_ms=110.5 turn_ms=14
10-09 12:00:02.000  1234  1250 I ToolPerf: open_ms=130 turn_ms=16
10-09 12:00:03.000  1234  1250 I ToolPerf: open_ms=125 turn_ms=15
EOF
expect_exit 0 "--key from logcat lines" python3 "$P" --key open_ms "$WORK/log"
check "--key: only that key" out_has "^open_ms n=4 p50=120 p90=130 p99=130 max=130$"
check "--key: other keys ignored" sh -c "! grep -q turn_ms '$WORK/out'"
expect_exit 0 "all keys" python3 "$P" "$WORK/log"
check "all keys: one row per key" out_has "^turn_ms n=3 p50=15 p90=16"
check "decimals kept" sh -c "python3 '$P' --key open_ms --drop 3 '$WORK/log' | grep -q 'max=125'"

printf 'no numbers here\n' > "$WORK/none"
expect_exit 1 "no samples" python3 "$P" "$WORK/none"
expect_exit 1 "dropped everything" python3 "$P" --drop 50 "$WORK/ten"
expect_exit 64 "bad --drop" python3 "$P" --drop -1 "$WORK/ten"
expect_exit 64 "unknown option" python3 "$P" --nope
expect_exit 0 "-h" python3 "$P" -h
