#!/usr/bin/env bash
# Scan a repo's files AND its whole git history for things that shouldn't go public, before you push it
# to a public remote or flip it to public. It is a best-effort net, not a verdict: it can't read
# compressed files or archives (.gz, .zip, .tar, .jar) or images, and it can't judge facts you've chosen
# not to publish. A reviewer still reads the repo before it goes public.
#
#   prepublish-scan.sh [repo-dir]
#
# Generic patterns are below. Your own private patterns (device serials, hostnames, family names, your
# employer) go in a file outside the repo, one extended regex per line (# starts a comment, CRLF line
# endings are fine), named by PREPUBLISH_PRIVATE_PATTERNS. That way the patterns are never committed.
#
# Scanned: tracked and untracked files (not ignored), the index, every commit on every ref, refs that
# point at a tree or a blob, commit messages, authors and committers, whole annotated-tag objects
# (tagger and full message), notes, every file name ever committed (merge commits included), tracked and
# untracked file names, and ref names. Binary files are scanned as text, so a NUL byte or a `binary`
# attribute can't hide one. Replacement objects (git replace) are ignored, so they can't hide a commit.
#
# The scanner holds its own patterns. At its paths (plugins/lp3/skills/lp3-prepublish/scripts/
# prepublish-scan.sh, and its older homes plugins/lp3/skills/prepublish/scripts/prepublish-scan.sh and
# scripts/prepublish-scan.sh) a matching line is skipped only when it is, verbatim, a line of the
# scanner you are running; every other line there is reported, in the working tree, the index and
# history alike, and the paths with skipped lines are printed. A line an older version had and this one
# doesn't is reported too: read it. If you vendor a copy elsewhere, list its path (a glob, relative to
# the repo root) in a file named by PREPUBLISH_EXCLUDE, one per line (# starts a comment); that path is
# then skipped in full. The active excludes are printed first.
#
# Exit 0 = no hits. Exit 1 = hits, printed as path:line:match (working tree, index), commit:path:line:match
# (history) or <where>:<what>:match (metadata). A hit isn't always a leak: read each one. Exit 64 = not a
# git repo, an unreadable patterns or exclude file, a pattern grep can't compile (it is named), or a
# search that failed: the scan never says clean when it couldn't search.
#
# What a regex can't catch: facts you've decided not to publish yet, or metadata inside images (EXIF,
# GPS). Those need a human or reviewer read, and a metadata stripper, not this script.
set -uo pipefail   # not -e: grep's "no match" exit status is the normal case here

case "${1:-}" in -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
repo="${1:-.}"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # before the cd: $0 may be relative
cd "$repo" || exit 64
export GIT_NO_REPLACE_OBJECTS=1   # a replacement object could otherwise stand in for a commit's content
# Outside a repo every git grep below fails, which must not read as "clean".
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo: $repo" >&2; exit 64; }
cd "$top" || exit 64   # pathspecs below are relative to the repo root

generic=(
  '/Users/[A-Za-z]'                   # macOS home paths
  '/home/[a-z]'                       # Linux home paths
  '/private/(tmp|var)/'               # macOS temp paths
  '\.claude/(jobs|projects)/'         # agent scratch and transcript paths
  '192\.168\.[0-9]{1,3}\.[0-9]{1,3}'  # LAN addresses
  # macOS git grep -E has no \b, so addresses are anchored with (^|[^0-9.]) instead.
  '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'  # Tailscale / CGNAT
  '[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}\.my\.local-ip\.co'
  '[A-Za-z0-9-]+\.ts\.net'            # Tailscale names
  '[A-Za-z0-9-]+\.local([^A-Za-z0-9-]|$)'  # mDNS host names
  '([0-9a-f]{2}:){5}[0-9a-f]{2}'      # MAC addresses
  'BEGIN [A-Z ]*PRIVATE KEY'
  'gh[pousr]_[A-Za-z0-9]{20,}'        # GitHub tokens
  'github_pat_[A-Za-z0-9_]{22,}'      # GitHub fine-grained tokens
  'xox[abposr]-[A-Za-z0-9-]{10,}'     # Slack tokens
  'sk-ant-[A-Za-z0-9_-]{10,}'         # Anthropic keys
  'sk-[A-Za-z0-9]{20,}'               # OpenAI-style keys
  'sk_(live|test)_[A-Za-z0-9]{10,}'   # Stripe keys
  'AIza[0-9A-Za-z_-]{30,}'            # Google API keys
  'AKIA[0-9A-Z]{16}'                  # AWS access keys
  'ops_[A-Za-z0-9]{20,}'              # 1Password service-account tokens
  'op://[^ ]+'                        # 1Password secret references
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'  # JWTs
  'Bearer [A-Za-z0-9._~+/=-]{16,}'    # bearer tokens
  'claude\.ai/code/session_[A-Za-z0-9]+'       # Claude session links
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'  # UUIDs (session and transcript ids)
)
# These two get the allowlist below, in a pass of their own. Every other pattern runs in a pass with no
# allowlist, so a token glued to an allowed address (ghp_...@example.com) is still caught by its own
# pattern.
allowable=(
  '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'  # email addresses
)
# Allowed MATCHES (not lines): the emulator's host addresses, bot/noreply addresses, and GitHub's shared
# SSH address (git@github.com).
allow='^[^0-9A-Za-z]?(10\.0\.2\.[0-9]+|noreply@anthropic\.com|noreply@github\.com|git@github\.com|[0-9]+\+?[A-Za-z0-9-]*@users\.noreply\.github\.com|[^@]+@example\.(com|org))$'

die() { echo "error: $*; the scan is incomplete, not clean" >&2; exit 64; }

patterns=("${generic[@]}")
if [ -n "${PREPUBLISH_PRIVATE_PATTERNS:-}" ]; then
  [ -r "$PREPUBLISH_PRIVATE_PATTERNS" ] || { echo "cannot read $PREPUBLISH_PRIVATE_PATTERNS" >&2; exit 64; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [ -n "$line" ] && [ "${line#\#}" = "$line" ] && patterns+=("$line")
  done < "$PREPUBLISH_PRIVATE_PATTERNS"
else
  echo "note: PREPUBLISH_PRIVATE_PATTERNS not set; scanning generic patterns only" >&2
fi
# A pattern grep can't compile would make every search below fail, which must not read as "no hits".
for p in "${patterns[@]}" "${allowable[@]}"; do
  grep -E -e "$p" </dev/null >/dev/null 2>&1
  [ $? -le 1 ] || { echo "bad pattern: $p" >&2; exit 64; }
done

own=(
  plugins/lp3/skills/lp3-prepublish/scripts/prepublish-scan.sh
  plugins/lp3/skills/prepublish/scripts/prepublish-scan.sh
  scripts/prepublish-scan.sh
)
own_excl=() user_excl=()
for o in "${own[@]}"; do
  own_excl+=(":(exclude,glob)$o"); echo "excluding: $o (except lines that aren't this scanner's)"
done
if [ -n "${PREPUBLISH_EXCLUDE:-}" ]; then
  [ -r "$PREPUBLISH_EXCLUDE" ] || { echo "cannot read $PREPUBLISH_EXCLUDE" >&2; exit 64; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\r'/}"
    [ -n "$line" ] && [ "${line#\#}" = "$line" ] || continue
    user_excl+=(":(exclude,glob)$line"); echo "excluding: $line (PREPUBLISH_EXCLUDE)"
  done < "$PREPUBLISH_EXCLUDE"
fi

strict=$(IFS='|'; echo "${patterns[*]}")
lenient=$(IFS='|'; echo "${allowable[*]}")
hits=0
scratch=$(mktemp -d "${TMPDIR:-/tmp}/prepublish.XXXXXX") || die "can't make a temp directory"
trap 'rm -rf "$scratch"' EXIT
revs=$(git rev-list --all) || die "git rev-list --all failed"

# Each source prints records as <where>\0<what>\0<match>\n (git grep -z prints path\0line\0match), so
# the match is split off exactly, whatever colons the path or the match hold.
# report [allow-regex]: print each record as where:what:match unless its match is allowed.
report() {
  local found=1 where what match
  while IFS= read -r -d '' where && IFS= read -r -d '' what && IFS= read -r match; do
    if [ -n "${1:-}" ] && printf '%s\n' "$match" | grep -qiE "$1"; then continue; fi
    printf '%s:%s:%s\n' "$where" "$what" "$match"; found=0
  done
  return $found
}

# These helpers, and the sources further down, are called through run(), which shellcheck can't follow.
# git grep, where any status above 1 (an error, not "no match") ends the scan with 64.
# shellcheck disable=SC2329
gg() { git grep "$@"; local s=$?; [ "$s" -le 1 ] || die "git grep failed (exit $s)"; }
# ggm <main|own> <pattern> [git grep args]: main prints each match in everything but the scanner's
# paths; own prints whole lines at the scanner's paths, for own_hits to filter.
# shellcheck disable=SC2329
ggm() {
  local mode="$1" pat="$2"; shift 2
  if [ "$mode" = own ]; then gg -z -naiE -e "$pat" "$@" -- "${own[@]}" ${user_excl[@]+"${user_excl[@]}"}
  else gg -z -naioE -e "$pat" "$@" -- . "${own_excl[@]}" ${user_excl[@]+"${user_excl[@]}"}; fi
}
# grep_records <where> <pattern>: each match in stdin as a record, with grep -n's line number
# shellcheck disable=SC2329
grep_records() {
  local out s l
  out=$(grep -naioE -e "$2"); s=$?
  [ "$s" -le 1 ] || die "grep failed (exit $s)"
  [ -n "$out" ] || return 0
  while IFS= read -r l; do printf '%s\0%s\0%s\n' "$1" "${l%%:*}" "${l#*:}"; done <<<"$out"
}
# matches_of <pattern> <text>: each match in <text>, one per line
matches_of() {
  local out s
  out=$(printf '%s\n' "$2" | grep -aioE -e "$1"); s=$?
  [ "$s" -le 1 ] || die "grep failed (exit $s)"
  [ -z "$out" ] || printf '%s\n' "$out"
}

# shellcheck disable=SC2329
worktree() { ggm "$1" "$2" --untracked; }
# shellcheck disable=SC2329
index() { ggm "$1" "$2" --cached; }
# shellcheck disable=SC2329
commits() {
  local c ref type obj ptype pobj
  for c in $revs; do ggm "$1" "$2" "$c"; done
  # refs to trees and blobs, directly or through an annotated tag (rev-list skips them)
  while read -r ref type obj ptype pobj; do
    if [ "$type" = tag ]; then type="$ptype" obj="$pobj"; fi
    case "$type" in
      tree) ggm "$1" "$2" "$obj" ;;
      blob) [ "$1" = own ] || { git cat-file blob "$obj" | grep_records "$ref" "$2"; } || exit 64 ;;
    esac
  done < <(git for-each-ref --format='%(refname) %(objecttype) %(objectname) %(*objecttype) %(*objectname)')
}
# metadata lines as <where>\t<what>\t<text>, written once to $scratch/meta
meta_lines() {
  local c note commit ref type obj
  for c in $revs; do
    git show -s --format='%an <%ae>%n%cn <%ce>%n%B' "$c" | sed "s/^/$c	message	/"
  done
  git for-each-ref --format='%(refname) %(objecttype) %(objectname)' | while read -r ref type obj; do
    if [ "$type" = tag ]; then git cat-file tag "$obj" | sed "s|^|$ref	tag object	|"; fi
  done
  git notes list | while read -r note commit; do git show "$note" | sed "s/^/note $commit	note	/"; done
  git -c core.quotePath=false log --all -m --format= --name-only | sort -u | sed 's/^/history	file name	/'
  git -c core.quotePath=false ls-files --cached --others --exclude-standard | sed 's/^/worktree	file name	/'
  git for-each-ref --format='%(refname)' | sed 's/^/ref	name	/'
}
# shellcheck disable=SC2329
metadata() {
  local line where rest what text m ms
  [ "$1" = main ] || return 0
  while IFS= read -r line; do
    where="${line%%$'\t'*}" rest="${line#*$'\t'}"
    what="${rest%%$'\t'*}" text="${rest#*$'\t'}"
    ms=$(matches_of "$2" "$text") || exit 64   # matches_of dies in the subshell; pass it on
    [ -z "$ms" ] || while IFS= read -r m; do printf '%s\0%s\0%s\n' "$where" "$what" "$m"; done <<<"$ms"
  done < "$scratch/meta"
}

# own_hits <pattern>: whole-line records from a scanner path in, match records out, except lines that
# are lines of this scanner (their paths are noted in $scratch/skipped).
own_hits() {
  local where what line m ms
  while IFS= read -r -d '' where && IFS= read -r -d '' what && IFS= read -r line; do
    if grep -Fxq -e "$line" "$self"; then printf '%s\n' "$where" >> "$scratch/skipped"; continue; fi
    ms=$(matches_of "$1" "$line") || exit 64
    [ -z "$ms" ] || while IFS= read -r m; do printf '%s\0%s\0%s\n' "$where" "$what" "$m"; done <<<"$ms"
  done
}

run() {  # run <source> <main|own> <pattern> [allow-regex]
  "$1" "$2" "$3" > "$scratch/raw"   # a failed search exits 64 from inside the source
  if [ "$2" = own ]; then own_hits "$3" < "$scratch/raw" > "$scratch/rec"; else mv "$scratch/raw" "$scratch/rec"; fi
  if report "${4:-}" < "$scratch/rec"; then hits=1; fi
}
section() {  # section <title> <source>
  local mode
  echo "== $1"
  for mode in main own; do run "$2" "$mode" "$strict"; run "$2" "$mode" "$lenient" "$allow"; done
}
meta_lines > "$scratch/meta"
section "working tree (tracked and untracked, not ignored)" worktree
section "index (staged)" index
section "history (every commit on every ref, and refs to trees or blobs)" commits
section "commit messages, authors and committers; tag objects; notes; file names; refs" metadata

if [ -s "$scratch/skipped" ]; then
  sed -E 's/^[0-9a-f]{40}://' "$scratch/skipped" | sort -u | sed 's/^/skipped (lines of this scanner): /'
fi
[ "$hits" -eq 0 ] && echo "clean" || echo "HITS above: read each one"
exit "$hits"
