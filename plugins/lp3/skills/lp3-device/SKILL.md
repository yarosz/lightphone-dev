---
name: lp3-device
description: This skill should be used for any adb step on a Light Phone III (LP3, model TLP301) or a LightOS emulator, such as installing or launching a Tool, tapping, sending keys or text, taking screenshots, reading logcat, changing settings, measuring, or running device CI, and when the phone has dropped off adb or several agent sessions share one phone. Typical requests are "take a screenshot on the LP3", "tap through my Tool", "the phone dropped off adb" and "who has the phone".
---

# Drive an LP3 or LightOS emulator safely

The scripts below live in this skill's `scripts/` directory; run them by that path. Each one prints its
usage with `-h`. Device facts (keys, wireless adb, the USB drop, the emulator setup) are in the
lightphone-dev repo's [PLATFORM.md](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md); this
skill names its sections instead of repeating them.

Use fixed script files for device work, not compound adb one-liners: worktree-isolated agent sessions
refuse compound commands, and a script runs the same checks every time.

## Every session

1. **Find the device.** `scripts/lp3-find.sh --phone` prints the one LP3 (by model TLP301, USB or
   wireless) or fails. For an emulator, `scripts/lp3-find.sh --avd <avd>`; right after starting one, use
   `scripts/lp3-find.sh --avd <avd> --wait 300`, because a boot takes minutes. Done when it printed one
   serial. Pass that serial with `-s <serial>` on every adb call.
2. **Take the lease, if other sessions share the device.** See [references/sharing.md](references/sharing.md).
   Done when `scripts/lp3-lease.sh take "<holder>" "<purpose>" 15` printed your lease.
3. **Save every setting you will change**, to a file named for your package and holder, so two sessions
   on one package don't collide:
   `scripts/lp3-settings.sh <serial> save "$HOME/.cache/lp3-settings-<pkg>-<holder>" global:stay_on_while_plugged_in ...`.
4. **Drive input through the guard.** `scripts/lp3-drive.sh <serial> <pkg> launch|tap|swipe|key|text|shot|stop|wake`.
   It checks before every input that the device is awake, unlocked and showing `<pkg>`. If it is asleep
   or locked, run `wake` (rules below); for any other exit 3, ask the human for the action it names.
   Only input (tap, swipe, key, text, launch) goes through the guard. `adb install -r`, `uninstall`,
   `settings put`, `logcat` and `screencap` are plain `adb -s <serial> ...` calls once you hold the lease
   (if sharing) and step 1 found the device. A dozing phone may drop off adb, so run
   `scripts/lp3-guard.sh --pre-launch <serial> <pkg>` (awake and unlocked) before an install too.
5. **Leave it as found** (the checklist below), then release the lease. Done when every check passes and
   `scripts/lp3-lease.sh release "<holder>"` printed `LP3 free`.

## Rules

**Find the device, never assume it** (step 1). Never use `adb -d` (it stops finding the phone once it is
wireless), never take "the only device", and never run `adb kill-server` (it drops every session's
devices). An agent once assumed the wrong phone, and a CI run picked another session's emulator.

**When the phone is missing, look before blaming the cable.** In order:
1. `adb devices -l`: is it there as `adb-<serial>-<suffix>._adb-tls-connect._tcp`? Ask any other
   session sharing it whether they moved it to wireless.
2. Read the host's USB state (macOS: `ioreg -r -c AppleHPMInterfaceType10 -l`; Linux: `lsusb`). If it
   flaps with `TransportsActive = ("CC")` only, ask the human to plug it into a charger briefly, then
   back into the host (PLATFORM.md, "Driving devices from scripts").
3. `scripts/lp3-find.sh --phone --wait 600` ends as soon as adb sees it again. No blind retries.
4. When it is back, use the serial `lp3-find.sh --phone` printed from then on. It may have changed, for
   example from the USB serial to the wireless entry.

An agent once blamed the cable while another session had moved the phone to wireless.

**Guard every input** (step 4). The guard reads `dumpsys power` (Awake), the keyguard state from both
`dumpsys window policy` and `dumpsys activity activities` (it needs `isKeyguardShowing=false` as proof,
so unfamiliar output is unsafe), and the global `dumpsys window displays` mCurrentFocus (a window whose
component is the `<pkg>` you passed, never NotificationShade or a keyguard; LightOS focus fails it for any
Tool's package). It reads only these live sections:
the full `dumpsys window` starts with a saved LAST ANR section whose focus may be stale. Call `scripts/lp3-guard.sh` yourself before any input
you send another way. Volume keys once landed on the LightOS home screen and may have zeroed the ringer;
a dozing phone failed CI three times; the guard pattern ran 184 focus checks with 0 misfires in one
project.

**Drive LightOS itself only when the human allows it.** For OS-level work (LightOS Settings, say), ask
first. Only after the human says yes, set `LP3_ALLOW_LIGHTOS=1` and pass `com.lightos` as `<pkg>`:
`LP3_ALLOW_LIGHTOS=1 scripts/lp3-drive.sh <serial> com.lightos shot|tap|swipe|key ...`. Without the
variable the guard exits 3 and sends nothing. With it, the guard still needs LightOS focused, awake and
unlocked. `key` refuses the sleep/wake keys it refuses for a Tool, and also the volume and mute keys
(VOLUME_UP, VOLUME_DOWN, VOLUME_MUTE, MUTE), in any spelling. `stop` refuses `com.lightos`.
- Take a `shot` and read the screen before every tap. LightOS has no Tool layout to rely on.
- LightOS Settings > Debug is off-limits: "service menu" restarts the phone, the "Android Dev Mode"
  toggle is USB debugging (turning it off drops adb), and leave OEM unlocking and "change launcher" alone
  (PLATFORM.md, "Getting adb on the phone").
- LightOS's text fields ignore `input text` and keyevents: tap its on-screen keys, located from a
  screenshot. Seen on a real LP3 (2026-10-11) in the eSIM activation-code field.
  For letters and spaces use `scripts/lightos-type.sh <serial> "<text>"` (needs `LP3_ALLOW_LIGHTOS=1`):
  one guarded tap per key, coordinates measured on the Messages compose keyboard (2026-10-11). Digits
  and punctuation are on the "123" layer and refused (exit 64); two spaces in a row type ". ".
- A setting changed through the LightOS UI bypasses `lp3-settings.sh` save and restore. Write down each
  one you change, with its old value, and set it back by hand before you finish.
- Never pass `com.lightos` while testing a Tool, or to recover a Tool that lost focus: `launch` the Tool
  again instead.

**Wake with `wake` if the owner allows it, then ask.** Waking and unlocking a phone is its owner's call:
a person may be using it. If they have allowed it and the guard says asleep or locked, run
`scripts/lp3-drive.sh <serial> <pkg> wake`: it sends WAKEUP and `wm dismiss-keyguard` only when needed,
then waits for the guard. If it exits 3 (a PIN or pattern keeps the phone locked, another window has
focus, or adb is gone), ask the human and don't run it again. Some harnesses (Claude Code's auto mode,
for one) may block waking over adb; then ask the human rather than work around it. Never press POWER,
SLEEP, SOFT_SLEEP, TV_POWER or ENDCALL: they can sleep the LP3 and drop adb. `lp3-drive.sh key` refuses
them, and WAKEUP, in any spelling.

**Read the lease, then ask.** A quiet logcat or an old install time doesn't mean the phone is free: a
person may be reading on it.

**Save settings to a file, restore them yourself** (step 3). `save` refuses to overwrite a file that
wasn't restored, and `restore` deletes keys that were unset (null) instead of writing 0. Examples:
`global:stay_on_while_plugged_in`, the grayscale filter `secure:accessibility_display_daltonizer_enabled`.
A killed run once lost the original stay-on value because it lived in a shell variable, and another
restored null as 0.

**Leave it as found** (step 5). At the end of every session:
- `scripts/lp3-drive.sh <serial> <pkg> stop`: force-stop your package only. Skip this when `<pkg>` is
  `com.lightos` (it refuses); restore by hand any LightOS setting you changed instead.
- Uninstall only probes you installed.
- `scripts/lp3-settings.sh <serial> restore "$HOME/.cache/lp3-settings-<pkg>-<holder>"`.
- `adb -s <serial> shell pm list packages` still lists your Tool and the stock Tools (one session's
  uninstall test removed Light's Weather Tool from a shared phone).
- Optional: hash the Tool's data file before and after an automated run.

**Never chain anything after `mise run emu`** (or any command that keeps the emulator attached): it
blocks until the emulator exits. Kill stale background chains before shutting an emulator down. A chained
CI once ran late against no emulator and posted a failing signoff after the passing one.

**In `adb devices | while read ...` loops, give each `adb shell` `</dev/null`**, or it swallows the rest
of the device list.

**Keep personal data out of output.** Filter logcat to your own tag and event names
(`adb -s <serial> logcat -s <TAG>`), drop JSON payloads from LightOS clients, and look at every screenshot
before sharing it. One screenshot showed the owner's phone number; a watcher printed a saved location.

**Check the device yourself before asking the human.** Read it first (`dumpsys`, `pm list packages`,
`getprop`, a screenshot). Ask only for what the scripts or the hardware can't do (an unlock after
`wake` failed, a replug, a reboot), and name the exact action. Across three projects, the human had to
correct agents nine times for asking about things they could have read themselves.

**For sleep or Doze tests, unplug and poll over wireless adb.** USB power and adb polling keep the phone
awake. Let it sleep on its own timeout; never press POWER to force it.

## Scripts

| Script | Does |
|---|---|
| `lp3-find.sh [--phone \| --avd <name>] [--wait <s>]` | Prints exactly one serial, or exits 1 (none) or 2 (several). |
| `lp3-guard.sh [--pre-launch] <serial> <pkg>` | Exit 0 if awake, unlocked and `<pkg>` focused (`com.lightos` counts only when passed as `<pkg>`, with `LP3_ALLOW_LIGHTOS=1`); exit 3 with the reason. `--pre-launch` still refuses a locked phone. |
| `lp3-drive.sh <serial> <pkg> <verb> ...` | Guarded `launch`, `tap`, `swipe`, `key`, `text`; unguarded `shot`, `stop`; `wake` wakes and unlocks (no PIN), exit 3 if it can't. |
| `lightos-type.sh <serial> "<text>"` | Types letters and spaces on LightOS's in-app keyboard (it ignores `input text`) by guarded taps; needs `LP3_ALLOW_LIGHTOS=1`; digits and punctuation exit 64. |
| `lp3-settings.sh <serial> save <file> <ns>:<key>... \| restore <file>` | Saves originals to a file; restores, deleting nulls. |
| `lp3-lease.sh take\|renew\|release\|show` | Turn-taking between sessions ([references/sharing.md](references/sharing.md)). |

The plugin's tests run every script against a fake adb: `../../tests/run.sh` (relative to this skill's
directory).
