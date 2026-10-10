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
expect_exit 64 "unknown command" "$L" grab
expect_exit 0 "-h" "$L" -h
check "-h prints usage" out_has "lp3-lease.sh take"

# LP3_SERIAL: take checks the phone is attached
add_device SER-ONE TLP301 SER-ONE
LP3_SERIAL=SER-ONE expect_exit 0 "take with LP3_SERIAL attached" "$L" take chess ci
"$L" release chess >/dev/null
LP3_SERIAL=SER-TWO expect_exit 1 "take with LP3_SERIAL missing" "$L" take chess ci
unset LP3_LEASE
