---
name: lp3-new-tool
description: This skill should be used when creating a new LightOS Tool (a Light Phone III app built with Light's light-sdk), copying another Tool's build setup into a repo, or bumping a Tool's light-sdk version.
---

# Start or re-base a LightOS Tool

Platform facts are in the lightphone-dev repo's PLATFORM.md ([relative](../../../../PLATFORM.md),
[GitHub](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md)). Templates named below are in
its `templates/` folder ([GitHub](https://github.com/yarosz/lightphone-dev/tree/main/templates)).
`scripts/check-tool.sh` is in this skill's directory.

For an SDK bump, skip to [references/sdk-bump.md](references/sdk-bump.md).

## New Tool

0. **Read first.** PLATFORM.md, then Light's SDK README
   ([lightphone/light-sdk](https://github.com/lightphone/light-sdk)). Check what sibling Tools fixed
   lately (their merged PRs and PLATFORM.md's dated entries): a Tool once shipped about 22 MB of unused
   ML Kit until someone asked whether the fix was only in one sibling.
1. **Design before code.** Grill the product with domain-expert agents
   (`templates/domain-expert-brief.md`), then write `CONTEXT.md` (the glossary), ADRs for hard-to-reverse
   choices, and a decision log. Done when the rulings cover the first milestone and `CONTEXT.md` exists.
2. **Repo.** `git init -b main`, an empty signed first commit (`git commit -S --allow-empty -m init`),
   then work in worktrees. Give every builder subagent its own isolated worktree: a parent session pinned
   to a worktree blocks non-isolated children.
3. **light-sdk as a submodule at Light's newest tag**, cloned from GitHub (a local clone may lack the
   tag's commit):
   ```sh
   gh api repos/lightphone/light-sdk/tags --jq '.[0].name'          # newest tag, e.g. v0.2.0
   git submodule add https://github.com/lightphone/light-sdk light-sdk
   git -C light-sdk checkout <tag>
   gh api repos/lightphone/light-sdk/git/ref/tags/<tag> --jq .object.sha   # peel it if .object.type is "tag"
   git ls-tree HEAD light-sdk                                       # after committing: same commit
   ```
4. **Root targetSdk mirrors the SDK tag's root build file** (`ext["targetSdk"] = 34` on v0.2.0). Light's
   builder compiles `tool/build.gradle.kts` inside the SDK project, so a mismatch means your CI tests a
   different APK from the one Light signs. One release shipped at 36 while claiming to mirror the SDK.
5. **`serverPackage = "com.lightos"` committed** in `tool/lighttool.toml`. Build for the emulator only
   through a swap-and-restore wrapper (light-reader `scripts/emulator-build.sh`). Guard the string in
   three places: the wrapper's grep after it restores the file, `grep -qx` in the builder rehearsal, and a
   unit test that reads `lighttool.toml`. Once a tagged SDK includes light-sdk #234, the plugin fails on
   any other value unless `-DlightSdk.allowAltServerPackage=true` is passed, which emulator builds then
   need.
6. **No QR scanner?** Add the six-group exclude block from PLATFORM.md ("Build plugin rules") to
   `tool/build.gradle.kts`, rerun the builder rehearsal, and never call the scanner afterwards (it would
   crash).
7. **Copy from a sibling Tool** ([light-reader](https://github.com/yarosz/light-reader),
   [light-chess](https://github.com/yarosz/light-chess)): build files, `mise.toml`, the UI driver task,
   `scripts/ci.sh`, `scripts/light-build.sh`, `scripts/emulator-build.sh`, `scripts/domain-drift.sh`,
   `.github/`. Then rename every identifier (`grep -ri <sibling-name>` returns nothing), fix drift checks
   that point at files you don't have, and `chmod +x scripts/*.sh` (a copy once lost the exec bits).
8. **Your own emulator AVD**, from light-chess `scripts/emulator/RECIPE.md`, on the next free even port:
   LightOS emulator as a system app, 480 dpi, gesture navigation, and on the v0.2.0 emulator Allowed tools
   set to "All Tools". mise on a fresh Mac: point `AVDMANAGER_OPTS` at `cmdline-tools/latest`, and set
   `task.run_auto_install=false` when a parent directory pins tools.
9. **Ledger** from `templates/ledger-handoff.md`, with a done-when on every item. Keep a private ledger
   outside the repo for devices, accounts and anything personal.
10. **Gates**: unit tests, the builder rehearsal (`scripts/light-build.sh`) on a committed HEAD, and CI
    with device signoffs.

Done when `scripts/check-tool.sh <repo>` prints `all checks passed`.

## check-tool.sh

`scripts/check-tool.sh [repo]` reads the committed HEAD (Light builds from a commit, so commit first) and
fails, with a reason, when:
- light-sdk isn't a submodule at an exact tag;
- the tag isn't Light's newest (only with `gh` installed; set `LP3_OFFLINE=1` to skip);
- the Tool's targetSdk differs from the SDK's root targetSdk at that commit, or either can't be parsed;
- `lighttool.toml` doesn't commit `serverPackage = "com.lightos"` exactly;
- a committed `scripts/*.sh` isn't executable.

It warns when the ML Kit exclude block is missing. Run it before every release and after every SDK bump.
