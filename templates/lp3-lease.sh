#!/usr/bin/env bash
# Take turns on one Light Phone III between several agent sessions.
#
#   lp3-lease.sh take "<holder>" "<purpose>" [minutes]   # default 15
#   lp3-lease.sh release "<holder>"
#   lp3-lease.sh show
#
# Written for this repo from the protocol our sessions followed by hand (docs/how-we-worked.md). The
# lease is a file with holder, purpose, since and until (plus until_epoch, which this script adds). It is
# created with noclobber, so when two sessions race for a free phone, exactly one wins. An expired lease
# is moved aside before a new one is created; if what was moved turns out to be a fresh lease another
# session had just written, it is put back. That narrows the takeover race to a tiny window but isn't a
# strict lock, which is one more reason for the heads-up messages. A lease written by hand without until_epoch is read through
# its `until:` line, which must look like 2026-09-28T14:05:00-0500. Anything else counts as held: ask.
#
# After taking or releasing, send the other sessions a one-line heads-up ("LP3 held by <holder> until
# <time>" / "LP3 free"). Agent turns should be 15 minutes or less. Yield at the next safe point when
# another session asks.
#
# Set LP3_SERIAL to your phone's serial so the script checks the right phone is attached. Keep the
# serial out of anything you commit.
set -euo pipefail

LEASE="${LP3_LEASE:-$HOME/.cache/lp3-lease}"
cmd="${1:-show}"

fmt_time() { date -r "$1" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d "@$1" '+%Y-%m-%dT%H:%M:%S%z'; }
parse_time() {  # ISO 8601 with a numeric offset -> epoch seconds, macOS or GNU date
  date -j -f '%Y-%m-%dT%H:%M:%S%z' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

expired() {  # expired [file]
  local f="${1:-$LEASE}" until_epoch until_text
  until_epoch=$(sed -n 's/^until_epoch: //p' "$f")
  if [ -z "$until_epoch" ]; then
    until_text=$(sed -n 's/^until: //p' "$f")
    [ -n "$until_text" ] || return 1          # an open-ended hold (a person using the phone): ask them
    until_epoch=$(parse_time "$until_text") || return 1
  fi
  [ "$(date +%s)" -gt "$until_epoch" ]
}

case "$cmd" in
  take)
    holder="${2:?holder}"; purpose="${3:?purpose}"; minutes="${4:-15}"
    [[ $minutes =~ ^[0-9]+$ ]] || { echo "minutes must be a whole number" >&2; exit 64; }
    if [ -n "${LP3_SERIAL:-}" ]; then
      adb devices | grep -q "^${LP3_SERIAL}[[:space:]]*device$" || { echo "LP3 not attached" >&2; exit 1; }
    fi
    mkdir -p "$(dirname "$LEASE")"
    if [ -f "$LEASE" ]; then
      if expired; then
        stale="$LEASE.stale.$$"
        mv "$LEASE" "$stale" 2>/dev/null || { echo "lost the race" >&2; exit 3; }
        if ! expired "$stale"; then   # another session's fresh lease landed first: put it back
          mv -n "$stale" "$LEASE"; rm -f "$stale"; echo "lost the race" >&2; exit 3
        fi
        echo "took over an expired lease:" >&2; cat "$stale" >&2; rm -f "$stale"
      else
        echo "lease held (ask the holder):" >&2; cat "$LEASE" >&2; exit 2
      fi
    fi
    now=$(date +%s); until_epoch=$((now + minutes * 60))
    set -C
    { printf 'holder: %s\npurpose: %s\nsince: %s\nuntil: %s\nuntil_epoch: %s\n' \
        "$holder" "$purpose" "$(fmt_time "$now")" "$(fmt_time "$until_epoch")" "$until_epoch" \
        > "$LEASE"; } 2>/dev/null || { echo "lost the race" >&2; exit 3; }
    cat "$LEASE"
    ;;
  release)
    holder="${2:?holder}"
    if [ -f "$LEASE" ] && grep -qxF "holder: $holder" "$LEASE"; then
      rm -f "$LEASE"; echo "LP3 free"
    else
      echo "not your lease (or none):" >&2; cat "$LEASE" >&2 2>/dev/null || true; exit 4
    fi
    ;;
  show)
    cat "$LEASE" 2>/dev/null || echo "LP3 free"
    ;;
  *) echo "usage: $0 take|release|show ..." >&2; exit 64 ;;
esac
