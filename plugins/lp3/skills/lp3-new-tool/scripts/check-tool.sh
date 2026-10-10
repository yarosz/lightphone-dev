#!/usr/bin/env bash
# Check a LightOS Tool repo's committed HEAD against the setup rules Light's builder depends on.
#
#   check-tool.sh [repo-dir]          # default: the current directory
#
# Fails, with a reason, when:
#   - light-sdk isn't a submodule whose committed URL is Light's repo (https://github.com/lightphone/
#     light-sdk or git@github.com:lightphone/light-sdk, .git optional);
#   - with gh installed and LP3_OFFLINE unset: the submodule commit isn't the commit of one of Light's
#     tags on GitHub, or that tag isn't Light's newest release tag. Offline (or gh missing, or the
#     listing fails) a tag in the initialised submodule is accepted with a warning: "local tag, not
#     verified against GitHub". Not at any tag fails either way;
#   - the Tool's targetSdk differs from the SDK's root targetSdk at that commit. Comments (//, #, and
#     /* */ on one line) are stripped first; a targetSdk set to anything but a literal number (or, in
#     a Tool module, rootProject.ext["targetSdk"]) fails with "can't parse targetSdk";
#   - the committed lighttool.toml (tool/lighttool.toml, else the first one found) doesn't have exactly
#     one serverPackage line, outside any """ string, saying serverPackage = "com.lightos";
#   - a committed scripts/*.sh isn't executable.
# Warns when tool/build.gradle.kts has no ML Kit exclude block (fine if the Tool uses the QR scanner).
#
# It reads committed files only (git show HEAD:...), because Light builds from a commit. Commit first.
# Exit 0 = all checks pass. 1 = at least one failure. 64 = not a git repo, or usage.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -le 1 ] || { usage >&2; exit 64; }
repo="${1:-.}"
git -C "$repo" rev-parse --verify -q HEAD >/dev/null || { echo "not a git repo with a commit: $repo" >&2; exit 64; }

failures=0
ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failures=$((failures + 1)); }
warn() { echo "warn  $*"; }
show() { git -C "$repo" show "HEAD:$1" 2>/dev/null; }

strip_comments() { sed -E -e 's#/\*.*\*/##g' -e 's#//.*$##' -e 's/#.*$//'; }
# target_sdks: for each line that sets targetSdk (targetSdk = 34, ext["targetSdk"] = 34, the SDK's own
# form, targetSdkVersion 34, targetSdk.set(34), targetSdk = "34" in a TOML catalog) print the number, or
# ?<line> when the value isn't a literal number. A Tool module mirroring the root
# (rootProject.ext["targetSdk"] as Int) prints nothing: the root's literal is what's compared.
target_sdks() {
  local line rhs
  local assign='targetSdk(Version)?"?]?[[:space:]]*(=|\(|\.set\(|[[:space:]])[[:space:]]*(.*)$'
  local literal='^"?([0-9]+)"?[[:space:])}]*$'
  local mirror='^rootProject\.(ext|extra)\["targetSdk"\]( as Int)?[[:space:])}]*$'
  while IFS= read -r line; do
    [[ $line =~ $assign ]] || continue
    rhs="${BASH_REMATCH[3]}"
    if [[ $rhs =~ $literal ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ $rhs =~ $mirror ]]; then :
    else echo "?$line"; fi
  done
}

# --- light-sdk submodule at a tag
sdk_path="" sdk_sha="" sdk_tag="" sdk_entry="" light_tags=""
light_url='^(https://github\.com/|git@github\.com:)lightphone/light-sdk(\.git)?/?$'
while read -r key url; do
  if [[ $url =~ $light_url ]]; then
    sdk_entry="${key%.url}"
    sdk_path=$(git -C "$repo" config --blob HEAD:.gitmodules "$sdk_entry.path" || true)
  fi
done < <(git -C "$repo" config --blob HEAD:.gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)

if [ -n "$sdk_entry" ] && [ -z "$sdk_path" ]; then
  fail "$sdk_entry in the committed .gitmodules points at light-sdk but has no path"
elif [ -z "$sdk_path" ]; then
  fail "no light-sdk submodule in the committed .gitmodules (add https://github.com/lightphone/light-sdk)"
else
  sdk_sha=$(git -C "$repo" ls-tree HEAD -- "$sdk_path" | awk '$2 == "commit" { print $3 }')
  if [ -z "$sdk_sha" ]; then
    fail "$sdk_path is in .gitmodules but not committed as a submodule"
  else
    local_tag=""
    if [ -e "$repo/$sdk_path/.git" ]; then
      local_tag=$(git -C "$repo/$sdk_path" tag --points-at "$sdk_sha" | sed -n 1p)
    fi
    # Light's tags as "<name> <commit sha>": a local tag alone can be made by anyone
    if [ -z "${LP3_OFFLINE:-}" ] && command -v gh >/dev/null; then
      light_tags=$(gh api --paginate repos/lightphone/light-sdk/tags \
        --jq '.[] | "\(.name) \(.commit.sha)"' 2>/dev/null) || light_tags=""
    fi
    if [ -n "$light_tags" ]; then
      sdk_tag=$(awk -v s="$sdk_sha" '$2 == s { print $1 }' <<<"$light_tags" | sort -V | tail -n 1)
      if [ -n "$sdk_tag" ]; then
        ok "light-sdk at tag $sdk_tag, one of Light's tags on GitHub ($sdk_sha)"
      else
        fail "light-sdk commit $sdk_sha is not at any of Light's tags on GitHub${local_tag:+ (the local tag $local_tag is not one)}"
      fi
    elif [ -n "$local_tag" ]; then
      sdk_tag="$local_tag"
      ok "light-sdk at tag $sdk_tag ($sdk_sha)"
      warn "local tag, not verified against GitHub (needs gh and network; LP3_OFFLINE is set, gh is missing, or listing Light's tags failed)"
    else
      fail "light-sdk commit $sdk_sha is not at a tag (or the submodule isn't initialised: git submodule update --init)"
    fi
  fi
fi

# --- newest tag (needs Light's tag list)
if [ -n "$sdk_tag" ]; then
  if [ -z "$light_tags" ]; then
    echo "skip  newest-tag check (needs gh and network; LP3_OFFLINE is set, gh is missing, or listing failed)"
  else
    newest=$(awk '{ print $1 }' <<<"$light_tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1) || newest=""
    if [ -z "$newest" ]; then
      echo "skip  newest-tag check (no release tags in Light's list)"
    elif awk -v n="$newest" -v s="$sdk_sha" '$1 == n && $2 == s { f = 1 } END { exit !f }' <<<"$light_tags"; then
      ok "$newest is Light's newest tag"
    else
      fail "light-sdk is at $sdk_tag but Light's newest tag is $newest: bump it in its own PR"
    fi
  fi
fi

# --- targetSdk mirrors the SDK's root build file
tool_lines=$(for f in build.gradle.kts build.gradle tool/build.gradle.kts gradle/libs.versions.toml; do
  show "$f" || true; done | strip_comments | target_sdks)
sdk_lines=""
if [ -n "$sdk_sha" ] && [ -e "$repo/$sdk_path/.git" ]; then
  sdk_lines=$(for f in build.gradle.kts build.gradle gradle/libs.versions.toml; do
    git -C "$repo/$sdk_path" show "$sdk_sha:$f" 2>/dev/null || true; done | strip_comments | target_sdks)
fi
tool_bad=$(sed -n 's/^?//p' <<<"$tool_lines" | sed -n 1p)
sdk_bad=$(sed -n 's/^?//p' <<<"$sdk_lines" | sed -n 1p)
tool_targets=$(grep -E '^[0-9]+$' <<<"$tool_lines" | sort -u || true)
sdk_targets=$(grep -E '^[0-9]+$' <<<"$sdk_lines" | sort -u || true)
if [ -n "$tool_bad" ]; then
  fail "can't parse targetSdk in the Tool's build files ($tool_bad); check it against the SDK by hand"
elif [ -z "$tool_targets" ]; then
  fail "no literal targetSdk in build.gradle.kts, tool/build.gradle.kts or gradle/libs.versions.toml; check it against the SDK by hand"
elif [ "$(printf '%s\n' "$tool_targets" | wc -l)" -gt 1 ]; then
  fail "several targetSdk values in the Tool's build files: $(echo "$tool_targets" | tr '\n' ' ')"
elif [ -n "$sdk_bad" ]; then
  fail "can't parse targetSdk in the SDK's root build files ($sdk_bad); check by hand"
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
# tool/lighttool.toml is where Light's builder reads it; search the tree only when it isn't there.
if git -C "$repo" cat-file -e HEAD:tool/lighttool.toml 2>/dev/null; then
  toml=tool/lighttool.toml
else
  toml=$(git -C "$repo" ls-tree -r --name-only HEAD | grep -E '(^|/)lighttool\.toml$' | sed -n 1p || true)
fi
if [ -z "$toml" ]; then
  fail "no committed lighttool.toml"
else
  # serverPackage lines: how many, how many inside a """ multi-line string, and the one outside
  pkg=$(show "$toml" | awk '
    /^[[:space:]]*serverPackage[[:space:]]*=/ { total++; if (inblock) inside++; else line = $0 }
    gsub(/"""/, "&") % 2 == 1 { inblock = !inblock }
    END { printf "%d %d\n%s\n", total, inside, line }')
  read -r pkg_total pkg_inside <<<"$(sed -n 1p <<<"$pkg")"
  pkg_line=$(sed -n 2p <<<"$pkg")
  pkg_re='^[[:space:]]*serverPackage[[:space:]]*=[[:space:]]*"com\.lightos"[[:space:]]*(#.*)?$'
  if [ "$pkg_inside" -gt 0 ]; then
    fail "$toml has a serverPackage line inside a \"\"\" string; commit one real serverPackage = \"com.lightos\""
  elif [ "$pkg_total" -ne 1 ]; then
    fail "$toml has $pkg_total serverPackage lines; it must have exactly one, serverPackage = \"com.lightos\""
  elif [[ $pkg_line =~ $pkg_re ]]; then
    ok "$toml has serverPackage = \"com.lightos\""
  else
    fail "$toml must commit serverPackage = \"com.lightos\" (swap it only inside the emulator build wrapper)"
  fi
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
