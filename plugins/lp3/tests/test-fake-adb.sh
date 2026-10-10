# shellcheck shell=bash disable=SC2016  # literal $ and backticks are the point here
# Tests for the fakes themselves. Sourced by run.sh. The fake adb must never evaluate its arguments on
# the host: a shell argument holding shell metacharacters is logged and refused with exit 96.
A="$TESTS/fake-adb/adb"
S=SER-ONE

new_state; add_device $S TLP301 $S
canary="$WORK/canary"
for payload in 'getprop;' 'a|b' 'a&b' 'a$b' 'a`b' 'a<b' 'a>b' $'a\nb' $'a\rb' \
  ".Main;touch $canary" ".Main\$(touch $canary)" ".Main\`touch $canary\`" $'.Main\ntouch '"$canary"; do
  expect_exit 96 "fake adb refuses shell metacharacters: $(printf '%q' "$payload")" "$A" -s $S shell am start -n "$payload"
  check "fake adb: refusal says why ($(printf '%q' "$payload"))" err_has "shell metacharacters"
done
check "fake adb: no injected command ran on the host" test ! -e "$canary"
check "fake adb: refusals are logged" log_has "fake adb: shell metacharacters"

# Quoting is parsed like the device's shell parses it, without evaluation.
echo "x" > "$FAKE_ADB_STATE/dev/$S/settings/secure.k"
expect_exit 0 "fake adb: backslash-escaped space is one word" "$A" -s $S shell settings put secure k 'two\ words'
check "fake adb: escaped value stored" grep -qx "two words" "$FAKE_ADB_STATE/dev/$S/settings/secure.k"
expect_exit 0 "fake adb: single-quoted value is one word" "$A" -s $S shell settings put secure k "'a  b'"
check "fake adb: quoted value stored" grep -qx "a  b" "$FAKE_ADB_STATE/dev/$S/settings/secure.k"
expect_exit 97 "fake adb: unknown shell command" "$A" -s $S shell rm -rf x

# fake gh: arguments are compared, never run
export FAKE_GH_TAGS="$WORK/tags"; printf 'v1\n' > "$FAKE_GH_TAGS"
expect_exit 97 "fake gh: unknown path with metacharacters" "$TESTS/fake-gh/gh" api "repos/x;touch $canary"
expect_exit 97 "fake gh: jq with metacharacters is refused, not run" "$TESTS/fake-gh/gh" api repos/lightphone/light-sdk/tags --jq "\$(touch $canary)"
check "fake gh: no injected command ran on the host" test ! -e "$canary"
unset FAKE_GH_TAGS
