# Tests for prepublish-scan.sh against a fixture repo. Sourced by run.sh.
SCAN="$SKILLS/prepublish/scripts/prepublish-scan.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
g() { git -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

new_state
r="$WORK/repo"; mkdir -p "$r"; g -C "$r" init
printf '# notes\nnothing private here\n' > "$r/README.md"
g -C "$r" add -A; g -C "$r" commit -m init
pat="$WORK/private-patterns"   # outside the scanned repo, as the skill says
printf '# my patterns\nPLANTED-MARKER-[0-9]+\n' > "$pat"

PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 0 "clean repo" "$SCAN" "$r"
check "clean repo: says clean" out_has "^clean$"

printf 'serial PLANTED-MARKER-42\n' > "$r/untracked.txt"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "untracked file with a private pattern" "$SCAN" "$r"
check "untracked hit printed" out_has "untracked.txt:1:PLANTED-MARKER-42"
rm "$r/untracked.txt"

printf 'PLANTED-MARKER-7\n' > "$r/leak.txt"; g -C "$r" add -A; g -C "$r" commit -m leak
g -C "$r" rm leak.txt; g -C "$r" commit -m "remove leak"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a removed file still in history" "$SCAN" "$r"
check "history hit printed" out_has "leak.txt:1:PLANTED-MARKER-7"

mkdir -p "$r/tools"; cp "$SCAN" "$r/tools/prepublish-scan.sh"
expect_exit 64 "unreadable patterns file" env PREPUBLISH_PRIVATE_PATTERNS="$WORK/missing" "$SCAN" "$r"
expect_exit 0 "-h" "$SCAN" -h

unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
