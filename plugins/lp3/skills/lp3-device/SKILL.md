---
name: lp3-device
description: This skill should be used for any adb step on a Light Phone III (LP3, model TLP301) or a LightOS emulator, such as installing or launching a Tool, tapping, sending keys or text, taking screenshots, reading logcat, changing settings, measuring, or running device CI, and when the phone has dropped off adb or several agent sessions share one phone.
---

# Drive an LP3 or LightOS emulator safely

The scripts below live in this skill's `scripts/` directory; run them by that path. Each one prints its
usage with `-h`. Device facts (keys, wireless adb, the USB drop, the emulator setup) are in the
lightphone-dev repo's PLATFORM.md ([relative](../../../../PLATFORM.md),
[GitHub](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md)); this skill links to its
sections by name instead of repeating them.

Use fixed script files for device work, not compound adb one-liners: worktree-isolated agent sessions
refuse compound commands, and a script runs the same checks every time.

## Every session

1. **Find the device.** `scripts/lp3-find.sh --phone` prints the one LP3 (by model TLP301, USB or
   wireless) or fails. For an emulator, `scripts/lp3-find.sh --avd <avd>`. Done when it printed one
   serial. Pass that serial with `-s <serial>` on every adb call.
2. **Take the lease, if other sessions share the device.** See [references/sharing.md](references/sharing.md).
   Done when `scripts/lp3-lease.sh take` printed your lease.
3. **Save every setting you will change**, to a file:
   `scripts/lp3-settings.sh <serial> save <file> global:stay_on_while_plugged_in ...`.
4. **Drive through the guard.** `scripts/lp3-drive.sh <serial> <pkg> launch|tap|swipe|key|text|shot|stop`.
   It checks before every input that the device is awake, unlocked and showing `<pkg>`. Exit 3 means
   stop and ask the human for the one action the guard names.
5. **Leave it as found.** Then release the lease. Done when every check in "Leave it as found" passes.

## Rules

**Find the device, never assume it.** Pick the phone by model and the emulator by AVD name, always
through `lp3-find.sh`. Never use `adb -d` (it stops finding the phone once it is wireless), never take
"the only device", and never run `adb kill-server` (it drops every session's devices). An agent once
assumed the wrong phone, and a CI run picked another session's emulator.

**When the phone is missing, look before blaming the cable.** In order:
1. `adb devices -l`: is it there as `adb-<serial>-<suffix>._adb-tls-connect._tcp`? Ask any other
   session sharing it whether they moved it to wireless.
2. Read the host's USB state (macOS: `ioreg -r -c AppleHPMInterfaceType10 -l`; Linux: `lsusb`). If it
   flaps with `TransportsActive = ("CC")` only, ask the human to plug it into a charger briefly, then
   back into the host (PLATFORM.md, "Driving devices from scripts").
3. `scripts/lp3-find.sh --phone --wait 600` ends as soon as adb sees it again. No blind retries.

An agent once blamed the cable while another session had moved the phone to wireless.

**Guard every input.** Before any tap, swipe, key, text or launch: `dumpsys power` mWakefulness is
Awake, no keyguard is showing, and `dumpsys window` mCurrentFocus names your package (not
NotificationShade, a keyguard, or `com.lightos`). `lp3-drive.sh` runs `lp3-guard.sh` for you; call the
guard yourself before any adb input you send another way. Screenshots and log reads need no guard. Volume
keys once landed on the LightOS home screen and may have zeroed the ringer; a dozing phone failed CI
three times; the guard pattern ran 184 focus checks with 0 misfires in one project.

**Leave waking and unlocking to the human.** When the guard fails, stop and ask the human to wake or
unlock the phone. Never press POWER (it sleeps the LP3 and drops adb) and never wake or unlock with key
events; `lp3-drive.sh key` refuses POWER, SLEEP and WAKEUP. Auto mode blocks waking over adb anyway.
`wm dismiss-keyguard` still unlocks a phone with no PIN, but don't build CI on it.

**Read the lease, then ask.** A quiet logcat or an old install time doesn't mean the phone is free: a
person may be reading on it.

**Save settings to a file, restore them yourself.** `lp3-settings.sh save` writes the originals to a file
and refuses to overwrite one that wasn't restored; `restore` deletes keys that were unset (null) instead
of writing 0. Examples: `global:stay_on_while_plugged_in`, the grayscale filter
`secure:accessibility_display_daltonizer_enabled`. A killed run once lost the original stay-on value
because it lived in a shell variable, and another restored null as 0.

**Leave it as found.** At the end of every session:
- `scripts/lp3-drive.sh <serial> <pkg> stop`: force-stop your package only.
- Uninstall only probes you installed.
- `scripts/lp3-settings.sh <serial> restore <file>`.
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
`getprop`, a screenshot). Ask only for what a guard or the hardware blocks (wake, unlock, replug, reboot),
and name the exact action. Across three projects, the human had to correct agents nine times for asking
about things they could have read themselves.

**For sleep or Doze tests, unplug and poll over wireless adb.** USB power and adb polling keep the phone
awake.

## Scripts

| Script | Does |
|---|---|
| `lp3-find.sh [--phone \| --avd <name>] [--wait <s>]` | Prints exactly one serial, or exits 1 (none) or 2 (several). |
| `lp3-guard.sh [--pre-launch] <serial> <pkg>` | Exit 0 if awake, unlocked and `<pkg>` focused; exit 3 with the reason. |
| `lp3-drive.sh <serial> <pkg> <verb> ...` | Guarded `launch`, `tap`, `swipe`, `key`, `text`; unguarded `shot`, `stop`. |
| `lp3-settings.sh <serial> save <file> <ns>:<key>... \| restore <file>` | Saves originals to a file; restores, deleting nulls. |
| `lp3-lease.sh take\|renew\|release\|show` | Turn-taking between sessions ([references/sharing.md](references/sharing.md)). |

The plugin's tests run every script against a fake adb: `plugins/lp3/tests/run.sh` in the
lightphone-dev repo.
