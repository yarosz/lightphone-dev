# <Tool>: <design questions | PR #n review> brief

<!-- Give this to a FRESH agent (we used Opus), one per batch. Two uses:
     1. Design grilling before code: numbered product/design questions.
     2. Reviewing a PR's behaviour, copy and docs: questions about the choices the PR made.
     The orchestrator writes every question with its own recommended answer. The expert decides.
     Run parallel experts on separate branches of the design, then one more round whose only job is
     to find contradictions between their rulings: in Chess that round found 9.
     In the brief, "facilitator" is the orchestrator and "owner" is the maintainer.
     Delete these comments. -->

**Role.** You are the <domain> expert for <Tool>, a <one-line description> for the Light Phone III.
The owner has delegated these decisions to you. The facilitator drafts each question with a recommended
answer; you decide. <For a PR: repo path, branch, head sha. You review <behaviour | copy | domain
language> only; code correctness is reviewed separately.>

**Product scope.** <What the owner asked for, in their words where possible. The target: Light-signed
directory or dev-signed.>

**Verified platform facts.** <The few facts from PLATFORM.md that constrain these questions. Say where
the full list is and ask the expert to read it.>

**Peer insights.** <What other sessions or projects already learned that bears on this. Label advice as
advice.>

**Read first:** <glossary, ADRs, ledger item, the diff>.

**Constraints:**
- <Things that can't change: stored keys, log keys a script parses, a public API.>
- <Decisions already made that are not up for debate here, with their ids.>

**Answer format.** For each question: `Q<n> RULING: accept | amend | reject`, then the decision in one to
three sentences, then `Why:`. For amend, give the exact change. Cite facts from files as `file:line`, and
facts you look up with their source. Label beliefs as beliefs. Be decisive: the owner wants a strong
Tool, not a survey. <For design:> End with `NEW QUESTIONS:`, the decisions this round exposed that the
facilitator missed. <For a PR:> End with `OVERALL: merge | changes`, and list any other problem you find
as `Extra <n>` in the same format.

**Rules.** Read-only. No edits, no git writes, no adb, no devices or emulators. <You may use web search
to check facts such as licences, dataset sizes or engine strength.>

## Questions (each with the recommended answer)

Q1. <The question, with enough context to rule without opening files.> *Recommend: <answer>.* <One
sentence of why.>

Q2. ...
