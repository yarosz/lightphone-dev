---
name: lp3-release
description: This skill should be used when cutting a release of a LightOS Tool, posting publicly about a Tool, or submitting a Tool build to Light's Tool Library. Typical requests are "cut a release of my Tool", "tag v1.2.0" and "submit the build to the Tool Library".
---

# Release a LightOS Tool

The human drives the outward steps; agents prepare, check and draft. Tool Library and versioning facts
are in the lightphone-dev repo's PLATFORM.md, "Shipping through Light"
([GitHub](https://github.com/yarosz/lightphone-dev/blob/main/PLATFORM.md#shipping-through-light)).

## Steps

1. **SDK check first.** Run `../lp3-new-tool/scripts/check-tool.sh <repo>` (relative to this skill's
   directory) with `gh` available. If light-sdk isn't at Light's newest tag, bump it in its own PR before
   the release. A release PR cut on the old SDK once had to be redone.
2. **Release branch.**
   - Bump `versionCode` above the newest Version in the Tool Library, and `versionName` to semver with no
     pre-release suffix. Assert both with a script, not by eye, for example:
     ```sh
     grep -Eq 'versionName = "[0-9]+\.[0-9]+\.[0-9]+"' tool/build.gradle.kts
     code=$(sed -nE 's/.*versionCode = ([0-9]+).*/\1/p' tool/build.gradle.kts); [ "$code" -gt <newest> ]
     ```
   - Signed commit, then a PR.
   - Run every check through the repo's toolchain (`mise exec -- ...`), so the pinned JDK and Gradle run.
   - Upgrade check on a phone or emulator, driven with the lp3-device skill:
     ```sh
     adb -s <serial> install <previous.apk>
     # create data in the Tool (through ../lp3-device/scripts/lp3-drive.sh)
     adb -s <serial> install -r <new.apk>
     # confirm the data is still there
     ```
   - Minified release build, the builder rehearsal on the committed HEAD, and CI with device signoffs.
3. **Merge and tag the merge commit**, not whatever `origin/main` points at by then:
   ```sh
   gh pr merge <n> --squash --match-head-commit <tested-sha>
   m=$(gh pr view <n> --json mergeCommit --jq .mergeCommit.oid)
   [ -n "$m" ] || { echo "no merge commit yet; wait and retry"; exit 1; }
   git fetch origin
   git rev-parse "$m^{tree}"             # must equal the next line
   git rev-parse "<tested-sha>^{tree}"
   ```
   If the two trees differ, stop: CI didn't test what merged. Otherwise:
   ```sh
   git tag -s v<version> "$m" -m v<version>
   git push origin v<version>
   gh release create v<version> --verify-tag --latest --notes-file <notes>
   ```
   Anything a post links to (a GIF, a screenshot) must exist at the tag. Before the repo or CI evidence
   goes public, use the lp3-prepublish skill.
4. **Release before any public post**, and at the end of every milestone. A post once went up with no
   release behind it, so readers couldn't find the build it described.
5. **Tool Library**, in Light's dashboard, by the human or by an agent with explicit approval.
   - Ask once, before any outward step, for approval covering the description, images, build note and
     the submit. Not a stop before each step.
   - Register: a title, the GitHub repo, a one-line description and one tag. The package name comes from
     `lighttool.toml` on the default branch and can't change later.
   - The description is limited to 255 characters; 256 fails silently (reported to Light). Count it
     before saving.
   - Images: up to 3, at least one. Raw LP3 screencaps work; look at each for personal data first.
   - "Submit build": the release commit's full SHA (`git rev-parse v<version>^{commit}`) and a one-line
     note linking the GitHub release.
   - Builds took 6-8 minutes. "Pending approval" is Light's review queue, not a result. Keep the host
     awake through long waits (macOS: `caffeinate -di`).
6. **Never install Light's signed build over a dev-signed one.** Each Tool has its own certificate, so
   switching means uninstalling first, which deletes the Tool's data. Plan it and tell the user before
   doing it.
7. **Posts come from the human, in their own words.** Light's AI policy for its repos asks that all
   communication there come from a person. Agents may draft; the human rewrites and posts.
8. **Update `RELEASING.md`** whenever the flow changes. Two repos' copies went stale.

Done when the tag is signed and pushed, the GitHub release is marked latest, any submission the human
approved shows its build, and `RELEASING.md` matches what you did.
