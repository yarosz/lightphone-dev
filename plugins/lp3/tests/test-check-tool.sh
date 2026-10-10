# Tests for check-tool.sh against fixture repos built in a temp directory. Sourced by run.sh.
C="$SKILLS/lp3-new-tool/scripts/check-tool.sh"

# Isolate the fixture repos from the user's git config (signing, hooks, templates).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
g() { git -c init.defaultBranch=main -c protocol.file.allow=always "$@" >/dev/null 2>&1; }

new_state
sdk="$WORK/lightphone/light-sdk"
mkdir -p "$sdk"
g -C "$sdk" init
printf 'ext["compileSdk"] = 36\next["targetSdk"] = 36\n' > "$sdk/build.gradle.kts"
g -C "$sdk" add -A; g -C "$sdk" commit -m old; g -C "$sdk" tag v0.1.2
printf 'ext["compileSdk"] = 36\next["targetSdk"] = 34\n' > "$sdk/build.gradle.kts"
g -C "$sdk" commit -am new; g -C "$sdk" tag -a v0.2.0 -m v0.2.0
printf 'more\n' > "$sdk/NOTES"; g -C "$sdk" add -A; g -C "$sdk" commit -m untagged

# make_tool <dir>: a Tool repo that passes every check, with light-sdk at v0.2.0
make_tool() {
  local t="$1"
  mkdir -p "$t/tool" "$t/scripts"
  g -C "$t" init
  g -C "$t" submodule add "$sdk" light-sdk
  g -C "$t/light-sdk" checkout v0.2.0
  printf 'ext["compileSdk"] = 36\next["targetSdk"] = 34\n' > "$t/build.gradle.kts"
  printf 'targetSdk = rootProject.ext["targetSdk"] as Int\nconfigurations.configureEach {\n    exclude(group = "com.google.mlkit")\n}\n' > "$t/tool/build.gradle.kts"
  printf '[tool]\nname = "Example"\nserverPackage = "com.lightos"\n' > "$t/tool/lighttool.toml"
  printf '#!/bin/sh\n' > "$t/scripts/ci.sh"; chmod +x "$t/scripts/ci.sh"
  g -C "$t" add -A; g -C "$t" commit -m init
}

make_tool "$WORK/good"
expect_exit 0 "a correct Tool passes" "$C" "$WORK/good"
check "good: tag reported" out_has "light-sdk at tag v0.2.0"
check "good: targetSdk matches" out_has "targetSdk 34 matches"
check "good: newest-tag check skipped offline" out_has "skip  newest-tag"

make_tool "$WORK/untagged"
g -C "$WORK/untagged/light-sdk" checkout main
g -C "$WORK/untagged" commit -am "sdk to an untagged commit"
expect_exit 1 "submodule not at a tag" "$C" "$WORK/untagged"
check "untagged: reason" out_has "is not at a tag"

make_tool "$WORK/oldsdk"
g -C "$WORK/oldsdk/light-sdk" checkout v0.1.2
g -C "$WORK/oldsdk" commit -am "old sdk"
expect_exit 1 "old SDK with targetSdk 34 mismatches its 36" "$C" "$WORK/oldsdk"
check "oldsdk: at tag v0.1.2" out_has "tag v0.1.2"
check "oldsdk: targetSdk reason" out_has "targetSdk is 34 but the SDK's root build says 36"

make_tool "$WORK/target36"
sed -i.bak 's/= 34/= 36/' "$WORK/target36/build.gradle.kts"; rm "$WORK/target36/build.gradle.kts.bak"
g -C "$WORK/target36" commit -am "target 36"
expect_exit 1 "targetSdk 36 on SDK v0.2.0" "$C" "$WORK/target36"

make_tool "$WORK/uncommitted"
sed -i.bak 's/= 34/= 36/' "$WORK/uncommitted/build.gradle.kts"; rm "$WORK/uncommitted/build.gradle.kts.bak"
expect_exit 0 "uncommitted edits are ignored (Light builds the commit)" "$C" "$WORK/uncommitted"

make_tool "$WORK/emu"
sed -i.bak 's/com.lightos/com.thelightphone.sdk.emulator/' "$WORK/emu/tool/lighttool.toml"; rm "$WORK/emu/tool/lighttool.toml.bak"
g -C "$WORK/emu" commit -am "emulator package committed"
expect_exit 1 "emulator serverPackage committed" "$C" "$WORK/emu"
check "emu: reason" out_has 'must commit serverPackage = "com.lightos"'

make_tool "$WORK/prefix"
sed -i.bak 's/"com.lightos"/"com.lightos.extra"/' "$WORK/prefix/tool/lighttool.toml"; rm "$WORK/prefix/tool/lighttool.toml.bak"
g -C "$WORK/prefix" commit -am "near miss"
expect_exit 1 "serverPackage must be exactly com.lightos" "$C" "$WORK/prefix"

make_tool "$WORK/noexec"
printf '#!/bin/sh\n' > "$WORK/noexec/scripts/light-build.sh"
g -C "$WORK/noexec" add -A; g -C "$WORK/noexec" commit -m "copied without exec bit"
expect_exit 1 "script without exec bit" "$C" "$WORK/noexec"
check "noexec: names the script" out_has "scripts/light-build.sh"

make_tool "$WORK/nomlkit"
printf 'targetSdk = rootProject.ext["targetSdk"] as Int\n' > "$WORK/nomlkit/tool/build.gradle.kts"
g -C "$WORK/nomlkit" commit -am "no excludes"
expect_exit 0 "no ML Kit block only warns" "$C" "$WORK/nomlkit"
check "nomlkit: warning printed" out_has "warn  no ML Kit exclude block"

make_tool "$WORK/noparse"
printf 'ext["targetSdk"] = libs.versions.target.get().toInt()\n' > "$WORK/noparse/build.gradle.kts"
g -C "$WORK/noparse" commit -am "indirect targetSdk"
expect_exit 1 "targetSdk that can't be parsed fails with an explanation" "$C" "$WORK/noparse"
check "noparse: says check by hand" out_has "check it against the SDK by hand"

mkdir -p "$WORK/nosdk/tool"; g -C "$WORK/nosdk" init
printf 'serverPackage = "com.lightos"\n' > "$WORK/nosdk/tool/lighttool.toml"
g -C "$WORK/nosdk" add -A; g -C "$WORK/nosdk" commit -m init
expect_exit 1 "no submodule" "$C" "$WORK/nosdk"
check "nosdk: reason" out_has "no light-sdk submodule"

mkdir -p "$WORK/empty"
expect_exit 64 "not a repo" "$C" "$WORK/empty"
expect_exit 0 "-h" "$C" -h

unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
