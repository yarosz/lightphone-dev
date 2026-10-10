# shellcheck shell=bash
# Tests for lp3-lease.sh. Sourced by run.sh.
L="$DEVICE/lp3-lease.sh"

new_state
export LP3_LEASE="$WORK/leases/lp3-lease"
unset LP3_SERIAL

expect_exit 0 "show: free" "$L" show
check "show: says free" out_has "LP3 free"
expect_exit 0 "take a free phone" "$L" take reader "perf run" 10
check "take: holder line" grep -qx "holder: reader" "$LP3_LEASE"
check "take: since in UTC" grep -Eq '^since: [0-9-]{10}T[0-9:]{8}\+0000$' "$LP3_LEASE"
check "take: until in UTC" grep -Eq '^until: [0-9-]{10}T[0-9:]{8}\+0000$' "$LP3_LEASE"
check "take: until_epoch" grep -Eq '^until_epoch: [0-9]+$' "$LP3_LEASE"
expect_exit 2 "take a held phone" "$L" take chess "ci"
check "take held: shows the holder" err_has "holder: reader"
expect_exit 4 "release someone else's lease" "$L" release chess
check "release someone else's: lease still there" test -f "$LP3_LEASE"
expect_exit 0 "renew your own lease" "$L" renew reader 20
check "renew: purpose kept" grep -qx "purpose: perf run" "$LP3_LEASE"
expect_exit 4 "renew someone else's lease" "$L" renew chess
expect_exit 0 "release your own lease" "$L" release reader
check "release: says LP3 free" out_has "LP3 free"
check "release: file gone" test ! -e "$LP3_LEASE"
expect_exit 4 "release with no lease" "$L" release reader

# expired leases are taken over
now=$(date +%s)
printf 'holder: doom\npurpose: x\nsince: s\nuntil: u\nuntil_epoch: %s\n' $((now - 60)) > "$LP3_LEASE"
expect_exit 0 "take over an expired lease" "$L" take chess "ci"
check "take over: reports the old lease" err_has "took over an expired lease"
check "take over: new holder" grep -qx "holder: chess" "$LP3_LEASE"
"$L" release chess >/dev/null

# hand-written leases: until honoured, open means held
printf 'holder: someone\nuntil: 2001-01-01T00:00:00+0000\n' > "$LP3_LEASE"
expect_exit 0 "hand-written past until: taken over" "$L" take chess ci
"$L" release chess >/dev/null
printf 'holder: someone\nuntil: 2999-01-01T00:00:00+0000\n' > "$LP3_LEASE"
expect_exit 2 "hand-written future until: held" "$L" take chess ci
printf 'holder: owner\nuntil: open\n' > "$LP3_LEASE"
expect_exit 2 "until: open is held" "$L" take chess ci
printf 'holder: owner\nuntil: after lunch\n' > "$LP3_LEASE"
expect_exit 2 "unparseable until is held" "$L" take chess ci
rm -f "$LP3_LEASE"

expect_exit 0 "take open (a person holds it)" "$L" take owner "reading" open
check "take open: until: open" grep -qx "until: open" "$LP3_LEASE"
check "take open: no until_epoch" sh -c "! grep -q until_epoch '$LP3_LEASE'"
expect_exit 2 "an open hold blocks agents" "$L" take chess ci
"$L" release owner >/dev/null

expect_exit 64 "take: bad minutes" "$L" take chess ci soon
expect_exit 64 "take: no purpose" "$L" take chess
check "take: no purpose prints usage" err_has "lp3-lease.sh take"
expect_exit 64 "take: no holder" "$L" take
expect_exit 64 "renew: no holder" "$L" renew
expect_exit 64 "release: no holder" "$L" release
check "release: no holder prints usage" err_has "lp3-lease.sh release"
expect_exit 64 "unknown command" "$L" grab
expect_exit 0 "-h" "$L" -h
check "-h prints usage" out_has "lp3-lease.sh take"

# LP3_SERIAL: take checks the phone is attached
add_device SER-ONE TLP301 SER-ONE
LP3_SERIAL=SER-ONE expect_exit 0 "take with LP3_SERIAL attached" "$L" take chess ci
"$L" release chess >/dev/null
LP3_SERIAL=SER-TWO expect_exit 1 "take with LP3_SERIAL missing" "$L" take chess ci
unset LP3_LEASE

# Three sessions and a slow mv (the round-3 repro). B and C both see an expired lease. The fake mv lets
# the first move through at once; the second sleeps, moves B's fresh lease aside, then sleeps again
# before anything can put it back, and D arrives in that gap. Exactly one session may end up holding.
new_state
export LP3_LEASE="$WORK/leases/lp3-lease"
mkdir -p "$WORK/leases" "$WORK/racebin" "$WORK/rc"
cat > "$WORK/racebin/mv" <<'MV'
#!/usr/bin/env bash
case "${2:-}" in
  *.stale.*)
    [ -z "${RACE_SLOW:-}" ] || sleep 1.5
    /bin/mv "$@" || exit
    [ -z "${RACE_SLOW:-}" ] || sleep 1 ;;
  *) exec /bin/mv "$@" ;;
esac
MV
chmod +x "$WORK/racebin/mv"
printf 'holder: doom\nuntil_epoch: %s\n' $(( $(date +%s) - 60 )) > "$LP3_LEASE"
( PATH="$WORK/racebin:$PATH" "$L" take B ci >/dev/null 2>&1; echo $? > "$WORK/rc/B" ) &
( PATH="$WORK/racebin:$PATH" RACE_SLOW=1 "$L" take C ci >/dev/null 2>&1; echo $? > "$WORK/rc/C" ) &
( sleep 2; PATH="$WORK/racebin:$PATH" "$L" take D ci >/dev/null 2>&1; echo $? > "$WORK/rc/D" ) &
wait
winners=$(grep -lx 0 "$WORK/rc/"* | wc -l | tr -d ' ')
check "three sessions, slow mv: exactly one holder (got $winners)" test "$winners" -eq 1
holder=$(sed -n 's/^holder: //p' "$LP3_LEASE")
check "three sessions: the lease names the winner" test "$(cat "$WORK/rc/$holder" 2>/dev/null)" = 0
check "three sessions: no stale file left" sh -c "! ls '$WORK/leases' | grep -q stale"
rm -f "$LP3_LEASE"

# the lock: a stale one (over 30 s old) is cleared, a fresh one makes take give up with 3
mkdir "$LP3_LEASE.lock"; touch -t 202001010000 "$LP3_LEASE.lock"
expect_exit 0 "a stale lock is cleared" "$L" take chess ci
check "stale lock: lock dir gone afterwards" test ! -e "$LP3_LEASE.lock"
"$L" release chess >/dev/null
mkdir "$LP3_LEASE.lock"
expect_exit 3 "a fresh lock held by another session" "$L" take chess ci
check "fresh lock: says busy" err_has "busy"
check "fresh lock: no lease written" test ! -e "$LP3_LEASE"
rmdir "$LP3_LEASE.lock"

# minutes: base 10, 0-1440; holder not empty
now=$(date +%s)
expect_exit 0 "take 010 minutes" "$L" take chess ci 010
ue=$(sed -n 's/^until_epoch: //p' "$LP3_LEASE")
check "010 minutes is 10, not octal 8" test $(( ue - now )) -ge 600 -a $(( ue - now )) -le 605
"$L" release chess >/dev/null
expect_exit 0 "take 09 minutes (not an octal error)" "$L" take chess ci 09
expect_exit 0 "renew 0008 minutes" "$L" renew chess 0008
"$L" release chess >/dev/null
expect_exit 64 "take: minutes overflow" "$L" take chess ci 99999999999999999999
expect_exit 64 "take: 1441 minutes" "$L" take chess ci 1441
expect_exit 0 "take: 1440 minutes" "$L" take chess ci 1440
expect_exit 64 "renew: minutes overflow" "$L" renew chess 99999999999999999999
"$L" release chess >/dev/null
expect_exit 64 "take: empty holder" "$L" take "" ci
expect_exit 64 "renew: empty holder" "$L" renew ""
expect_exit 64 "release: empty holder" "$L" release ""
unset LP3_LEASE

# holder and purpose: no newline or CR; holder compared exactly
new_state
export LP3_LEASE="$WORK/leases/lp3-lease"
"$L" take alice "perf run" 10 >/dev/null
cp "$LP3_LEASE" "$WORK/alice-lease"
expect_exit 64 "release: a newline holder can't delete someone else's lease" "$L" release $'bob\nholder: alice'
check "release newline holder: alice's lease untouched" cmp -s "$LP3_LEASE" "$WORK/alice-lease"
expect_exit 64 "renew: a newline holder can't rewrite someone else's lease" "$L" renew $'bob\nholder: alice' 30
check "renew newline holder: alice's lease untouched" cmp -s "$LP3_LEASE" "$WORK/alice-lease"
expect_exit 64 "release: CR in holder" "$L" release $'alice\r'
expect_exit 4 "release: a holder that is a prefix doesn't match" "$L" release ali
expect_exit 4 "release: a regex holder doesn't match" "$L" release 'al.ce'
check "prefix/regex holders: alice's lease untouched" cmp -s "$LP3_LEASE" "$WORK/alice-lease"
"$L" release alice >/dev/null
expect_exit 64 "take: newline in holder" "$L" take $'x\nuntil: open' ci
expect_exit 64 "take: newline in purpose" "$L" take x $'ci\nholder: y'
expect_exit 64 "take: CR in purpose" "$L" take x $'ci\r'
check "take with newlines: no lease written" test ! -e "$LP3_LEASE"

# until: open is held even with an old until_epoch
printf 'holder: owner\nuntil: open\nuntil_epoch: %s\n' $(( $(date +%s) - 3600 )) > "$LP3_LEASE"
expect_exit 2 "until: open plus an old until_epoch is still held" "$L" take chess ci
check "open plus old epoch: owner keeps it" grep -qx "holder: owner" "$LP3_LEASE"
unset LP3_LEASE
