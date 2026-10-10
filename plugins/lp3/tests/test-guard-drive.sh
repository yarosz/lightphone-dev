# Tests for lp3-guard.sh and lp3-drive.sh. Sourced by run.sh.
G="$DEVICE/lp3-guard.sh"
D="$DEVICE/lp3-drive.sh"
PKG=com.example.tool
S=SER-ONE

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $PKG)"
expect_exit 0 "guard: awake, unlocked, focused" "$G" $S $PKG

set_screen $S Dozing "$(focus_of $PKG)"
expect_exit 3 "guard: Dozing" "$G" $S $PKG
check "guard: Dozing reason" err_has "Dozing"

set_screen $S Asleep "$(focus_of $PKG)"
expect_exit 3 "guard: Asleep" "$G" $S $PKG

set_screen $S Awake "$(focus_of $PKG)" true
expect_exit 3 "guard: keyguard showing" "$G" $S $PKG
check "guard: keyguard reason" err_has "keyguard"

set_screen $S Awake "Window{9f u0 Keyguard}"
expect_exit 3 "guard: keyguard has focus" "$G" $S $PKG

set_screen $S Awake "Window{9f u0 NotificationShade}"
expect_exit 3 "guard: NotificationShade has focus" "$G" $S $PKG
check "guard: NotificationShade reason" err_has "NotificationShade"

set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 3 "guard: LightOS has focus" "$G" $S $PKG
check "guard: wrong focus reason names it" err_has "com.lightos"

set_screen $S Awake "$(focus_of com.example.toolbox)"
expect_exit 3 "guard: a package with the same prefix doesn't count" "$G" $S $PKG

set_screen $S Awake "null"
expect_exit 3 "guard: nothing focused" "$G" $S $PKG

expect_exit 3 "guard: device gone" "$G" SER-GONE $PKG
set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 0 "guard --pre-launch with LightOS focus" "$G" --pre-launch $S $PKG
set_screen $S Awake "Window{9f u0 NotificationShade}"
expect_exit 3 "guard --pre-launch with NotificationShade" "$G" --pre-launch $S $PKG
expect_exit 64 "guard: usage" "$G" $S

# drive: guarded verbs run input only after the guard passes
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $PKG)"
expect_exit 0 "drive tap" "$D" $S $PKG tap 540 600
check "drive tap: input sent" log_has "adb -s $S shell input tap 540 600"
expect_exit 0 "drive swipe" "$D" $S $PKG swipe 100 900 100 300 200
expect_exit 0 "drive key wheel" "$D" $S $PKG key 318
expect_exit 0 "drive text with a space" "$D" $S $PKG text "war and peace"
check "drive text: spaces sent as %s" log_has "input text war%sand%speace"
expect_exit 0 "drive shot" "$D" $S $PKG shot "$WORK/s.png"
check "drive shot: file written" test -s "$WORK/s.png"
check "drive shot: personal-data reminder" err_has "personal data"
expect_exit 0 "drive stop" "$D" $S $PKG stop
check "drive stop: force-stops only the package" log_has "am force-stop $PKG"
check "drive: every call uses -s" all_calls_addressed

new_state; add_device $S TLP301 $S
set_screen $S Dozing "$(focus_of $PKG)"
expect_exit 3 "drive tap while Dozing" "$D" $S $PKG tap 1 1
check "drive tap while Dozing: no input sent" log_lacks "input"
expect_exit 0 "drive shot while Dozing: no guard" "$D" $S $PKG shot "$WORK/s.png"

set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 3 "drive key with LightOS focus" "$D" $S $PKG key 24
check "drive key with LightOS focus: no key sent" log_lacks "keyevent"

set_screen $S Awake "$(focus_of $PKG)"
for k in 26 KEYCODE_POWER 223 224 KEYCODE_WAKEUP; do
  expect_exit 3 "drive key $k refused" "$D" $S $PKG key $k
done
check "drive: POWER never sent" log_lacks "keyevent"
expect_exit 64 "drive tap: bad coordinates" "$D" $S $PKG tap 1 x
expect_exit 64 "drive: unknown verb" "$D" $S $PKG poke

# launch: pre-launch guard, am start, then focus must arrive
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
cp "$FAKE_ADB_STATE/dev/$S/window" "$WORK/home"
set_screen $S Awake "$(focus_of $PKG)"
mv "$FAKE_ADB_STATE/dev/$S/window" "$FAKE_ADB_STATE/dev/$S/window.launched"
cp "$WORK/home" "$FAKE_ADB_STATE/dev/$S/window"
expect_exit 0 "drive launch from LightOS" "$D" $S $PKG launch .MainActivity
check "drive launch: component built" log_has "am start -W -n $PKG/.MainActivity"

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 3 "drive launch: Tool never takes focus" "$D" $S $PKG launch .MainActivity

new_state; add_device $S TLP301 $S
set_screen $S Dozing "$(focus_of com.lightos)"
expect_exit 3 "drive launch while Dozing" "$D" $S $PKG launch .MainActivity
check "drive launch while Dozing: nothing started" log_lacks "am start"
