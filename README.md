# Building Light Phone III Tools with AI agents

Notes from building three LightOS Tools for the Light Phone III in September 2026, with Claude Code
agents writing nearly all of the code and most of the design rulings. One maintainer set direction,
held the phone, pressed Touch ID and made the calls that can't be undone.

| Tool | What it is | State |
|---|---|---|
| [light-reader](https://github.com/yarosz/light-reader) | DRM-free EPUB reader: Gutenberg, Standard Ebooks, OPDS catalogues, offline | In development, not yet submitted to Light |
| [light-doom](https://github.com/yarosz/light-doom) | Doom at 35 fps in pure Kotlin through a WebAssembly interpreter | Released as a dev-signed proof of concept |
| [light-chess](https://github.com/yarosz/light-chess) | Puzzles, an offline engine, and phone-to-phone games | v1 merged, v2 and v3 in progress |

A side project, [lightphone-wifi-install](https://github.com/yarosz/lightphone-wifi-install), installs
Tools over Wi-Fi without a cable.

## What's here

- [PLATFORM.md](PLATFORM.md) is the most useful file if you are writing a Tool yourself, with or
  without AI. It lists what the LP3 and LightOS do, checked on the phone or in Light's SDK source:
  keys, display, the build plugin's rules, lifecycle traps, getting adb on the phone, the emulator
  setup, and device quirks. Most of it is not in Light's docs.
- [docs/how-we-worked.md](docs/how-we-worked.md): one orchestrator session per Tool, fresh subagents
  per job, worktrees, ledgers, and three sessions sharing one phone.
- [docs/review-and-verification.md](docs/review-and-verification.md): the gates a change passed before
  it merged, and what each gate caught.
- [docs/what-went-wrong.md](docs/what-went-wrong.md): the incidents and the rule or script each one
  produced. If you read one doc about working with agents, read this one.
- [docs/apps/](docs/apps/): a short case study per Tool.
- [templates/](templates/): the brief formats we used, stripped of our paths, and a phone-lease script
  written for this repo from the protocol the sessions followed by hand.
- [scripts/prepublish-scan.sh](scripts/prepublish-scan.sh): scans a repo and its whole history for
  paths, addresses, keys and your own private patterns before it goes public.

## The short version

1. **Make the machine check the agent's work.** Pure cores with property tests, a local CI that runs
   on the real phone, and a rehearsal of Light's release builder on the committed commit. An agent's
   "done" meant nothing until one of those said so.
2. **Measure on the phone.** The emulator ran different fonts, a different density, no wheel and the
   Mac's CPU. Several bugs only ever showed up on the LP3.
3. **Review with fresh agents that hold one role.** In Reader, a three-model adversarial review found
   real bugs in almost every non-trivial PR, including one caused by a fix list the orchestrator wrote
   itself. A domain expert briefed with numbered questions and a recommended answer for each, replying
   `RULING: accept | amend | reject`, replaced a long-lived advisor session that had become a bottleneck.
4. **Write state down, not in the session.** A ledger with a HANDOFF section let any session, or a
   stranger, resume after compaction, a spend limit, or a 16-hour stall.
5. **Keep a short list of things only the human does.** Posting to Light, going public, signing,
   licences, and anything on the maintainer's accounts. Agents drafted; the maintainer sent.
6. **When a guard blocks an agent, stop.** Twice an agent got around a guard instead of reporting
   it. Both times the right fix was to change the setup.

## Starting a new Tool

The order that worked for the third Tool:

1. Read [PLATFORM.md](PLATFORM.md), then Light's SDK README. Get adb on the phone ("Getting adb on the
   phone").
2. Add [light-sdk](https://github.com/lightphone/light-sdk) as a submodule at a tagged version. Commit
   `serverPackage = "com.lightos"` in `lighttool.toml`, and copy light-reader's `scripts/emulator-build.sh`
   (swaps it for emulator builds), `scripts/light-build.sh` (rehearses Light's builder) and `scripts/ci.sh`.
3. Build your own emulator AVD from light-chess `scripts/emulator/RECIPE.md`, on the next free even port.
4. Start `LEDGER.md` from [templates/ledger-handoff.md](templates/ledger-handoff.md), with a done-when on
   every item. Keep a private ledger outside the repo for anything personal.
5. Grill the design with [templates/domain-expert-brief.md](templates/domain-expert-brief.md) before any
   code. Write the glossary (`CONTEXT.md`) from the rulings, and copy light-reader's
   `scripts/domain-drift.sh`.
6. Put the logic in pure Kotlin with property tests first; the Compose screens come after.
7. If other sessions share the phone, take turns with [templates/lp3-lease.sh](templates/lp3-lease.sh).
8. Before going public, run [scripts/prepublish-scan.sh](scripts/prepublish-scan.sh) with a private
   patterns file.
9. Add a weekly job that runs the builder rehearsal against Light's newest SDK.

## How this was written

Claude wrote these docs from the three projects' repos, ledgers, decision logs and session transcripts.
Four independent review agents then checked them for privacy, accuracy and usefulness, and the
maintainer reviewed them before publishing. Light's
[AI/LLM policy](https://github.com/lightphone/light-sdk/blob/main/CONTRIBUTING.md#aillm-policy) asks
that all communication in Light's own repos come from a human; nothing here is posted there.

Facts are dated because LightOS changes. If one is wrong on your LightOS version, open an issue.

## Licence

Text: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Scripts and templates: MIT. See
[LICENSE](LICENSE).
