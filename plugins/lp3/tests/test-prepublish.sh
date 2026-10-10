# shellcheck shell=bash disable=SC2016  # the fake git below is written with a literal $1 and $@
# Tests for prepublish-scan.sh against a fixture repo. Sourced by run.sh.
SCAN="$SKILLS/lp3-prepublish/scripts/prepublish-scan.sh"

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

# The scanner's own paths hold its patterns. A line there is skipped only when it is a line of this
# scanner; anything else at those paths is scanned. A copy anywhere else is scanned in full, unless
# PREPUBLISH_EXCLUDE names it.
r2="$WORK/repo2"; own=plugins/lp3/skills/lp3-prepublish/scripts/prepublish-scan.sh
mkdir -p "$r2/$(dirname "$own")"; g -C "$r2" init
cp "$SCAN" "$r2/$own"
g -C "$r2" add -A; g -C "$r2" commit -m "the scanner at its own path"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 0 "an exact copy of the scanner at its own path is skipped" "$SCAN" "$r2"
check "skipped scanner path printed" out_has "^skipped.*$own"
{ cat "$SCAN"; printf '# PLANTED-MARKER-99\n'; } > "$r2/$own"
g -C "$r2" add -A; g -C "$r2" commit -m "a line planted in the scanner"
cp "$SCAN" "$r2/$own"; g -C "$r2" add -A; g -C "$r2" commit -m "scanner restored"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a planted line at the scanner's own path, in history" "$SCAN" "$r2"
check "planted line at the scanner's path reported with its commit" out_has "^[0-9a-f]\{40\}:$own:[0-9]*:PLANTED-MARKER-99"
{ cat "$SCAN"; printf '# PLANTED-MARKER-98\n'; } > "$r2/$own"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a planted line at the scanner's own path, in the working tree" "$SCAN" "$r2"
check "planted line in the working-tree scanner reported" out_has "^$own:[0-9]*:PLANTED-MARKER-98"

r2v="$WORK/repo2v"; mkdir -p "$r2v/tools" "$r2v/docs"; g -C "$r2v" init
{ cat "$SCAN"; printf '# PLANTED-MARKER-99\n'; } > "$r2v/tools/prepublish-scan.sh"
cp "$r2v/tools/prepublish-scan.sh" "$r2v/docs/my-prepublish-scan.sh"
g -C "$r2v" add -A; g -C "$r2v" commit -m "vendored copies"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "copies of the scanner elsewhere are scanned" "$SCAN" "$r2v"
check "copy at tools/prepublish-scan.sh reported" out_has "^tools/prepublish-scan.sh:.*PLANTED-MARKER-99"
check "copy at docs/my-prepublish-scan.sh reported" out_has "^docs/my-prepublish-scan.sh:.*PLANTED-MARKER-99"
printf '# vendored scanners\ntools/prepublish-scan.sh\ndocs/my-prepublish-scan.sh\n' > "$WORK/excludes"
PREPUBLISH_EXCLUDE="$WORK/excludes" PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 0 "PREPUBLISH_EXCLUDE skips vendored copies" "$SCAN" "$r2v"
check "active excludes printed" out_has "^excluding.*docs/my-prepublish-scan.sh"
printf 'tools/prepublish-scan.sh\r\ndocs/my-prepublish-scan.sh\r\n' > "$WORK/excludes-crlf"
PREPUBLISH_EXCLUDE="$WORK/excludes-crlf" PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 0 "a CRLF PREPUBLISH_EXCLUDE file still excludes" "$SCAN" "$r2v"
expect_exit 64 "unreadable PREPUBLISH_EXCLUDE" env PREPUBLISH_EXCLUDE="$WORK/missing" "$SCAN" "$r2v"

# The allowlist can't swallow a secret glued to an allowed address, and a match is taken after the
# path:line: prefix, not after its last colon. Tokens are built here so this file holds none.
r3="$WORK/repo3"; mkdir -p "$r3"; g -C "$r3" init
a36=$(printf 'A%.0s' $(seq 36)); a12=$(printf 'b%.0s' $(seq 12))
gh_tok="ghp""_$a36" ant_tok="sk-""ant-$a12" op_ref="op:""//Private/Item/password"
printf 'x %s@example.com\ny %s@example.org\nz %s:noreply@github.com\n' "$gh_tok" "$ant_tok" "$op_ref" > "$r3/glued.txt"
g -C "$r3" add -A; g -C "$r3" commit -m glued
expect_exit 1 "secrets glued to allowed addresses" "$SCAN" "$r3"
check "ghp token before @example.com reported" out_has "^glued.txt:1:$gh_tok"
check "sk-ant key before @example.org reported" out_has "^glued.txt:2:$ant_tok"
check "op:// reference before :noreply@github.com reported" out_has "^glued.txt:3:op:"
check "history: glued token reported with its commit" out_has "^[0-9a-f]\{40\}:glued.txt:1:$gh_tok"
check "allowed address alone is still allowed" sh -c "! grep -qx 'glued.txt:1:noreply@github.com' '$WORK/out'"
r3s="$WORK/repo3s"; mkdir -p "$r3s"; g -C "$r3s" init
printf 'url = git@github.com:lightphone/light-sdk.git\n' > "$r3s/.gitmodules"
expect_exit 0 "GitHub's shared SSH address (git@github.com) is allowed" "$SCAN" "$r3s"

# binary files are scanned: a NUL byte or a binary attribute can't hide one
r4="$WORK/repo4"; mkdir -p "$r4"; g -C "$r4" init
printf 'head\0PLANTED-MARKER-31 tail\n' > "$r4/nul.bin"
printf '*.dat binary\n' > "$r4/.gitattributes"; printf 'PLANTED-MARKER-32\n' > "$r4/secret.dat"
g -C "$r4" add -A; g -C "$r4" commit -m binaries
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "binary files" "$SCAN" "$r4"
check "file with a NUL byte scanned" out_has "^nul.bin:1:PLANTED-MARKER-31"
check "file marked binary in .gitattributes scanned" out_has "^secret.dat:1:PLANTED-MARKER-32"

# metadata: annotated-tag taggers, every file name ever committed, ref names
r5="$WORK/repo5"; mkdir -p "$r5"; g -C "$r5" init
printf 'clean\n' > "$r5/a.txt"; g -C "$r5" add -A; g -C "$r5" commit -m init
GIT_COMMITTER_NAME=PLANTED-MARKER-41 GIT_COMMITTER_EMAIL=tagger@example.com g -C "$r5" tag -a v1 -m "release"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "annotated-tag tagger" "$SCAN" "$r5"
check "tagger name reported" out_has "PLANTED-MARKER-41"
g -C "$r5" tag -d v1
printf 'clean\n' > "$r5/PLANTED-MARKER-42.txt"; g -C "$r5" add -A; g -C "$r5" commit -m add
g -C "$r5" rm PLANTED-MARKER-42.txt; g -C "$r5" commit -m remove
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a file name in history" "$SCAN" "$r5"
check "file name reported" out_has "PLANTED-MARKER-42"
g -C "$r5" reset --hard HEAD~2
g -C "$r5" branch PLANTED-MARKER-43
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a ref name" "$SCAN" "$r5"
check "ref name reported" out_has "^ref:name:PLANTED-MARKER-43"

mkdir -p "$WORK/notrepo"
GIT_CEILING_DIRECTORIES="$WORK" expect_exit 64 "not a git repo" "$SCAN" "$WORK/notrepo"
check "not a git repo: says so" err_has "not a git repo"
expect_exit 64 "unreadable patterns file" env PREPUBLISH_PRIVATE_PATTERNS="$WORK/missing" "$SCAN" "$r"
expect_exit 0 "-h" "$SCAN" -h


# fails closed: a bad pattern or a failing search is an error (64), never "clean"
printf 'serial PLANTED-MARKER-61\n' > "$r/planted.txt"
printf 'PLANTED-MARKER-[0-9]+\n(unclosed[\n' > "$WORK/bad-patterns"
PREPUBLISH_PRIVATE_PATTERNS="$WORK/bad-patterns" expect_exit 64 "a bad private pattern plus a planted token" "$SCAN" "$r"
check "bad pattern named" err_has "bad pattern"
check "bad pattern: never says clean" sh -c "! grep -q '^clean' '$WORK/out'"
printf '# crlf\r\nPLANTED-MARKER-[0-9]+\r\n' > "$WORK/crlf-patterns"
PREPUBLISH_PRIVATE_PATTERNS="$WORK/crlf-patterns" expect_exit 1 "a CRLF patterns file still matches" "$SCAN" "$r"
mkdir -p "$WORK/fakegit"
printf '#!/usr/bin/env bash\n[ "$1" = grep ] && { echo "fatal: simulated failure" >&2; exit 128; }\nexec "$REAL_GIT" "$@"\n' > "$WORK/fakegit/git"
chmod +x "$WORK/fakegit/git"
REAL_GIT=$(command -v git) PATH="$WORK/fakegit:$PATH" expect_exit 64 "a failing git grep is fatal" "$SCAN" "$r"
check "failing git grep: never says clean" sh -c "! grep -q '^clean' '$WORK/out'"
rm "$r/planted.txt"

# git replace can't hide a commit's content
r6="$WORK/repo6"; mkdir -p "$r6"; g -C "$r6" init
printf 'clean\n' > "$r6/a.txt"; g -C "$r6" add -A; g -C "$r6" commit -m init
printf 'PLANTED-MARKER-51\n' > "$r6/leak.txt"; g -C "$r6" add -A; g -C "$r6" commit -m leak
leak=$(git -C "$r6" rev-parse HEAD)
g -C "$r6" rm leak.txt; g -C "$r6" commit -m remove
decoy=$(git -C "$r6" commit-tree -p "$leak~1" -m leak "$leak~1^{tree}")
g -C "$r6" replace "$leak" "$decoy"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a commit hidden by git replace" "$SCAN" "$r6"
check "replaced commit's content reported" out_has "^$leak:leak.txt:1:PLANTED-MARKER-51"

# GitHub fine-grained tokens and Slack tokens (built here so this file holds none)
r7="$WORK/repo7"; mkdir -p "$r7"; g -C "$r7" init
pat_tok="github""_pat_$(printf 'C%.0s' $(seq 30))" slack_tok="xox""b-$(printf '1%.0s' $(seq 12))-abc"
printf 'a %s\nb %s\n' "$pat_tok" "$slack_tok" > "$r7/tokens.txt"
expect_exit 1 "GitHub fine-grained and Slack tokens" "$SCAN" "$r7"
check "github_pat token reported" out_has "^tokens.txt:1:$pat_tok"
check "Slack token reported" out_has "^tokens.txt:2:$slack_tok"

# the index: a staged secret whose working-tree copy was cleaned
r8="$WORK/repo8"; mkdir -p "$r8"; g -C "$r8" init
printf 'clean\n' > "$r8/a.txt"; g -C "$r8" add -A; g -C "$r8" commit -m init
printf 'PLANTED-MARKER-71\n' > "$r8/staged.txt"; g -C "$r8" add staged.txt
printf 'clean now\n' > "$r8/staged.txt"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a staged secret" "$SCAN" "$r8"
check "staged secret reported" out_has "staged.txt:1:PLANTED-MARKER-71"

# more metadata: a full tag message, a file name added by a merge, refs to blobs and trees, untracked names
r9="$WORK/repo9"; mkdir -p "$r9"; g -C "$r9" init
printf 'clean\n' > "$r9/a.txt"; g -C "$r9" add -A; g -C "$r9" commit -m init
{ echo release; for _ in $(seq 120); do echo filler; done; echo PLANTED-MARKER-81; } > "$WORK/tagmsg"
g -C "$r9" tag -a v1 -F "$WORK/tagmsg"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "line 122 of a tag message" "$SCAN" "$r9"
check "late tag-message line reported" out_has "PLANTED-MARKER-81"
g -C "$r9" tag -d v1
g -C "$r9" checkout -b side; printf 'side\n' > "$r9/s.txt"; g -C "$r9" add -A; g -C "$r9" commit -m side
g -C "$r9" checkout main; printf 'main\n' > "$r9/m.txt"; g -C "$r9" add -A; g -C "$r9" commit -m main
g -C "$r9" merge --no-commit side
printf 'clean\n' > "$r9/PLANTED-MARKER-82.txt"; g -C "$r9" add -A; g -C "$r9" commit -m merge
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a file name only a merge commit added" "$SCAN" "$r9"
check "merge-added file name reported" out_has "PLANTED-MARKER-82"
g -C "$r9" reset --hard HEAD~1; g -C "$r9" branch -D side
blob=$(printf 'PLANTED-MARKER-83\n' | git -C "$r9" hash-object -w --stdin)
g -C "$r9" update-ref refs/blobref "$blob"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a ref pointing at a blob" "$SCAN" "$r9"
check "blob ref content reported" out_has "PLANTED-MARKER-83"
g -C "$r9" update-ref -d refs/blobref
tree=$(printf '100644 blob %s\tt.txt\n' "$blob" | git -C "$r9" mktree)
g -C "$r9" update-ref refs/treeref "$tree"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "a ref pointing at a tree" "$SCAN" "$r9"
check "tree ref content reported" out_has "t.txt:1:PLANTED-MARKER-83"
g -C "$r9" update-ref -d refs/treeref
g -C "$r9" tag -a blobtag -m "points at a blob" "$blob"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "an annotated tag pointing at a blob" "$SCAN" "$r9"
check "tagged blob content reported" out_has "PLANTED-MARKER-83"
g -C "$r9" tag -d blobtag
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 0 "repo9 clean again" "$SCAN" "$r9"
: > "$r9/PLANTED-MARKER-84.txt"
PREPUBLISH_PRIVATE_PATTERNS="$pat" expect_exit 1 "an untracked file's name" "$SCAN" "$r9"
check "untracked file name reported" out_has "PLANTED-MARKER-84"

unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
