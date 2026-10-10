# lp3: Claude Code skills for Light Phone III Tools

Five skills for an agent building a LightOS Tool for the Light Phone III. Each rule in them comes from
an incident in building three Tools; the incidents are in
[docs/what-went-wrong.md](https://github.com/yarosz/lightphone-dev/blob/main/docs/what-went-wrong.md),
and the platform facts the skills point to are in
[PLATFORM.md](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md).

## Install

```
/plugin marketplace add yarosz/lightphone-dev
/plugin install lp3@lightphone-dev
```

## Skills

| Skill | Use it for |
|---|---|
| `lp3-device` | Any adb step on an LP3 or LightOS emulator. Finds the device by model or AVD name, checks the phone is awake, unlocked and showing your Tool before every input, saves and restores settings, and takes turns when sessions share a phone. |
| `lp3-new-tool` | Starting a Tool, copying a sibling's setup, or bumping light-sdk. `check-tool.sh` checks the submodule tag, targetSdk, `serverPackage` and script permissions in the committed HEAD. |
| `lp3-measure` | Performance numbers on the LP3: build checks, harness rules, the splash trap, and `p90.py` for nearest-rank percentiles. |
| `lp3-release` | Cutting a release, the Tool Library submission (human-approved), and posts. |
| `lp3-prepublish` | Before a Tool repo, branch, export or device-CI evidence goes public. `prepublish-scan.sh` scans the tree and every commit. |

The scan and steps in `lp3-prepublish` work on any repo when you invoke the skill by name.

Scripts are bash (macOS and Linux) and Python 3; each prints its usage with `-h`. They need `adb` on
PATH; `check-tool.sh` uses `gh` when present.

## Tests

```
tests/run.sh
```

(relative to this plugin) runs every script against a fake `adb` (`tests/fake-adb/adb`) and fixture git repos. Nothing touches a
real device or emulator.

## Licence

MIT (see [LICENSE](LICENSE)).
