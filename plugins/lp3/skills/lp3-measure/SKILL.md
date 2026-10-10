---
name: lp3-measure
description: This skill should be used when measuring a LightOS Tool's performance on a Light Phone III (open or launch time, frame rate, engine speed, memory) or when deciding go or no-go on performance numbers. Typical requests are "how fast does my Tool open on the LP3", "get P90 open times" and "is this fast enough to ship".
---

# Measure performance on the LP3

Drive the phone with the lp3-device skill (find, lease, guard, settings). Reference numbers and the
splash, frame-rate and debug-build facts are in the lightphone-dev repo's PLATFORM.md, "Measuring
performance" and "Rendering and frame rate"
([GitHub](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md#measuring-performance)).
light-reader's `scripts/perf.sh` is a working harness to copy.

## Steps

1. **Measure on the LP3.** Use the emulator only to check that a harness runs; its numbers come from the
   host's CPU and the Roboto font, so never decide on them.
2. **Check the build, then prepare it.** No sample counts until each line passes:
   ```sh
   # pass: no DEBUGGABLE in pkgFlags
   adb -s <serial> shell dumpsys package <pkg> | grep pkgFlags
   # pass: the broadcast prints result=1 (profile written)
   adb -s <serial> shell am broadcast -a androidx.profileinstaller.action.INSTALL_PROFILE -n <pkg>/androidx.profileinstaller.ProfileInstallReceiver
   # pass: prints Success
   adb -s <serial> shell cmd package compile -f -m speed-profile <pkg>
   # optional: shows speed-profile
   adb -s <serial> shell dumpsys package <pkg> | grep -A2 'Dexopt state'
   ```
   Any other broadcast result is one of profileinstaller's documented codes; look it up before going
   on. Compare release with release on the same phone. A debug build ran an engine 3.6× slower, and a debug
   build left on the phone by CI made the owner think the Tool was slow (4.7 s against 0.13 s).
3. **Instrument the app.** One logcat tag, batched lines, and log keys frozen once a script parses them
   (`open_ms=123`).
4. **Write the harness.**
   - A fresh process per sample, through the guard:
     `../lp3-device/scripts/lp3-drive.sh <serial> <pkg> stop`, then
     `../lp3-device/scripts/lp3-drive.sh <serial> <pkg> launch <activity>` (paths relative to this
     skill's directory). Run `adb -s <serial> logcat -c` before each sample.
   - n ≥ 10, and 20 for opens. Drop warm-up samples for frame intervals.
   - Every poll has a deadline.
   - Report P50 and P90 with `scripts/p90.py` (nearest rank), plus the thread, cores, thermal status and
     heap where they matter (`dumpsys thermalservice`, `dumpsys meminfo <pkg>`).
5. **Dry-run the harness against a fake adb first.** A logcat filter once hid the script's own lines and
   the harness hung. The plugin's fake adb, `../../tests/fake-adb/adb` (relative to this skill's
   directory), is a stub to start from.
6. **Time from a tap after launch, not from launch.** The SDK's splash holds drawing for the first
   1,000 ms, so every scripted open read about 0.95 s until a Perfetto trace showed why.
7. **Distrust a flat number.** Identical results across different inputs mean the harness is timing a
   floor. Find it (Perfetto plus `trace_processor`), fix it, drop the old tables, measure again. A finding
   that lazy parsing saved nothing was retracted after the splash fix: parsing was 85-90% of a long open.
8. **Restore settings.** Save any setting the harness changes with
   `../lp3-device/scripts/lp3-settings.sh` before
   the run, and restore it after.
9. **Run every UI-driving script at every milestone**, even when nobody needs its numbers that week. A
   perf script broke silently when the UI changed and stayed broken for a milestone.

Done when each reported number came from a non-debuggable build on the LP3, with n and P90 from
`p90.py`, and a flat result has been explained.

## p90.py

`scripts/p90.py [--key NAME] [--drop N] [FILE ...]` reads bare numbers or `key=value` log lines (logcat
lines as they are) from files or stdin and prints `n`, P50, P90, P99 and max per key. Percentiles are
nearest rank, `ceil(p × n)`, so each one is a real sample. `--drop N` drops each series' first N samples.

```sh
adb -s <serial> logcat -d -s <TAG> | scripts/p90.py --key open_ms --drop 1
```
