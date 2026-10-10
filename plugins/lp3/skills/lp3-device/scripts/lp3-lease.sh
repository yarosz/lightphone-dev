#!/usr/bin/env bash
# Take turns on one Light Phone III (or one shared emulator) between several agent sessions.
#
#   lp3-lease.sh take "<holder>" "<purpose>" [minutes|open]   # default 15; open = a person holds it
#   lp3-lease.sh renew "<holder>" [minutes]                   # extend your own lease
#   lp3-lease.sh release "<holder>"                           # only your own lease
#   lp3-lease.sh show
#
# The lease is a file with holder, purpose, since and until in UTC, plus until_epoch, which this script
# adds. Create and change it only with this script, so there is one format. take, renew and release
# each run inside a lock (a directory, <lease>.lock, made with mkdir, which only one session can do), so
# checking the lease and changing it is one step: when several sessions race for a free or expired
# phone, exactly one gets it. A lock older than 30 s is left by a session that died and is cleared; a
# session that can't get the lock within about 5 s gives up with exit 3. A lease without until_epoch is
# read through its `until:` line, which must look like 2026-09-28T14:05:00+0000. `until: open` counts as
# held whatever until_epoch says, and so does an `until:` that doesn't parse: ask the holder.
#
# Holder and purpose are one line each: a newline or CR in either is refused, and so is an empty
# holder. renew and release act only when the `holder:` line equals your holder exactly. Minutes are a
# whole number from 0 to 1440 (24 hours), read in base 10, so 010 is ten.
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
# Exit 0 = done. 1 = LP3_SERIAL is set and that phone isn't attached (take only). 2 = held by someone
# else. 3 = lost a race, or the lock stayed busy. 4 = not your lease. 64 = usage (missing arguments, bad
# minutes, an empty holder, a holder or purpose with a newline or CR).
set -euo pipefail

usage() { sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; }

LEASE="${LP3_LEASE:-$HOME/.cache/lp3-lease}"
cmd="${1:-show}"

fmt_time() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%S%z'; }
parse_time() {  # ISO 8601 with a numeric offset -> epoch seconds, macOS or GNU date
  date -j -f '%Y-%m-%dT%H:%M:%S%z' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

expired() {
  local until_epoch until_text
  until_text=$(sed -n 's/^until: //p' "$LEASE")
  [ "$until_text" != open ] || return 1       # a person is using the phone, whatever until_epoch says
  until_epoch=$(sed -n 's/^until_epoch: //p' "$LEASE")
  if [ -z "$until_epoch" ]; then
    [ -n "$until_text" ] || return 1          # no end time: held
    until_epoch=$(parse_time "$until_text") || return 1
  fi
  [[ $until_epoch =~ ^[0-9]{1,12}$ ]] || return 1   # a mangled until_epoch: held, ask the holder
  [ "$(date +%s)" -gt "$((10#$until_epoch))" ]
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

one_line() {  # one_line <what> <value>: refuse a newline or CR, which would forge lease lines
  case "$2" in *$'\n'*|*$'\r'*) echo "$1 must be one line (no newline or CR)" >&2; exit 64 ;; esac
}
check_holder() {
  [ -n "$1" ] || { echo "holder must not be empty" >&2; exit 64; }
  one_line holder "$1"
}
is_holder() { [ -f "$LEASE" ] && [ "$(sed -n 's/^holder: //p' "$LEASE")" = "$1" ]; }

# check_minutes <value>: sets minutes, base 10, 0-1440
check_minutes() {
  if [[ $1 =~ ^0*([0-9]{1,4})$ ]] && [ "$((10#${BASH_REMATCH[1]}))" -le 1440 ]; then
    minutes=$((10#${BASH_REMATCH[1]}))
  else
    echo "minutes must be a whole number from 0 to 1440" >&2; exit 64
  fi
}

# lock: mkdir is atomic, so one session at a time gets past here. Released on exit.
lock() {
  local tries=0 made
  mkdir -p "$(dirname "$LEASE")"
  until mkdir "$LEASE.lock" 2>/dev/null; do
    made=$(stat -c %Y "$LEASE.lock" 2>/dev/null || stat -f %m "$LEASE.lock" 2>/dev/null) || made=""
    if [[ $made =~ ^[0-9]+$ ]] && [ $(( $(date +%s) - made )) -gt 30 ]; then
      echo "cleared a stale lock (over 30 s old): $LEASE.lock" >&2
      rmdir "$LEASE.lock" 2>/dev/null || true
      continue
    fi
    tries=$((tries + 1))
    [ "$tries" -lt 50 ] || { echo "lease busy: another session holds $LEASE.lock; try again" >&2; exit 3; }
    sleep 0.1
  done
  trap 'rmdir "$LEASE.lock" 2>/dev/null || true' EXIT
}

case "$cmd" in
  -h|--help) usage ;;
  take)
    [ $# -ge 3 ] || { usage >&2; exit 64; }
    holder="$2"; purpose="$3"; minutes="${4:-15}"
    check_holder "$holder"; one_line purpose "$purpose"
    [ "$minutes" = open ] || check_minutes "$minutes"
    if [ -n "${LP3_SERIAL:-}" ]; then
      grep -q "^${LP3_SERIAL}[[:space:]]*device$" <<<"$(adb devices)" || { echo "LP3 not attached" >&2; exit 1; }
    fi
    lock
    if [ -f "$LEASE" ]; then
      if expired; then
        echo "took over an expired lease:" >&2; cat "$LEASE" >&2; rm -f "$LEASE"
      else
        echo "lease held (ask the holder):" >&2; cat "$LEASE" >&2; exit 2
      fi
    fi
    body=$(lease_body "$holder" "$purpose" "$(date +%s)" "$minutes")
    set -C   # a lease written by hand, outside the lock, still isn't overwritten
    { printf '%s\n' "$body" > "$LEASE"; } 2>/dev/null || { echo "lost the race" >&2; exit 3; }
    cat "$LEASE"
    ;;
  renew)
    [ $# -ge 2 ] || { usage >&2; exit 64; }
    holder="$2"
    check_holder "$holder"; check_minutes "${3:-15}"
    lock
    if is_holder "$holder"; then
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
    [ $# -ge 2 ] || { usage >&2; exit 64; }
    holder="$2"
    check_holder "$holder"
    lock
    if is_holder "$holder"; then
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
