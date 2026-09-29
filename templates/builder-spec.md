# <Milestone> PR (<letter>): <what it builds>

<!-- A builder agent's brief. Written by the orchestrator, one per PR, saved as a file so a fresh agent
     can be relaunched from it. Reader's chapter work used exactly this shape. The glossary and drift-check
     lines assume a CONTEXT.md and light-reader's scripts/domain-drift.sh; delete them if you have
     neither. Delete these comments. -->

**Where:** git worktree `<path>` (branch `<branch>`, from main `<sha>`). Edit only inside it. **Do not
commit** (the orchestrator commits, signed). No adb, no emulator. <!-- or say which emulator, by AVD name -->

**Read first:** `AGENTS.md` (all of it, especially "Domain language"), `CONTEXT.md` (<the terms this PR
touches>), `docs/adr/<the relevant ADRs>`, the `LEDGER.md` item for this milestone (the settled answers
under it are the spec), then <the files the change starts from>.

## Goal

<Two or three sentences: what exists after this PR that didn't before. Say what is NOT in this PR and
which later PR does it.>

## Rules

<!-- Numbered, so reviewers and fix lists can cite them. Each rule traces to an ADR, a glossary entry or
     a ledger answer. Where you haven't decided, say "decide and document", and give a recommendation. -->

1. **<Rule name>.** <The rule, with the edge cases spelled out.>
2. ...

## Data shape

<!-- Name the shape before any code. Suggest one; let the builder improve it and say why. -->

Name the shape first, then write code. A suggested starting point:
- `data class <Thing>(...)`
- `fun <Owner>.<query>(...): <Type>`

Any new top-level name must be a `CONTEXT.md` term or listed in `docs/domain-ignore.txt`. Run the
drift check and get it to 0.

## Tests

<Where tests go and how to build fixtures.> Cover:
- <each rule, and each edge case named in the rules>;
- <the boundaries>.

Keep the existing <N> tests green: `<exact test command>`. Count the tests from the JUnit XML, not from
the console.

**Real-data check (not committed):** <download or use a real input, print what matters>. The done-when is
**<a number you expect>**. If the real data differs, report exactly what it has and why, and do not bend
the rules to hit the number.

## Style

Match the surrounding code: its comment density, naming and idiom. No narrating comments. Keep the change
as small as the rules allow.

## Report back

- The data shape you chose and why.
- The files changed.
- The test count and failures.
- The drift result.
- The real-data output.
- Every judgement call you made, and anything in the rules that turned out ambiguous.
