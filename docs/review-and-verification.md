# Review and verification

The rule under all of this: an agent's claim that something works is not evidence. A test, a script
or a measurement on the phone is. We wrote that down on day two (Reader's first decision log: "makes
AI-written code checkable by machines instead of by claims") and built the gates to match.

## The gates a change passed

Reader's gate: `AGENTS.md` "How changes land", plus the orchestrator's own steps from its ledger. Chess
used steps 1, 2 and 5 to 8, with a single independent review agent in place of step 3.

1. **The builder's own tests**, written from the spec before or with the code.
2. **The orchestrator's first-hand check.** Read the diff. Run the tests and the builder rehearsal again
   in the worktree, through the same toolchain ([mise](https://mise.jdx.dev): `mise exec`, so the pinned
   JDK and Gradle are used). Look at the screenshots.
3. **Interrogate.** Three reviewers on different models, in parallel, each told to find what's wrong.
   Findings go into a letter-coded fix list, each fix with a failing test first.
4. **Verification after each fix commit** for risky areas (parsers, stored positions), until a round
   comes back clean.
5. **Code review** by a fresh agent, read-only.
6. **Domain-expert review** of behaviour, copy and docs, as `RULING` lines posted on the PR.
7. **CI**:
   - GitHub Actions `build`: unit tests and a simulation of Light's release builder.
   - `signoff/emulator` and `signoff/lp3` statuses, which only the local `mise run ci` can post, after
     a scripted round trip on the emulator and on the phone.
8. **Squash merge** with `--match-head-commit`, so what merges is the commit that was reviewed.

It sounds like a lot for a one-person project. Most gates caught something the others missed.

## What each gate caught

**Pure cores and property tests.** Pagination, parsing, Place resolution (finding a saved reading
position again), chess rules and ratings live in plain Kotlin with no Android in them, tested over
thousands of random inputs:

- 6 × 3,000 random pagination cases.
- Chess move generation exact on perft, plus 400 random games.
- Engine node counts identical to the upstream engine after vendoring (`ParityTest`).
- Glicko-2 against Glickman's worked example.
- Opening-book keys against the Polyglot spec's test keys.
- Byte-identical rebuilds of the puzzle pack and opening book.
- A two-phone correspondence game replayed across random network failures.

These tests let us accept a large amount of agent-written logic without reading every line of it.

**Interrogate (Reader)** found real bugs in nearly every non-trivial PR:

- Saving reading data (N2): 10 issues. A stale debounced save could overwrite the pause flush. A crash
  between two renames could lose the newest save. A snippet could split an emoji in half. The suite went
  from 61 to 105 tests.
- Chapters (N4 a): three rounds. Round 1 found that 55 of 66 stored positions at chapter headings would
  drift, some by about 2,400 characters. Round 2 found a regression that the orchestrator's own round-1
  fix list had caused. That is why step 4 exists.

**An independent review agent (Chess)** on the phone-to-phone relay server found a cancel/redeem race,
a double append at the same sequence number, and a join path that skipped the rate limit. Each was fixed
test-first.

**Domain experts** caught design mistakes before there was code. Chess's round-3 contradiction pass,
which compared the rulings of agents that had worked in parallel, found 9 contradictions. One was a
non-canonical en passant field in positions that would have made two phones disagree about a game and
freeze it as "out of sync". An expert also rejected the first engine candidate (Java, reflection, and
about 400 Elo weaker) for one that vendors cleanly.

**The advisor, after a merge.** Reader's first CI PR committed the emulator's `serverPackage`. A
Light-signed build of that commit would never have connected to LightOS. The design advisor noticed it
while reading the merged PR. It is now covered by a unit test and by the builder rehearsal.

**The PR reviewer** caught that Reader's first device round trip would have passed on an empty screen,
because empty before equals empty after.

**The emulator** caught parsing problems (Android's XML parser silently drops entities the JVM parser
handles in unit tests). It also showed its own mismatches: with three-button navigation, the portrait
lock pillarboxed the Reader to 43 pages per chapter against the phone's 34.

**The phone** caught what nothing else could:

- Reader's first layout approach took 475-1,356 ms to open a long chapter on the phone, against a
  300 ms budget. The emulator runs on the Mac's CPU, so its numbers never count.
- The emulator ran at 420 dpi against the phone's 480.
- The LP3's font is wider than the emulator's, so labels wrapped.
- A key-up the Tool declined toggled the flashlight. Only the real wheel and a real torch showed it.

**Hand testing by the maintainer** caught feel. In Doom that was the grip (the shutter sits under the
right index finger only when the phone is held sideways, which changed the whole layout), a slider that
stuck, and a color toggle that only darkened the screen. No agent found these, because they need hands.

**A smoke-test agent** on a throwaway emulator walked every flow and reported only. For Doom it found
five bugs, including that the back gesture closes the Tool and that quitting looked the same as crashing. For Chess
it found a failed result that wasn't saved at once and a back path that skipped a menu.

**The builder rehearsal.** Light builds releases from a committed hash with its own unmodified plugin.
`scripts/light-build.sh` clones the committed HEAD and runs the same checks, so it cannot see
uncommitted work. We ran it on every branch, and a weekly job runs it against Light's newest SDK.

## Things that looked like verification and weren't

- **An old result file.** Gradle run outside `mise` failed, and the orchestrator read the builder's
  previous test-result XML as a pass. Now: always run through `mise exec`, and check the timestamp.
- **An exit code.** A background `light-build` exited 0 without printing its OK line. Check for the
  line itself.
- **A debug build.** Chess's first go/no-go measurement ran on a debuggable build, 3.6× slower than
  release. A `benchmark` build type replaced it.
- **A scan that read nothing.** The first run of this repo's own pre-publish scan reported "clean"
  because `git grep` skips untracked files and nothing was committed yet. A planted fake serial proved
  the fixed version works.

## Evidence in public

Signoff statuses and PR comments are public, so CI evidence carries no device serials, hostnames or
local paths. Chess's `release-check.sh scan` greps for private patterns supplied through an environment
variable, so the patterns themselves never get committed. [scripts/prepublish-scan.sh](../scripts/prepublish-scan.sh)
is the version we ran on this repo.
