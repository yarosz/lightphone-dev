# shellcheck shell=bash
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
  # cloned from the local fixture, but committed with Light's URL, as a real Tool would be
  g -C "$t" config -f .gitmodules submodule.light-sdk.url https://github.com/lightphone/light-sdk
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

# tool/lighttool.toml wins over any other lighttool.toml in the tree (a/ sorts first)
make_tool "$WORK/twotoml"
mkdir -p "$WORK/twotoml/a"
printf 'serverPackage = "com.thelightphone.sdk.emulator"\n' > "$WORK/twotoml/a/lighttool.toml"
g -C "$WORK/twotoml" add -A; g -C "$WORK/twotoml" commit -m "an example toml elsewhere"
expect_exit 0 "tool/lighttool.toml is preferred" "$C" "$WORK/twotoml"
check "twotoml: checks tool/lighttool.toml" out_has "ok    tool/lighttool.toml has serverPackage"

# a light-sdk entry in .gitmodules without a path gives a reason, not a silent exit
mkdir -p "$WORK/nopath/tool"; g -C "$WORK/nopath" init
printf '[submodule "light-sdk"]\n\turl = https://github.com/lightphone/light-sdk\n' > "$WORK/nopath/.gitmodules"
printf 'serverPackage = "com.lightos"\n' > "$WORK/nopath/tool/lighttool.toml"
g -C "$WORK/nopath" add -A; g -C "$WORK/nopath" commit -m init
expect_exit 1 "light-sdk in .gitmodules without a path" "$C" "$WORK/nopath"
check "nopath: reason" out_has "has no path"

# serverPackage: exactly one real line, outside any """ string, set to com.lightos
make_tool "$WORK/twopkg"
printf 'serverPackage = "com.thelightphone.sdk.emulator"\n' >> "$WORK/twopkg/tool/lighttool.toml"
g -C "$WORK/twopkg" commit -am "a second serverPackage line"
expect_exit 1 "two serverPackage lines" "$C" "$WORK/twopkg"
check "twopkg: reason" out_has "serverPackage lines"
make_tool "$WORK/inblock"
printf '[tool]\nname = "Example"\nnotes = """\nserverPackage = "com.lightos"\n"""\n' > "$WORK/inblock/tool/lighttool.toml"
g -C "$WORK/inblock" commit -am "serverPackage only inside a multi-line string"
expect_exit 1 "serverPackage only inside a \"\"\" block" "$C" "$WORK/inblock"
check "inblock: reason" out_has '"""'

# targetSdk: comments are stripped first, and a value that isn't a literal number fails
make_tool "$WORK/commented"
printf 'ext["compileSdk"] = 36\n// ext["targetSdk"] = 34\next["targetSdk"] = libs.versions.target.get().toInt()\n' > "$WORK/commented/build.gradle.kts"
g -C "$WORK/commented" commit -am "commented-out literal"
expect_exit 1 "a commented-out targetSdk literal doesn't count" "$C" "$WORK/commented"
check "commented: can't parse" out_has "can't parse targetSdk"
make_tool "$WORK/blockcomment"
printf 'ext["compileSdk"] = 36\next["targetSdk"] = /* 34 */ 35\n' > "$WORK/blockcomment/build.gradle.kts"
g -C "$WORK/blockcomment" commit -am "block comment"
expect_exit 1 "a /* */ comment holding the SDK's number doesn't count" "$C" "$WORK/blockcomment"
check "blockcomment: 35 compared" out_has "targetSdk is 35"
make_tool "$WORK/expr"
printf 'targetSdk = 33 + 1\n' > "$WORK/expr/tool/build.gradle.kts"
g -C "$WORK/expr" commit -am "an expression"
expect_exit 1 "targetSdk as an expression" "$C" "$WORK/expr"
check "expr: can't parse" out_has "can't parse targetSdk"
make_tool "$WORK/trailing"
printf 'ext["compileSdk"] = 36\next["targetSdk"] = 34 // mirrors light-sdk\n' > "$WORK/trailing/build.gradle.kts"
g -C "$WORK/trailing" commit -am "trailing comment"
expect_exit 0 "a trailing comment after the literal is fine" "$C" "$WORK/trailing"

# the submodule URL must be Light's repo, exactly
for url in https://evil.example.com/lightphone/light-sdk https://github.com/lightphone/light-sdk-fork \
  https://github.com/attacker/lightphone/light-sdk; do
  make_tool "$WORK/url"
  g -C "$WORK/url" config -f .gitmodules submodule.light-sdk.url "$url"
  g -C "$WORK/url" commit -am "other url"
  expect_exit 1 "submodule URL $url refused" "$C" "$WORK/url"
  rm -rf "$WORK/url"
done
make_tool "$WORK/sshurl"
g -C "$WORK/sshurl" config -f .gitmodules submodule.light-sdk.url git@github.com:lightphone/light-sdk.git
g -C "$WORK/sshurl" commit -am "ssh url"
expect_exit 0 "git@github.com:lightphone/light-sdk.git accepted" "$C" "$WORK/sshurl"

# tag trust: offline a local tag passes with a warning; with gh the commit must be one of Light's tags
check "offline: local tag not verified warning" sh -c "$C '$WORK/good' | grep -q 'local tag, not verified against GitHub'"
v012=$(git -C "$sdk" rev-parse 'v0.1.2^{commit}') v020=$(git -C "$sdk" rev-parse 'v0.2.0^{commit}')
printf 'v0.1.2 %s\nv0.2.0 %s\nv0.10.0-rc1 %s\nnightly %s\n' "$v012" "$v020" "$v012" "$v012" > "$WORK/tags-current"
printf 'v0.1.2 %s\nv0.2.0 %s\nv0.3.0 %s\n' "$v012" "$v020" "$(printf 'f%.0s' $(seq 40))" > "$WORK/tags-ahead"
LP3_OFFLINE='' FAKE_GH_TAGS="$WORK/tags-current" PATH="$TESTS/fake-gh:$PATH" \
  expect_exit 0 "gh: at Light's newest tag" "$C" "$WORK/good"
check "gh: newest tag reported" out_has "ok    v0.2.0 is Light's newest tag"
check "gh: no local-tag warning" sh -c "! grep -q 'not verified' '$WORK/out'"
LP3_OFFLINE='' FAKE_GH_TAGS="$WORK/tags-ahead" PATH="$TESTS/fake-gh:$PATH" \
  expect_exit 1 "gh: behind Light's newest tag" "$C" "$WORK/good"
check "gh: names the newer tag" out_has "Light's newest tag is v0.3.0"
make_tool "$WORK/forged"
g -C "$WORK/forged/light-sdk" checkout main
g -C "$WORK/forged/light-sdk" tag -f v0.2.0
g -C "$WORK/forged" commit -am "sdk at an untagged commit, tagged locally"
LP3_OFFLINE='' FAKE_GH_TAGS="$WORK/tags-current" PATH="$TESTS/fake-gh:$PATH" \
  expect_exit 1 "gh: a local tag Light doesn't have" "$C" "$WORK/forged"
check "forged: reason" out_has "not at any of Light's tags"

mkdir -p "$WORK/empty"
expect_exit 64 "not a repo" "$C" "$WORK/empty"
expect_exit 0 "-h" "$C" -h

unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
