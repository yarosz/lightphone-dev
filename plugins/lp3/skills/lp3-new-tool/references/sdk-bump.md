# Bumping light-sdk

Do the bump in its own PR, before any release. A release PR cut on the old SDK once had to be redone.
What changed on v0.2.0 is in PLATFORM.md, "SDK v0.2.0"
([GitHub](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md#sdk-v020-tagged-2026-10-08)).

Every item ends on a check:

1. **Newest tag.** Read the tag's notes and merged PRs since your current tag.
   ```sh
   gh api --paginate repos/lightphone/light-sdk/tags --jq '.[].name' \
     | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
   ```
2. **Submodule commit.** `git -C light-sdk fetch --tags origin`, then `git -C light-sdk checkout <tag>`,
   and commit. Then `git ls-tree HEAD light-sdk` equals the tag's commit:
   ```sh
   git ls-remote https://github.com/lightphone/light-sdk 'refs/tags/<tag>' 'refs/tags/<tag>^{}'
   ```
   The `^{}` line, if present, is the commit (the tag is annotated); otherwise the only line is.
3. **Root targetSdk** equals the SDK's root `targetSdk`:
   `git -C light-sdk show <tag>:build.gradle.kts | grep targetSdk`.
4. **sdkVersion.** Match it; from v0.2.0 the plugin sets the `sdkVersion` manifest placeholder itself, so
   remove your own.
5. **API changes.** Build, and fix what broke (v0.2.0: `LightJobResult.Success(outputFilePath, message)`).
6. **Builder flags** in `scripts/light-build.sh` match the SDK's builder
   (v0.2.0: `-DlightSdk.unsigned=true -DlightSdk.abiFilters=arm64-v8a -DlightSdk.toolOnly=true`).
7. **Dependencies** are all in the SDK's `allowed-dependencies.txt`.
8. **Permissions** unchanged: compare the merged manifest's permissions before and after
   (`aapt2 dump permissions <apk>` or the build's merged manifest).
9. **Rehearsal.** The builder rehearsal passes on the committed HEAD.

Done when `scripts/check-tool.sh <repo>` (relative to this skill's directory) prints `all checks passed` with gh available, so
the newest-tag check runs.
