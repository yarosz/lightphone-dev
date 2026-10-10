---
name: lp3-prepublish
description: This skill should be used before a Light Phone III Tool repo, branch, export or device-CI evidence (commit statuses, PR comments with signoffs) goes public, such as making a Tool repo public, pushing a Tool branch to a public remote, or posting device signoffs. Typical requests are "make my Tool repo public", "check this branch before I push it" and "scan for serials before publishing".
---

# Before a Tool repo or its CI evidence goes public

`scripts/prepublish-scan.sh` is in this skill's directory; `-h` prints its usage. The scan is a
best-effort net, not a verdict: it can't read compressed files, archives (`.gz`, `.zip`, `.tar`, `.jar`)
or images, and it can't judge facts you've chosen not to publish. A reviewer's read (step 5) is still
required, whatever the scan prints. The scan and these steps work on any repo when the skill is invoked
by name.

## Steps

1. **Two ledgers.** The public one in the repo holds status, evidence and decisions. A private one outside
   the repo holds devices, accounts and anything personal. Done when nothing from the private list
   appears in the repo.
2. **Scan the tree and every commit on every ref.** Keep your private patterns (serials, hostnames, names,
   your employer) in a file outside the repo, one extended regex per line, and point to it:
   ```sh
   PREPUBLISH_PRIVATE_PATTERNS=<path-to-patterns-file> scripts/prepublish-scan.sh <repo>
   git -C <repo> log --all -G '<pattern>' --oneline        # per branch, for any pattern you doubt
   ```
   Write patterns into the file, never inline in a command: inline patterns end up in transcripts. Read
   every hit; exit 0 prints `clean`. Exit 64 means it couldn't search (a bad pattern, which it names, or
   a failed git command): fix that and rerun, never read it as clean. At the scanner's own paths it skips
   only lines that are lines of the scanner itself, and prints those paths; if the repo vendors a copy
   of the scanner elsewhere, list that path in a file named by `PREPUBLISH_EXCLUDE`.
3. **Publish clean history as it is; squash or export a dirty line.**
   - A clean branch pushes as it is.
   - A branch with private history publishes as one signed squash of the scrubbed tree:
     ```sh
     sha=$(git commit-tree -S -p <public-parent> "<branch>^{tree}" -m "<message>")
     git push <public-remote> "$sha:refs/heads/<branch>"
     ```
   - Or publish a history-free export: `git archive` with excludes into a fresh repo, then a signed first
     commit.
   - Keep every commit signed; never rewrite history with unsigned commits.
4. **Scan a fresh clone of the public remote** after pushing (`git clone <public-url> <dir>` and run the
   scan there): local-only branches and `refs/pull/*` give false hits in your working copy. Only after
   that scan prints `clean` and the human confirms, delete the local branches and worktrees that still
   hold private commits: `git worktree remove <path>`, then `git branch -D <branch>`.
5. **Have a reviewer read what a regex can't catch.** Brief a fresh agent to look for:
   - facts you've decided not to publish yet;
   - things others told you privately, and quotes from private chats;
   - unreported security findings;
   - wording that reads as a dig at a third party.

   For a first publication, run two independent privacy reviews on different models.
6. **Public CI evidence** (commit statuses, PR comments) carries no serials, hostnames or local paths.
   Signoffs are per commit, so rerun them on each new head.
7. **Check attribution trailers before the first push.** Session links in commit trailers are private
   identifiers, and harness trailers can come back after an owner asked for none:
   `git log --format=%B <range> | grep -i -E 'session|co-authored'`.
8. **Workflows over HTTPS.** Pushing `.github/workflows` through gh's HTTPS credentials needs
   `gh auth refresh -s workflow`.
9. **Outbound posts come from the human, in their own words.** Read their earlier posts first, and say
   only what actually shipped.

Done when the scan of a fresh public clone prints `clean`, the reviewers found nothing left to fix, and
no local branch or worktree holds private commits.
