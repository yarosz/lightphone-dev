# shellcheck shell=bash
# Tests for lp3-settings.sh. Sourced by run.sh.
X="$DEVICE/lp3-settings.sh"
S=SER-ONE

new_state; add_device $S TLP301 $S
SET="$FAKE_ADB_STATE/dev/$S/settings"
echo 0 > "$SET/global.stay_on_while_plugged_in"
echo 1 > "$SET/secure.accessibility_display_daltonizer_enabled"
saved="$WORK/saved/settings"

expect_exit 0 "save three keys, one unset" "$X" $S save "$saved" global:stay_on_while_plugged_in \
  secure:accessibility_display_daltonizer_enabled system:screen_off_timeout
check "save: file records null for the unset key" grep -q "^system	screen_off_timeout	null$" "$saved"

# the run changes everything
echo 7 > "$SET/global.stay_on_while_plugged_in"
echo 0 > "$SET/secure.accessibility_display_daltonizer_enabled"
echo 600000 > "$SET/system.screen_off_timeout"

expect_exit 1 "save again refuses to overwrite the originals" "$X" $S save "$saved" global:stay_on_while_plugged_in
check "save again: originals untouched" grep -q "^global	stay_on_while_plugged_in	0$" "$saved"

expect_exit 0 "restore" "$X" $S restore "$saved"
check "restore: value put back" grep -qx 0 "$SET/global.stay_on_while_plugged_in"
check "restore: grayscale back on" grep -qx 1 "$SET/secure.accessibility_display_daltonizer_enabled"
check "restore: null deletes the key, not 0" test ! -e "$SET/system.screen_off_timeout"
check "restore: delete was used" log_has "settings delete system screen_off_timeout"
check "restore: file removed after success" test ! -e "$saved"
check "settings: every call uses -s" all_calls_addressed

expect_exit 1 "restore with no file" "$X" $S restore "$saved"
expect_exit 64 "save: bad namespace" "$X" $S save "$WORK/x" vendor:thing
expect_exit 64 "save: missing namespace" "$X" $S save "$WORK/x" stay_on_while_plugged_in
expect_exit 64 "save: key with shell characters" "$X" $S save "$WORK/x" 'global:a;reboot'

# a value with a space survives the round trip
new_state; add_device $S TLP301 $S
SET="$FAKE_ADB_STATE/dev/$S/settings"
echo "two words" > "$SET/secure.some_label"
expect_exit 0 "save a value with a space" "$X" $S save "$WORK/sp" secure:some_label
echo changed > "$SET/secure.some_label"
expect_exit 0 "restore a value with a space" "$X" $S restore "$WORK/sp"
check "restore: value with a space intact" grep -qx "two words" "$SET/secure.some_label"

# device gone mid-save: no file is written
new_state
expect_exit 1 "save with the device gone" "$X" SER-GONE save "$WORK/gone" global:stay_on_while_plugged_in
check "save with the device gone: no file" test ! -e "$WORK/gone"

# values are kept exactly: leading and trailing tabs, inner spaces
new_state; add_device $S TLP301 $S
SET="$FAKE_ADB_STATE/dev/$S/settings"
printf '\tlead\n' > "$SET/secure.lead_tab"
printf 'trail\t\n' > "$SET/secure.trail_tab"
printf ' two  spaces \n' > "$SET/secure.spaces"
cp "$SET/secure.lead_tab" "$WORK/lead.want"; cp "$SET/secure.trail_tab" "$WORK/trail.want"; cp "$SET/secure.spaces" "$WORK/spaces.want"
expect_exit 0 "save values with tabs and spaces" "$X" $S save "$WORK/tabs" secure:lead_tab secure:trail_tab secure:spaces
echo changed > "$SET/secure.lead_tab"; echo changed > "$SET/secure.trail_tab"; echo changed > "$SET/secure.spaces"
expect_exit 0 "restore values with tabs and spaces" "$X" $S restore "$WORK/tabs"
check "restore: leading tab kept" cmp -s "$SET/secure.lead_tab" "$WORK/lead.want"
check "restore: trailing tab kept" cmp -s "$SET/secure.trail_tab" "$WORK/trail.want"
check "restore: spaces kept" cmp -s "$SET/secure.spaces" "$WORK/spaces.want"

# a multi-line value can't be saved one per line: refused
printf 'line one\nline two\n' > "$SET/secure.multi"
expect_exit 64 "save refuses a multi-line value" "$X" $S save "$WORK/multi" secure:multi
check "save multi-line: no file written" test ! -e "$WORK/multi"

# a CR or a trailing newline can't survive save and restore exactly: refused at save
printf 'a\rb\n' > "$SET/secure.cr_inside"
expect_exit 64 "save refuses a value with a CR" "$X" $S save "$WORK/cr" secure:cr_inside
check "save CR: no file written" test ! -e "$WORK/cr"
printf 'value\n\n' > "$SET/secure.trailing_nl"
expect_exit 64 "save refuses a value with a trailing newline" "$X" $S save "$WORK/nl" secure:trailing_nl
check "save trailing newline: no file written" test ! -e "$WORK/nl"
