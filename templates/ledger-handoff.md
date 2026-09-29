# Ledger

<!-- The ledger is where the project's state lives, so that a new session, after a compaction, a spend
     limit or a crash, can carry on without the old one. Keep the public ledger in the repo; keep anything
     personal (devices, accounts, household) in a private one outside it. Delete these comments. -->

STATUS: <milestone> <state>. main = <sha>. Next: <one line>
LAST SESSION: <date>

## HANDOFF (read first when resuming)

<!-- Newest state first. Write one before every compaction, and compact with a pointer to it:
     /compact <path>/LEDGER.md HANDOFF (<sha>) -->

### State (<date>, <event>). <Nothing in flight. | In flight: PR #n at <sha>, worktree <path>.>
- **main = <sha>** (#<n>, "<title>"). <test count>; drift <n> against `<tag>`.
- **What just landed:** <short list>.
- **Next, in order:**
  1. <item, with where its spec or brief lives>
  2. <item>
- **Devices:** <who holds the phone lease; which emulator is yours, by AVD name>.
- **Waiting on the maintainer:** <posts, decisions, Touch ID, anything only they can do>.

## Working rules learned

<!-- Only the non-obvious ones, each with the incident that taught it. -->

- <Rule.> (<date>: <what happened>.)

## Items

| # | Item | Done when | Status | Evidence |
|---|---|---|---|---|
| N1 | <item> | <a check anyone can run: a test, a number on the phone, a script at 0> | done | <PR, sha, measurement> |
| N2 | <item> | ... | in progress | |

## Open outside questions

<!-- Questions for the platform owner. Agents draft them; the maintainer sends them. -->

- <Question.> Draft: `<path>`. Not posted.
