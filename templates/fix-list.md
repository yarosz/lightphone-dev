# <Milestone> PR (<letter>): review fixes (PR #<n>, head <sha>)

<!-- After interrogate and code review, the orchestrator folds every finding it accepts into one
     letter-coded list, and a fresh builder fixes it. A verifier then re-checks each letter. For risky
     areas (parsers, anything stored), repeat review after every fix commit until a round is clean:
     once, a fix list like this one introduced a regression of its own. The drift-check line assumes
     light-reader's scripts/domain-drift.sh; delete it if you don't have one. Delete these comments. -->

**Where:** git worktree `<path>` (branch `<branch>`, head `<sha>` = PR #<n>). First read `<spec file>`
(the rules), then `git diff origin/main...HEAD`. **Do not commit.** No adb.

<N> reviewers found the issues below. Fix each with a test that fails before the fix, and say which
ones you saw fail.

A. **[critical] <Short name>.** <What goes wrong, with a concrete input and the wrong output. Where in
   the code (`File.kt` ~line). The fix you want, and where it must stay contained so existing behaviour
   doesn't change.> Then measure: <how to prove it on real data, before and after>. Add a test that
   <the exact case>.
B. **<Short name>.** <Same shape. Say what the fix must keep intact, for example an ADR's rule.>
C. **<Short name>.** <When there are several small parts, number them (1), (2), (3).>
...

When done:
1. Run `<test command>` and count the tests from the JUnit XML. Run the drift check; it must report 0.
2. Rerun the real-data check (throwaway, then delete). Expected, unchanged: <numbers>.

Match the surrounding style; no narrating comments; keep each fix as small as it can be. Report:
- each fix, with the test that proves it;
- the before-and-after numbers for anything measured;
- the test count and failures;
- the drift result;
- every judgement call you made.
