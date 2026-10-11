# shellcheck shell=bash
# Tests for lp3-find.sh. Sourced by run.sh.
F="$DEVICE/lp3-find.sh"

new_state
expect_exit 1 "no device: phone not found" "$F" --phone
check "no device: hint mentions the wireless entry" err_has "wireless"

new_state
add_device SER-ONE TLP301 SER-ONE
expect_exit 0 "one USB phone" "$F" --phone
check "one USB phone: prints its serial" out_has "^SER-ONE$"
check "every call uses -s" all_calls_addressed
check "never adb -d" log_lacks "adb -d"
check "never kill-server" log_lacks "kill-server"

new_state
add_device SER-ONE TLP301 SER-ONE
add_device SER-TWO TLP301 SER-TWO
expect_exit 2 "two phones: refuses to pick" "$F" --phone
check "two phones: lists both" err_has "SER-TWO"

new_state
add_device SER-ONE TLP301 SER-ONE
add_device "adb-SER-ONE-AbCdEf._adb-tls-connect._tcp" TLP301 SER-ONE
expect_exit 0 "same phone on USB and wireless: picks one" "$F" --phone
check "same phone on USB and wireless: prefers USB" out_has "^SER-ONE$"

new_state
add_device "adb-SER-ONE-AbCdEf._adb-tls-connect._tcp" TLP301 SER-ONE
expect_exit 0 "wireless only" "$F" --phone
check "wireless only: prints the mDNS serial" out_has "_adb-tls-connect._tcp$"

# adb renames an mDNS service after a quick wireless-debugging restart: "<name> (2)" has a space in it.
new_state
add_device "adb-SER-ONE-AbCdEf (2)._adb-tls-connect._tcp" TLP301 SER-ONE
expect_exit 0 "wireless serial with a space" "$F" --phone
check "wireless serial with a space: printed whole" out_has "^adb-SER-ONE-AbCdEf (2)\._adb-tls-connect\._tcp$"
check "wireless serial with a space: queried whole" log_has "adb -s adb-SER-ONE-AbCdEf (2)._adb-tls-connect._tcp shell getprop ro.product.model"

new_state
add_device "adb-SER-ONE-AbCdEf (2)._adb-tls-connect._tcp" TLP301 SER-ONE
add_device 192.168.1.20:41629 TLP301 SER-ONE
expect_exit 0 "same phone as a spaced mDNS name and IP:port: picks one" "$F" --phone

new_state
add_device OTHERPHONE Pixel_8 OTHERPHONE
add_device emulator-5556 sdk_gphone64_arm64
expect_exit 1 "other phone and an emulator: no LP3" "$F" --phone

new_state
add_device SER-ONE TLP301 SER-ONE
printf 'SER-OFF\toffline\nSER-UN\tunauthorized\n' >> "$FAKE_ADB_STATE/devices"
expect_exit 0 "offline and unauthorized entries are skipped" "$F" --phone
check "offline entries never queried" log_lacks "SER-OFF"

new_state
add_device emulator-5556; echo LightPhone3 > "$FAKE_ADB_STATE/dev/emulator-5556/avd"
add_device emulator-5558; echo ChessLP3 > "$FAKE_ADB_STATE/dev/emulator-5558/avd"
expect_exit 0 "emulator by AVD name" "$F" --avd ChessLP3
check "emulator by AVD name: the right one" out_has "^emulator-5558$"
expect_exit 1 "emulator: unknown AVD" "$F" --avd Nope

new_state
add_device emulator-5556; echo LightPhone3 > "$FAKE_ADB_STATE/dev/emulator-5556/avd"
add_device emulator-5558; echo LightPhone3 > "$FAKE_ADB_STATE/dev/emulator-5558/avd"
expect_exit 2 "two emulators with one AVD name" "$F" --avd LightPhone3

new_state
cp "$FAKE_ADB_STATE/devices" "$FAKE_ADB_STATE/devices.later"
printf 'SER-ONE\tdevice\n' >> "$FAKE_ADB_STATE/devices.later"
mkdir -p "$FAKE_ADB_STATE/dev/SER-ONE"; echo TLP301 > "$FAKE_ADB_STATE/dev/SER-ONE/model"
echo 2 > "$FAKE_ADB_STATE/appear_after"
expect_exit 0 "--wait: phone comes back" "$F" --phone --wait 20
check "--wait: prints it once back" out_has "^SER-ONE$"

new_state
expect_exit 1 "--wait: gives up at the deadline" "$F" --phone --wait 1
expect_exit 64 "bad option" "$F" --bogus
expect_exit 0 "-h" "$F" -h
check "-h prints usage" out_has "lp3-find.sh"

# numbers are checked before arithmetic or sleep
new_state
expect_exit 64 "--wait over 4 digits" "$F" --phone --wait 99999999999999999999
LP3_FIND_POLL="x[\$(touch $WORK/canary)]" expect_exit 64 "LP3_FIND_POLL with a command" "$F" --phone --wait 1
check "LP3_FIND_POLL payload never ran" test ! -e "$WORK/canary"
