#!/usr/bin/env bash
# Save Android settings to a file before you change them, and put them back afterwards.
#
#   lp3-settings.sh <serial> save <file> <namespace>:<key> [<namespace>:<key> ...]
#   lp3-settings.sh <serial> restore <file>
#
# <namespace> is system, secure or global. Example:
#   lp3-settings.sh <serial> save "$HOME/.cache/lp3-settings-<pkg>-<holder>" global:stay_on_while_plugged_in \
#     secure:accessibility_display_daltonizer_enabled
#
# save refuses to overwrite an existing file: that file holds the originals from a run that never
# restored them, and saving again would record your changed values as the originals. Restore it first.
# A key that was unset is saved as null, and restore deletes it instead of writing a value. `settings
# get` prints null for a missing key, so a key whose value is the literal string null can't be told
# apart from a missing one: restore deletes it. Values are kept exactly, tabs and spaces included; save
# refuses (exit 64) a value with a newline (inside or trailing) or a CR in it, which can't round-trip.
# restore puts every value back, reads each one again to check, and removes the file only if all match.
# Keep the file outside /tmp if a reboot may come between save and restore.
#
# Exit 0 = done. 1 = adb failed, a value didn't read back, or (save) the file already exists.
# 64 = usage, a bad key, or a value with a newline or CR.
set -euo pipefail

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 3 ] || { usage >&2; exit 64; }
serial="$1" action="$2" file="$3"; shift 3

# get <ns> <key>: sets got to the value exactly. The x keeps $( ) from eating trailing newlines; then
# the one newline `settings get` ends with is removed (and a CR before it, from a pty adb).
get() {
  got=$(adb -s "$serial" shell settings get "$1" "$2" </dev/null && printf x) || return 1
  got="${got%x}"; got="${got%$'\n'}"; got="${got%$'\r'}"
}
check_ns() { case "$1" in system|secure|global) ;; *) echo "bad namespace: $1" >&2; exit 64 ;; esac; }
sh_quote() { local q="'\\''"; printf "'%s'" "${1//\'/$q}"; }   # one word for the device's shell
check_key() { [[ $1 =~ ^[A-Za-z0-9_.]+$ ]] || { echo "bad key: $1" >&2; exit 64; }; }

case "$action" in
  save)
    [ $# -ge 1 ] || { usage >&2; exit 64; }
    lines=""
    for spec in "$@"; do
      ns="${spec%%:*}" key="${spec#*:}"
      [ "$ns" != "$spec" ] || { echo "expected <namespace>:<key>, got $spec" >&2; exit 64; }
      check_ns "$ns"; check_key "$key"
      get "$ns" "$key"; value="$got"
      case "$value" in
        *$'\n'*|*$'\r'*) echo "$ns:$key has a newline or CR in its value; save can't keep it exactly" >&2; exit 64 ;;
      esac
      lines+="$ns"$'\t'"$key"$'\t'"$value"$'\n'
    done
    mkdir -p "$(dirname "$file")"
    if ! { set -C; printf '%s' "$lines" > "$file"; } 2>/dev/null; then
      echo "$file already exists: it holds unrestored originals. Run restore first." >&2; exit 1
    fi
    cat "$file"
    ;;
  restore)
    [ $# -eq 0 ] || { usage >&2; exit 64; }
    [ -r "$file" ] || { echo "no saved settings at $file" >&2; exit 1; }
    failed=0
    while IFS= read -r line; do   # split on the first two tabs only, so the value stays exact
      [ -n "$line" ] || continue
      ns="${line%%$'\t'*}" rest="${line#*$'\t'}"
      key="${rest%%$'\t'*}" value="${rest#*$'\t'}"
      check_ns "$ns"; check_key "$key"
      if [ "$value" = null ]; then
        adb -s "$serial" shell settings delete "$ns" "$key" </dev/null >/dev/null
      else
        adb -s "$serial" shell settings put "$ns" "$key" "$(sh_quote "$value")" </dev/null
      fi
      get "$ns" "$key"; now="$got"
      if [ "$now" = "$value" ]; then
        echo "restored $ns:$key = $value"
      else
        echo "MISMATCH $ns:$key is $now, expected $value" >&2; failed=1
      fi
    done < "$file"
    if [ "$failed" -eq 0 ]; then rm -f "$file"; else echo "kept $file" >&2; exit 1; fi
    ;;
  *) usage >&2; exit 64 ;;
esac
