#!/usr/bin/env bash
# Print the adb serial of exactly one Light Phone III or one LightOS emulator, or fail.
#
#   lp3-find.sh [--phone] [--wait <seconds>]     # an LP3, found by model TLP301
#   lp3-find.sh --avd <name> [--wait <seconds>]  # an emulator, found by AVD name
#
# Phone: every attached device whose ro.product.model is TLP301, USB or wireless (the mDNS entry
# adb-<serial>-<suffix>._adb-tls-connect._tcp). The same phone on USB and wireless counts once, by
# ro.serialno, and the USB entry is printed. Emulator: every emulator-* whose `emu avd name` matches.
#
# --wait polls every 5 s until exactly one match or the deadline, then exits. Use it when the phone has
# dropped off adb (up to 600 s), instead of retrying by hand.
#
# Exit 0 = one serial on stdout. 1 = no match. 2 = more than one match (listed on stderr). 64 = usage.
# Never uses `adb -d` (it misses a wireless phone) or `adb kill-server`.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

mode=phone avd="" wait=0
while [ $# -gt 0 ]; do
  case "$1" in
    --phone) mode=phone; shift ;;
    --avd) [ $# -ge 2 ] || { usage >&2; exit 64; }; mode=avd; avd="$2"; shift 2 ;;
    --wait) [ $# -ge 2 ] && [[ $2 =~ ^[0-9]{1,4}$ ]] || { usage >&2; exit 64; }; wait="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done
poll="${LP3_FIND_POLL:-5}"
[[ $poll =~ ^[0-9]{1,4}$ ]] || { echo "LP3_FIND_POLL must be 0-9999 seconds" >&2; usage >&2; exit 64; }

# Serials adb lists in state "device" (offline and unauthorized entries can't be driven).
online() { adb devices </dev/null | awk 'NR > 1 && $2 == "device" { print $1 }'; }

# One line per match on stdout: "<key> <serial>". Phones are keyed by ro.serialno for de-duplication.
matches() {
  local s model sn name
  for s in $(online); do
    if [ "$mode" = phone ]; then
      model=$(adb -s "$s" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r') || continue
      [ "$model" = TLP301 ] || continue
      sn=$(adb -s "$s" shell getprop ro.serialno </dev/null 2>/dev/null | tr -d '\r') || sn=""
      echo "${sn:-$s} $s"
    else
      case "$s" in emulator-*) ;; *) continue ;; esac
      name=$(adb -s "$s" emu avd name </dev/null 2>/dev/null | sed -n 1p | tr -d '\r') || continue
      if [ "$name" = "$avd" ]; then echo "$s $s"; fi
    fi
  done
  return 0
}

# Collapse matches with the same key, preferring the entry that isn't wireless.
pick() {
  sort | awk '
    { wireless = ($2 ~ /_adb-tls-connect\._tcp$/ || $2 ~ /:[0-9]+$/) }
    !($1 in best) || (bestw[$1] && !wireless) { best[$1] = $2; bestw[$1] = wireless }
    END { for (k in best) print best[k] }'
}

deadline=$(( $(date +%s) + 10#$wait ))
while :; do
  found=$(matches | pick)
  count=$(printf '%s' "$found" | grep -c . || true)
  if [ "$count" -eq 1 ]; then echo "$found"; exit 0; fi
  if [ "$count" -gt 1 ]; then
    echo "more than one match; pass the serial yourself with adb -s:" >&2
    printf '%s\n' "$found" >&2
    exit 2
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    if [ "$mode" = phone ]; then
      echo "no LP3 (model TLP301) on adb. Look for its wireless entry in 'adb devices -l', and ask any" >&2
      echo "other session sharing the phone, before asking the human to check the cable." >&2
    else
      echo "no running emulator reports AVD name '$avd'" >&2
    fi
    exit 1
  fi
  sleep "$poll"
done
