#!/usr/bin/env bash
# Scan a repo's files AND its whole git history for things that shouldn't go public, before you push it
# to a public remote or flip it to public.
#
#   scripts/prepublish-scan.sh [repo-dir]
#
# Generic patterns are below. Your own private patterns (device serials, hostnames, family names, your
# employer) go in a file outside the repo, one extended regex per line (# starts a comment), named by
# PREPUBLISH_PRIVATE_PATTERNS. That way the patterns themselves are never committed.
#
# Exit 0 = no hits. Exit 1 = hits, printed as path:line:match (working tree) or commit:path:line:match
# (history). A hit isn't always a leak: read each one. Exit 64 = bad input.
#
# What a regex can't catch: facts you've decided not to publish yet. Those need a human or reviewer
# read, not this script.
# Binary files (images: EXIF, GPS) are skipped; strip their metadata separately.
set -uo pipefail

repo="${1:-.}"
cd "$repo" || exit 64

generic=(
  '/Users/[A-Za-z]'                   # macOS home paths
  '/home/[a-z]'                       # Linux home paths
  '/private/(tmp|var)/'               # macOS temp paths
  '\.claude/(jobs|projects)/'         # agent scratch and transcript paths
  '192\.168\.[0-9]{1,3}\.[0-9]{1,3}'  # LAN addresses
  # macOS git grep -E has no \b, so addresses are anchored with (^|[^0-9.]) instead.
  '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'  # Tailscale / CGNAT
  '[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}\.my\.local-ip\.co'
  '[A-Za-z0-9-]+\.ts\.net'            # Tailscale names
  '[A-Za-z0-9-]+\.local([^A-Za-z0-9-]|$)'  # mDNS host names
  '([0-9a-f]{2}:){5}[0-9a-f]{2}'      # MAC addresses
  'BEGIN [A-Z ]*PRIVATE KEY'
  'gh[pousr]_[A-Za-z0-9]{20,}'        # GitHub tokens
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
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'  # email addresses
)
# Allowed MATCHES (not lines): the emulator's host addresses and bot/noreply addresses.
allow='^[^0-9A-Za-z]?(10\.0\.2\.[0-9]+|noreply@anthropic\.com|[0-9]+\+?[A-Za-z0-9-]*@users\.noreply\.github\.com|[^@]+@example\.(com|org))$'

patterns=("${generic[@]}")
if [ -n "${PREPUBLISH_PRIVATE_PATTERNS:-}" ]; then
  [ -r "$PREPUBLISH_PRIVATE_PATTERNS" ] || { echo "cannot read $PREPUBLISH_PRIVATE_PATTERNS" >&2; exit 64; }
  while IFS= read -r line; do
    [ -n "$line" ] && [ "${line#\#}" = "$line" ] && patterns+=("$line")
  done < "$PREPUBLISH_PRIVATE_PATTERNS"
else
  echo "note: PREPUBLISH_PRIVATE_PATTERNS not set; scanning generic patterns only" >&2
fi

joined=$(IFS='|'; echo "${patterns[*]}")
hits=0

# Print each match that isn't allowed. Input lines look like <prefix>:<match>, where the match is the
# last field; git grep -o prints one match per line.
report() {
  local found=1 line match
  while IFS= read -r line; do
    match="${line##*:}"
    if ! printf '%s\n' "$match" | grep -qiE "$allow"; then echo "$line"; found=0; fi
  done
  return $found
}

echo "== working tree (tracked and untracked, not ignored)"
if git grep --untracked -nIioE "$joined" -- . ':!scripts/prepublish-scan.sh' | report; then hits=1; fi

echo "== history (every commit on every ref)"
for c in $(git rev-list --all); do
  if git grep -nIioE "$joined" "$c" -- . ':!scripts/prepublish-scan.sh' | report; then hits=1; fi
done

echo "== commit messages, authors and committers; tags; notes"
meta() {
  for c in $(git rev-list --all); do
    git show -s --format='%an <%ae>%n%cn <%ce>%n%B' "$c" | sed "s/^/$c:/"
  done
  git tag -n99 | sed 's/^\([^ ]*\) */tag \1:/'
  git notes list | while read -r note commit; do git show "$note" | sed "s/^/note $commit:/"; done
}
if meta | while IFS= read -r l; do
     printf '%s\n' "${l#*:}" | grep -ioE "$joined" | sed "s|^|${l%%:*}:|" || true
   done | report; then hits=1; fi

[ "$hits" -eq 0 ] && echo "clean" || echo "HITS above: read each one"
exit "$hits"
