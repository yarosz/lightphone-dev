#!/usr/bin/env bash
# Check a LightOS Tool repo's committed HEAD against the setup rules Light's builder depends on.
#
#   check-tool.sh [repo-dir]          # default: the current directory
#
# Fails, with a reason, when:
#   - light-sdk isn't a submodule, or its committed commit isn't at a tag;
#   - with gh installed and LP3_OFFLINE unset, that tag isn't Light's newest release tag;
#   - the Tool's targetSdk differs from the SDK's root targetSdk at that commit (or can't be parsed);
#   - the committed lighttool.toml doesn't say serverPackage = "com.lightos";
#   - a committed scripts/*.sh isn't executable.
# Warns when tool/build.gradle.kts has no ML Kit exclude block (fine if the Tool uses the QR scanner).
#
# It reads committed files only (git show HEAD:...), because Light builds from a commit. Commit first.
# Exit 0 = all checks pass. 1 = at least one failure. 64 = not a git repo, or usage.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -le 1 ] || { usage >&2; exit 64; }
repo="${1:-.}"
git -C "$repo" rev-parse --verify -q HEAD >/dev/null || { echo "not a git repo with a commit: $repo" >&2; exit 64; }

failures=0
ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failures=$((failures + 1)); }
warn() { echo "warn  $*"; }
show() { git -C "$repo" show "HEAD:$1" 2>/dev/null; }

# targetSdk values in build files' text, one per line, de-duplicated. Matches targetSdk = 34,
# ext["targetSdk"] = 34 (the SDK's own form), targetSdkVersion 34 and targetSdk = "34" in a TOML catalog.
target_sdks() {
  grep -Eo 'targetSdk(Version)?"?]?[[:space:]]*(=|\(|\.set\()?[[:space:]]*"?[0-9]+' | grep -Eo '[0-9]+$' | sort -u || true
}

# --- light-sdk submodule at a tag
sdk_path="" sdk_sha="" sdk_tag=""
while read -r key url; do
  case "$url" in
    *lightphone/light-sdk*) sdk_path=$(git -C "$repo" config --blob HEAD:.gitmodules "${key%.url}.path") ;;
  esac
done < <(git -C "$repo" config --blob HEAD:.gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)

if [ -z "$sdk_path" ]; then
  fail "no light-sdk submodule in the committed .gitmodules (add github.com/lightphone/light-sdk)"
else
  sdk_sha=$(git -C "$repo" ls-tree HEAD -- "$sdk_path" | awk '$2 == "commit" { print $3 }')
  if [ -z "$sdk_sha" ]; then
    fail "$sdk_path is in .gitmodules but not committed as a submodule"
  else
    if [ -e "$repo/$sdk_path/.git" ]; then
      sdk_tag=$(git -C "$repo/$sdk_path" tag --points-at "$sdk_sha" | sed -n 1p)
    fi
    if [ -z "$sdk_tag" ] && [ -z "${LP3_OFFLINE:-}" ] && command -v gh >/dev/null; then
      sdk_tag=$(gh api --paginate repos/lightphone/light-sdk/tags \
        --jq ".[] | select(.commit.sha == \"$sdk_sha\") | .name" 2>/dev/null | sed -n 1p) || sdk_tag=""
    fi
    if [ -n "$sdk_tag" ]; then
      ok "light-sdk at tag $sdk_tag ($sdk_sha)"
    else
      fail "light-sdk commit $sdk_sha is not at a tag (or the submodule isn't initialised: git submodule update --init)"
    fi
  fi
fi

# --- newest tag (optional)
if [ -n "$sdk_tag" ]; then
  if [ -n "${LP3_OFFLINE:-}" ] || ! command -v gh >/dev/null; then
    echo "skip  newest-tag check (needs gh and network; LP3_OFFLINE is set or gh is missing)"
  else
    newest=$(gh api --paginate repos/lightphone/light-sdk/tags --jq '.[].name' 2>/dev/null \
      | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) || newest=""
    if [ -z "$newest" ]; then
      echo "skip  newest-tag check (couldn't list Light's tags)"
    elif [ "$newest" = "$sdk_tag" ]; then
      ok "$sdk_tag is Light's newest tag"
    else
      fail "light-sdk is at $sdk_tag but Light's newest tag is $newest: bump it in its own PR"
    fi
  fi
fi

# --- targetSdk mirrors the SDK's root build file
tool_targets=$(for f in build.gradle.kts build.gradle tool/build.gradle.kts gradle/libs.versions.toml; do
  show "$f" || true; done | target_sdks)
sdk_targets=""
if [ -n "$sdk_sha" ] && [ -e "$repo/$sdk_path/.git" ]; then
  sdk_targets=$(for f in build.gradle.kts build.gradle gradle/libs.versions.toml; do
    git -C "$repo/$sdk_path" show "$sdk_sha:$f" 2>/dev/null || true; done | target_sdks)
fi
if [ -z "$tool_targets" ]; then
  fail "no literal targetSdk in build.gradle.kts, tool/build.gradle.kts or gradle/libs.versions.toml; check it against the SDK by hand"
elif [ "$(printf '%s\n' "$tool_targets" | wc -l)" -gt 1 ]; then
  fail "several targetSdk values in the Tool's build files: $(echo "$tool_targets" | tr '\n' ' ')"
elif [ -z "$sdk_targets" ]; then
  fail "couldn't read the SDK's root targetSdk at $sdk_sha (submodule not initialised, or its build file changed shape); check by hand"
elif [ "$(printf '%s\n' "$sdk_targets" | wc -l)" -gt 1 ]; then
  fail "several targetSdk values in the SDK's root build files: $(echo "$sdk_targets" | tr '\n' ' '); check by hand"
elif [ "$tool_targets" = "$sdk_targets" ]; then
  ok "targetSdk $tool_targets matches the SDK"
else
  fail "targetSdk is $tool_targets but the SDK's root build says $sdk_targets: Light's builder would test a different APK"
fi

# --- serverPackage
toml=$(git -C "$repo" ls-tree -r --name-only HEAD | grep -E '(^|/)lighttool\.toml$' | sed -n 1p || true)
if [ -z "$toml" ]; then
  fail "no committed lighttool.toml"
elif show "$toml" | grep -Eq '^[[:space:]]*serverPackage[[:space:]]*=[[:space:]]*"com\.lightos"[[:space:]]*(#.*)?$'; then
  ok "$toml has serverPackage = \"com.lightos\""
else
  fail "$toml must commit serverPackage = \"com.lightos\" (swap it only inside the emulator build wrapper)"
fi

# --- scripts are executable
not_exec=$(git -C "$repo" ls-tree HEAD scripts/ 2>/dev/null | awk '$4 ~ /\.sh$/ && $1 != "100755" { print $4 }')
if [ -n "$not_exec" ]; then
  fail "not executable in the commit (chmod +x, then commit): $(echo "$not_exec" | tr '\n' ' ')"
else
  ok "scripts/*.sh are executable"
fi

# --- ML Kit exclude block (warning only)
if show tool/build.gradle.kts | grep -Fq 'exclude(group = "com.google.mlkit")'; then
  ok "ML Kit exclude block present"
else
  warn "no ML Kit exclude block in tool/build.gradle.kts: if the Tool never calls the QR scanner, add the six excludes from PLATFORM.md (about 22 MB)"
fi

[ "$failures" -eq 0 ] || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
