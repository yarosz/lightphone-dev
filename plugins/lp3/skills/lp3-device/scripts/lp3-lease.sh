#!/usr/bin/env bash
# Take turns on one Light Phone III (or one shared emulator) between several agent sessions.
#
#   lp3-lease.sh take "<holder>" "<purpose>" [minutes|open]   # default 15; open = a person holds it
#   lp3-lease.sh renew "<holder>" [minutes]                   # extend your own lease
#   lp3-lease.sh release "<holder>"                           # only your own lease
#   lp3-lease.sh show
#
# The lease is a file with holder, purpose, since and until in UTC, plus until_epoch, which this script
# adds. Create and change it only with this script, so there is one format. It is created with
# noclobber, so when two sessions race for a free phone, exactly one wins. An expired lease is moved
# aside before a new one is created; if what was moved turns out to be a fresh lease another session
# had just written, it is put back. That narrows the takeover race to a tiny window but isn't a strict
# lock, which is one more reason for the heads-up messages. A lease without until_epoch is read through
# its `until:` line, which must look like 2026-09-28T14:05:00+0000. `until: open`, or anything else
# that doesn't parse, counts as held: ask the holder.
#
# Before taking it, tell the other sessions what you'll do, for how long, and whether you'll touch
# volume, power or settings. After releasing, say "LP3 free" and whether your Tool is still installed
# and any setting or data changed. Agent turns are 15 minutes or less; renew while waiting on the human,
# and agree longer holds first. Yield at the next safe point when another session asks.
#
# LP3_LEASE names the lease file (default ~/.cache/lp3-lease). Give each shared emulator its own file.
# Set LP3_SERIAL to your phone's serial so take checks the right phone is attached. Keep the serial out
# of anything you commit.
#
# Exit 0 = done. 2 = held by someone else. 3 = lost a race. 4 = not your lease. 64 = usage.
set -euo pipefail

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; }

LEASE="${LP3_LEASE:-$HOME/.cache/lp3-lease}"
cmd="${1:-show}"

fmt_time() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%S%z'; }
parse_time() {  # ISO 8601 with a numeric offset -> epoch seconds, macOS or GNU date
  date -j -f '%Y-%m-%dT%H:%M:%S%z' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

expired() {  # expired [file]
  local f="${1:-$LEASE}" until_epoch until_text
  until_epoch=$(sed -n 's/^until_epoch: //p' "$f")
  if [ -z "$until_epoch" ]; then
    until_text=$(sed -n 's/^until: //p' "$f")
    [ -n "$until_text" ] || return 1          # no end time: held
    [ "$until_text" != open ] || return 1     # a person is using the phone: ask them
    until_epoch=$(parse_time "$until_text") || return 1
  fi
  [ "$(date +%s)" -gt "$until_epoch" ]
}

# lease_body <holder> <purpose> <since-epoch> <minutes|open>
lease_body() {
  local until_epoch
  if [ "$4" = open ]; then
    printf 'holder: %s\npurpose: %s\nsince: %s\nuntil: open\n' "$1" "$2" "$(fmt_time "$3")"
  else
    until_epoch=$(( $(date +%s) + $4 * 60 ))
    printf 'holder: %s\npurpose: %s\nsince: %s\nuntil: %s\nuntil_epoch: %s\n' \
      "$1" "$2" "$(fmt_time "$3")" "$(fmt_time "$until_epoch")" "$until_epoch"
  fi
}

check_minutes() { [[ $1 =~ ^[0-9]+$ ]] || { echo "minutes must be a whole number" >&2; exit 64; }; }

case "$cmd" in
  -h|--help) usage ;;
  take)
    holder="${2:?holder}"; purpose="${3:?purpose}"; minutes="${4:-15}"
    [ "$minutes" = open ] || check_minutes "$minutes"
    if [ -n "${LP3_SERIAL:-}" ]; then
      grep -q "^${LP3_SERIAL}[[:space:]]*device$" <<<"$(adb devices)" || { echo "LP3 not attached" >&2; exit 1; }
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
    body=$(lease_body "$holder" "$purpose" "$(date +%s)" "$minutes")
    set -C
    { printf '%s\n' "$body" > "$LEASE"; } 2>/dev/null || { echo "lost the race" >&2; exit 3; }
    cat "$LEASE"
    ;;
  renew)
    holder="${2:?holder}"; minutes="${3:-15}"
    check_minutes "$minutes"
    if [ -f "$LEASE" ] && grep -qxF "holder: $holder" "$LEASE"; then
      purpose=$(sed -n 's/^purpose: //p' "$LEASE")
      since_text=$(sed -n 's/^since: //p' "$LEASE")
      since=$(parse_time "$since_text") || since=$(date +%s)
      tmp="$LEASE.renew.$$"
      lease_body "$holder" "$purpose" "$since" "$minutes" > "$tmp"
      mv -f "$tmp" "$LEASE"
      cat "$LEASE"
    else
      echo "not your lease (or none):" >&2; cat "$LEASE" >&2 2>/dev/null || true; exit 4
    fi
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
  *) usage >&2; exit 64 ;;
esac
