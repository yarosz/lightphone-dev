# shellcheck shell=bash disable=SC2016  # literal $ and backticks are the point here
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
expect_exit 3 "guard: keyguard showing (isKeyguardShowing, as on Android 14)" "$G" $S $PKG
check "guard: keyguard reason" err_has "keyguard"

set_screen $S Awake "$(focus_of $PKG)" false true
expect_exit 3 "guard: keyguard showing in dumpsys activity only" "$G" $S $PKG
check "guard: activity keyguard reason" err_has "keyguard"

set_screen $S Awake "$(focus_of $PKG)"
printf '  mShowingLockscreen=true mShowingDream=false\n' >> "$FAKE_ADB_STATE/dev/$S/window.policy"
expect_exit 3 "guard: older mShowingLockscreen field still counts" "$G" $S $PKG

set_screen $S Awake "$(focus_of com.lightos)" true
expect_exit 3 "guard --pre-launch refuses when locked over LightOS" "$G" --pre-launch $S $PKG
set_screen $S Awake "$(focus_of com.lightos)" false true
expect_exit 3 "guard --pre-launch refuses when dumpsys activity says locked" "$G" --pre-launch $S $PKG

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

# live state only: a LAST ANR section printed first must not count
set_screen $S Awake "$(focus_of com.lightos)"
set_last_anr $S "$(focus_of $PKG)"
expect_exit 3 "guard: LAST ANR shows the Tool, live focus is another app" "$G" $S $PKG
check "guard: live focus named" err_has "com.lightos"
check "guard: reads focus from dumpsys window displays" log_has "shell dumpsys window displays"
check "guard: reads keyguard from dumpsys window policy" log_has "shell dumpsys window policy"
check "guard: reads keyguard evidence from dumpsys window displays" log_has "shell dumpsys window displays"
check "guard: never reads the full dumpsys window" log_lacks "shell dumpsys window$"
rm -f "$FAKE_ADB_STATE/dev/$S/window.lastanr"

set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak 's/isKeyguardShowing=false/isKeyguardShowing = true/' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard: spaced isKeyguardShowing = true" "$G" $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak 's/mKeyguardShowing=false/mKeyguardShowing = true/' "$FAKE_ADB_STATE/dev/$S/activity"
expect_exit 3 "guard: spaced mKeyguardShowing = true" "$G" $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak 's/mIsShowing=false/mIsShowing=true/' "$FAKE_ADB_STATE/dev/$S/window.policy"
expect_exit 3 "guard: KeyguardStateMonitor mIsShowing=true" "$G" $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
expect_exit 0 "guard: unlocked again after the spaced-form fixtures" "$G" $S $PKG

# the keyguard check needs positive evidence: isKeyguardShowing=false, and no source saying true
set_screen $S Awake "$(focus_of $PKG)"
: > "$FAKE_ADB_STATE/dev/$S/window.policy"; : > "$FAKE_ADB_STATE/dev/$S/activity"; sed -i.bak '/isKeyguardShowing/d' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard: both keyguard sources empty" "$G" $S $PKG
check "guard: empty sources reason" err_has "can't confirm the phone is unlocked"
set_screen $S Awake "$(focus_of com.lightos)"
: > "$FAKE_ADB_STATE/dev/$S/window.policy"; : > "$FAKE_ADB_STATE/dev/$S/activity"; sed -i.bak '/isKeyguardShowing/d' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard --pre-launch: both keyguard sources empty" "$G" --pre-launch $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak '/isKeyguardShowing/d' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard: no isKeyguardShowing line" "$G" $S $PKG
check "guard: missing isKeyguardShowing reason" err_has "can't confirm the phone is unlocked"
set_screen $S Awake "$(focus_of com.lightos)"
sed -i.bak '/isKeyguardShowing/d' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard --pre-launch: no isKeyguardShowing line" "$G" --pre-launch $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak 's/      showing=false/      showing=true/' "$FAKE_ADB_STATE/dev/$S/window.policy"
expect_exit 3 "guard: KeyguardServiceDelegate showing=true" "$G" $S $PKG
set_screen $S Awake "$(focus_of com.lightos)"
sed -i.bak 's/      showing=false/      showing=true/' "$FAKE_ADB_STATE/dev/$S/window.policy"
expect_exit 3 "guard --pre-launch: KeyguardServiceDelegate showing=true" "$G" --pre-launch $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
sed -i.bak 's/isKeyguardShowing=false/isKeyguardShowing = false/' "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 0 "guard: spaced isKeyguardShowing = false is evidence" "$G" $S $PKG

# focus is the window's component, not its title; with several displays the global (last) line counts
set_screen $S Awake "Window{9f u0 Share $PKG/notes}"
expect_exit 3 "guard: a window title holding the package doesn't count" "$G" $S $PKG
set_screen $S Awake "Window{9f u0 $PKG/.Main extra}"
expect_exit 3 "guard: text after the component doesn't count" "$G" $S $PKG
set_screen $S Awake "Window{9f u0 evil u0 $PKG/x}"
expect_exit 3 "guard: a title that mimics 'u0 <pkg>/' doesn't count" "$G" $S $PKG
set_screen $S Awake "$(focus_of $PKG)"
printf '  Display: mDisplayId=2\n  mCurrentFocus=%s\n' "$(focus_of com.lightos)" >> "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 3 "guard: Tool focused on one display, global focus elsewhere" "$G" $S $PKG
check "guard: global focus named" err_has "com.lightos"
set_screen $S Awake "$(focus_of com.lightos)"
printf '  mCurrentFocus=%s\n' "$(focus_of $PKG)" >> "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 0 "guard: global (last) focus is the Tool" "$G" $S $PKG

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
for k in 26 0026 026 KEYCODE_POWER POWER 223 KEYCODE_SLEEP 224 KEYCODE_WAKEUP 276 0276 KEYCODE_SOFT_SLEEP SOFT_SLEEP KEYCODE_26 KEYCODE_0026 KEYCODE_276; do
  expect_exit 3 "drive key $k refused" "$D" $S $PKG key $k
done
for k in 6 06 0006 KEYCODE_ENDCALL ENDCALL KEYCODE_6 KEYCODE_006 177 0177 KEYCODE_TV_POWER TV_POWER KEYCODE_177 KEYCODE_00177; do
  expect_exit 3 "drive key $k refused (ENDCALL/TV_POWER)" "$D" $S $PKG key $k
done
check "drive: POWER never sent" log_lacks "keyevent"
expect_exit 0 "drive key with leading zeros is sent as the number" "$D" $S $PKG key 0024
check "drive key 0024: sent as 24" log_has "input keyevent 24"
expect_exit 64 "drive tap: bad coordinates" "$D" $S $PKG tap 1 x
expect_exit 64 "drive: unknown verb" "$D" $S $PKG poke

# launch: pre-launch guard, am start, then focus must arrive
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
cp "$FAKE_ADB_STATE/dev/$S/window.displays" "$WORK/home"
set_screen $S Awake "$(focus_of $PKG)"
mv "$FAKE_ADB_STATE/dev/$S/window.displays" "$FAKE_ADB_STATE/dev/$S/window.displays.launched"
cp "$WORK/home" "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 0 "drive launch from LightOS" "$D" $S $PKG launch .MainActivity
check "drive launch: component built" log_has "am start -W -n $PKG/.MainActivity"

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 3 "drive launch: Tool never takes focus" "$D" $S $PKG launch .MainActivity

new_state; add_device $S TLP301 $S
set_screen $S Dozing "$(focus_of com.lightos)"
expect_exit 3 "drive launch while Dozing" "$D" $S $PKG launch .MainActivity
check "drive launch while Dozing: nothing started" log_lacks "am start"

# <pkg> must look like a package name
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $PKG)"
for bad in 'com.x;reboot' 'com' '1com.x' 'com..x' 'com.x/y' 'com x.y' "\$(id).x" ''; do
  expect_exit 64 "guard refuses pkg $(printf '%q' "$bad")" "$G" $S "$bad"
  expect_exit 64 "guard --pre-launch refuses pkg $(printf '%q' "$bad")" "$G" --pre-launch $S "$bad"
  expect_exit 64 "drive refuses pkg $(printf '%q' "$bad")" "$D" $S "$bad" stop
done
check "bad pkg: nothing reached adb" log_lacks "adb"

# launch component: nothing malformed reaches `shell`
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
for bad in '.Main;reboot' '.Main$(id)' '.Main`id`' $'.Main\nreboot' '.Main Activity' 'com.other/.Main' \
  "$PKG/.Main;x" '/.Main' "$PKG/" '9Main' '.' '-n' "$PKG/.A/.B"; do
  expect_exit 64 "drive launch refuses $(printf '%q' "$bad")" "$D" $S $PKG launch "$bad"
done
check "bad launch component: nothing reached shell" log_lacks "shell"
cp "$FAKE_ADB_STATE/dev/$S/window.displays" "$WORK/home"
set_screen $S Awake "$(focus_of $PKG)"
mv "$FAKE_ADB_STATE/dev/$S/window.displays" "$FAKE_ADB_STATE/dev/$S/window.displays.launched"
for good in MainActivity "$PKG/com.example.tool.ui.Main"; do
  cp "$WORK/home" "$FAKE_ADB_STATE/dev/$S/window.displays"
  expect_exit 0 "drive launch accepts $good" "$D" $S $PKG launch "$good"
done
check "drive launch: bare class gets a dot" log_has "am start -W -n $PKG/.MainActivity\$"
check "drive launch: full class kept" log_has "am start -W -n $PKG/com.example.tool.ui.Main\$"
# A legal inner class ($) is passed quoted; the fake refuses any $ (exit 96), which shows it arrived escaped.
cp "$WORK/home" "$FAKE_ADB_STATE/dev/$S/window.displays"
expect_exit 96 "drive launch: inner class reaches adb escaped" "$D" $S $PKG launch '.ui.Main$Inner'
check "drive launch: inner class escaped" log_has 'am start -W -n com.example.tool/.ui.Main\\\$Inner$'

# every other verb: values are numeric or quoted before they reach shell
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $PKG)"
expect_exit 64 "drive tap: negative" "$D" $S $PKG tap -1 5
expect_exit 64 "drive tap: injected" "$D" $S $PKG tap '1;reboot' 5
expect_exit 64 "drive tap: newline" "$D" $S $PKG tap $'1\nreboot' 5
expect_exit 64 "drive swipe: injected duration" "$D" $S $PKG swipe 1 2 3 4 '5;reboot'
expect_exit 64 "drive key: injected" "$D" $S $PKG key 'KEYCODE_A;reboot'
expect_exit 64 "drive key: newline" "$D" $S $PKG key $'KEYCODE_A\nreboot'
expect_exit 64 "drive stop: extra argument" "$D" $S $PKG stop now
check "injected values never reached adb" log_lacks "reboot"
expect_exit 0 "drive text with a quote" "$D" $S $PKG text "it's"
check "drive text: quote escaped" log_has "input text it\\\\'s\$"
expect_exit 96 "drive text with ; reaches adb escaped (fake refuses any ;)" "$D" $S $PKG text 'a;b'
check "drive text: ; escaped" log_has 'input text a\\;b$'

# LP3_FOCUS_WAIT is a number before it reaches arithmetic (a[$(...)] would run inside $(( )))
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
LP3_FOCUS_WAIT="serial[\$(touch $WORK/canary)]" expect_exit 64 "drive launch: LP3_FOCUS_WAIT with a command" "$D" $S $PKG launch .MainActivity
check "LP3_FOCUS_WAIT payload never ran" test ! -e "$WORK/canary"
check "LP3_FOCUS_WAIT payload: nothing started" log_lacks "am start"
LP3_FOCUS_WAIT=12345 expect_exit 64 "drive launch: LP3_FOCUS_WAIT over 4 digits" "$D" $S $PKG launch .MainActivity

# a backslash in the class, and a doubled KEYCODE_ prefix, are refused
new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 64 "drive launch refuses a backslash in the class" "$D" $S $PKG launch '.Main\Inner'
check "backslash class: nothing reached shell" log_lacks "shell"
set_screen $S Awake "$(focus_of $PKG)"
for k in KEYCODE_KEYCODE_POWER KEYCODE_KEYCODE_24 KEYCODE_KEYCODE_0026; do
  expect_exit 64 "drive key $k refused" "$D" $S $PKG key $k
done
check "doubled KEYCODE_: no key sent" log_lacks "keyevent"

# wake: KEYCODE_WAKEUP and wm dismiss-keyguard, then the --pre-launch guard must pass
export LP3_WAKE_WAIT=1
new_state; add_device $S TLP301 $S
set_screen $S Asleep "$(focus_of com.lightos)" true
touch "$FAKE_ADB_STATE/dev/$S/wake.wakes" "$FAKE_ADB_STATE/dev/$S/wake.unlocks"
expect_exit 0 "drive wake: asleep and locked, no PIN" "$D" $S $PKG wake
check "drive wake: WAKEUP sent with -s" log_has "^adb -s $S shell input keyevent KEYCODE_WAKEUP$"
check "drive wake: dismiss-keyguard sent with -s" log_has "^adb -s $S shell wm dismiss-keyguard$"
check "drive wake: every call uses -s" all_calls_addressed
expect_exit 0 "guard --pre-launch passes after wake" "$G" --pre-launch $S $PKG

new_state; add_device $S TLP301 $S
set_screen $S Asleep "$(focus_of com.lightos)" true
touch "$FAKE_ADB_STATE/dev/$S/wake.wakes"   # wakes, but a PIN keeps the keyguard up
expect_exit 3 "drive wake: keyguard stays showing" "$D" $S $PKG wake
check "drive wake: keyguard reason" err_has "keyguard"
check "drive wake: tells the agent to ask the human" err_has "Ask the human"
check "drive wake: doesn't tell the agent to run wake again" bash -c '! grep -q "run lp3-drive.sh" "$1"' _ "$WORK/err"
check "drive wake: still tried dismiss-keyguard" log_has "wm dismiss-keyguard"

new_state; add_device $S TLP301 $S
set_screen $S Asleep "$(focus_of com.lightos)"
expect_exit 3 "drive wake: stays asleep" "$D" $S $PKG wake
check "drive wake: asleep reason" err_has "Asleep"

new_state
expect_exit 3 "drive wake: device not on adb" "$D" SER-GONE $PKG wake
check "drive wake: no device tells the agent to ask the human" err_has "Ask the human"
# No adb at all: a PATH holding only bash and the system directories (skipped if those have an adb).
if [ ! -e /usr/bin/adb ] && [ ! -e /bin/adb ]; then
  mkdir -p "$WORK/noadb"; ln -s "$(command -v bash)" "$WORK/noadb/bash"
  PATH="$WORK/noadb:/usr/bin:/bin" expect_exit 3 "drive wake: no adb on PATH" "$D" $S $PKG wake
  check "drive wake: no adb tells the agent to ask the human" err_has "Ask the human"
fi

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of com.lightos)"
expect_exit 0 "drive wake: already awake and unlocked" "$D" $S $PKG wake
check "drive wake: already awake sends no keyevent" log_lacks "keyevent"
check "drive wake: already awake sends no dismiss-keyguard" log_lacks "dismiss-keyguard"

new_state; add_device $S TLP301 $S
set_screen $S Awake "$(focus_of $PKG)"
for k in 224 KEYCODE_WAKEUP WAKEUP KEYCODE_0224 0224; do
  expect_exit 3 "drive key $k still refused (wake is the only way)" "$D" $S $PKG key $k
  check "drive key $k: refusal points to wake" err_has " wake$"
done
check "drive key WAKEUP: no keyevent sent" log_lacks "keyevent"
expect_exit 64 "drive wake: extra argument" "$D" $S $PKG wake now
LP3_WAKE_WAIT="x[\$(touch $WORK/canary)]" expect_exit 64 "drive wake: LP3_WAKE_WAIT with a command" "$D" $S $PKG wake
check "LP3_WAKE_WAIT payload never ran" test ! -e "$WORK/canary"
check "LP3_WAKE_WAIT payload: nothing reached adb" log_lacks "adb"
unset LP3_WAKE_WAIT
