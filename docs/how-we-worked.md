# How we worked

Three Tools were built between 2026-09-23 and 2026-09-29, mostly in parallel, by Claude Code sessions on
one Mac with one Light Phone III. This is the setup that held up, and why.

## One orchestrator per Tool

Each Tool had one long-running orchestrator session. The orchestrator planned the work, wrote briefs,
spawned subagents, read every diff itself, ran the checks again itself, made the commits and merged.
It wrote little of the code.

- Reader's session ran for about five days and spawned about 120 subagents. It compacted six times.
- Chess's session spawned 48 subagents over about 28 hours.
- Doom was a single session with one subagent, because it was a proof of concept.

Before each compaction the orchestrator wrote a HANDOFF section in the ledger (below) and compacted
with a pointer to it, for example `/compact <path>/LEDGER.md HANDOFF (<commit>)`. The session that
came back read the ledger first and carried on.

## Fresh subagents, one role each, explicit model

Every job went to a new subagent with its own brief, and every follow-up went to another new one
instead of resuming the first. Two reasons:

- Resuming an agent by message is known to drop its model override silently (a rule we brought from
  earlier work), so a follow-up can run on a different model than intended.
- A fresh agent reads the code as it is now, not as it remembers it.

The roles that recurred:

| Role | Model | Brief |
|---|---|---|
| Builder | Opus (Fable for a few early Reader PRs) | A spec file: rules, data shapes, the tests to write, "Do not commit" ([template](../templates/builder-spec.md)) |
| Interrogate (Reader) | Three models in parallel: Opus, Fable and Sonnet, later Opus, Sonnet and Haiku | The diff, the spec, and "find what's wrong" |
| Independent review (Chess) | Opus | The branch, the ADRs, and "verify and review" |
| Code review | Opus, sometimes Sonnet or Fable | The PR URL and the local checkout path, read-only |
| Domain expert | Opus | Numbered questions, each with a recommended answer ([template](../templates/domain-expert-brief.md)) |
| Verifier | Haiku | The fix list, re-checked item by item after each fix commit ([template](../templates/fix-list.md)) |
| Smoke tester | Opus | A throwaway emulator, a list of flows, report-only |

"Interrogate" is a Claude Code review skill we used. Without it, spawn three read-only subagents on
different models, give each the diff and the spec, and tell each to find what's wrong. The maintainer
dropped Fable from Reader's trio for cost on 2026-09-28, and the trio kept finding real issues with Haiku
in its place.

Builders did not commit. Commits are signed through 1Password with Touch ID, so only the orchestrator,
with the maintainer at the keyboard, could make them. That turned out to be a useful checkpoint: nothing
landed that the orchestrator had not read.

## Worktrees

One git worktree per writer, one branch per PR. A subagent inherits its parent's working-directory pin.
When Chess's orchestrator had entered a worktree, a builder it spawned was refused every command in the
builder's own worktree. After that, every builder launched with `isolation: worktree`, and the
orchestrator stayed out of worktrees while a non-isolated agent was working. For submodules and stacked
PRs, see [what went wrong](what-went-wrong.md#git-in-parallel).

## Ledgers

Each repo keeps a `LEDGER.md`: a STATUS line, a "HANDOFF (read first)" section, and a list of work
items, each with a *done-when* ("done when `domain-drift.sh` reports 0", "done when the first Page opens
in 300 ms P90 on the LP3"). A done-when is what let an agent say "done" and a reviewer check it.

Reader numbers its milestones N1 to N7 (N2 is saving reading data, N3 catalogues, N4 chapters), and
(a), (b), (c) are the PRs within one. The other docs use those ids in parentheses.

There were two ledgers. The public one in each repo holds status, evidence and decisions. A private one
outside the repos holds anything personal: which phone is which, account details, the household. Public
repos never get personal facts, and that rule needed stating more than once: early on, Reader's
orchestrator put household details into a commit for a public release doc, and the maintainer caught it
before it was pushed.

Decisions went to ADRs (`docs/adr/`) when they were hard to reverse, surprising, and a real trade-off,
and to a lighter decision log otherwise. Chess's `docs/design/decision-log.md` gives every ruling an id,
so later rulings can supersede earlier ones by name.

The [ledger template](../templates/ledger-handoff.md) is the shape that worked.

## Domain language

Reader started with a glossary (`CONTEXT.md`): Book, Place (a saved reading position: a character
offset plus a snippet of the text there), Spine item (one file in the EPUB's reading order), Chapter,
Shelf, Catalogue. Four rounds of design grilling produced it before any product code. Once it existed:

- `scripts/domain-drift.sh` lists names in the code that are neither glossary terms nor listed in
  `docs/domain-ignore.txt`.
- A domain pass runs before each milestone's first PR. An expert agent reviews the names the milestone
  will add against the glossary, the glossary is updated, and the code is renamed to match. The pass
  ends when drift reports 0, and the result is tagged (`domain-pass/n4`).

Agents name things fluently and inconsistently. A glossary plus a script that complains is cheaper than
catching it in review. Chess adopted the same pattern on its first day.

## Sharing one phone between sessions

Three sessions shared one LP3 and, for a while, one emulator. Collisions were real: a run that installs,
takes focus or injects keys breaks any other session's run. What worked:

- **A lease file.** `~/.cache/lp3-lease` with holder, purpose, since and until, created with noclobber
  so only one session wins. Agent turns are 15 minutes or less. Release it, and say "LP3 free". The
  sessions ran this protocol by hand; [templates/lp3-lease.sh](../templates/lp3-lease.sh) is a script
  written afterwards for this repo that does the same.
- **Heads-up messages** between sessions before and after each hold. The sessions also traded findings
  this way. Chess found that LightOS acts on key-ups a Tool declined, and Reader shipped the same fix for
  its volume keys the same night.
- **One emulator per Tool.** Chess got its own AVD on its own port, and scripts pick their emulator by
  AVD name, never "the first `emulator-*` in `adb devices`".
- **Stop only your own package** at the end, and leave the other Tools installed.

## What stayed with the human

The maintainer kept a short list, and the agents kept to it:

- Anything posted to Light: issues, PR descriptions, discussion threads, replies. Light's contributing
  policy asks for this, so agents wrote drafts to a folder and the maintainer rewrote and posted them.
- Making a repo public, the licence, and the name.
- Signing (Touch ID), cables, waking the phone.
- Anything sent from the maintainer's own accounts to an outside service.
- Any report to Light, including security reports.

Everything else, agents did without asking once the gates were green: design rulings through domain
experts, implementation, reviews, merges, and edits to [PLATFORM.md](../PLATFORM.md). Partway through
Chess, the maintainer gave standing merge authority: merge once other agents have verified and approved.
Late in Reader, they handed one evening's product questions to a "decider" agent briefed to rule as
they would.

## Cost and limits

We hit spend and session limits several times, and agents died mid-milestone three times on Reader
alone. Nothing was lost, because each worktree was clean or its work staged, and each HANDOFF was current.
Before relaunching, check the worktrees yourself; don't trust the dead agent's last message.
