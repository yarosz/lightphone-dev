---
name: prepublish
description: This skill should be used before anything goes public, such as making a repo public, pushing a branch to a public remote, publishing an export, posting CI evidence (statuses, PR comments), or flipping a repo's visibility.
---

# Before a repo or a post goes public

`scripts/prepublish-scan.sh` is in this skill's directory; `-h` prints its usage. What a scan can't catch
needs a reviewer's read (step 5).

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
   every hit; exit 0 prints `clean`.
3. **Publish clean history as it is; squash or export a dirty line.**
   - A clean branch pushes as it is.
   - A branch with private history publishes as one signed squash of the scrubbed tree:
     `git commit-tree -S -p <public-parent> <branch>^{tree} -m "<message>"`, then push that commit.
   - Or publish a history-free export: `git archive` with excludes into a fresh repo, then a signed first
     commit.
   - Keep every commit signed; never rewrite history with unsigned commits.
4. **Scan a fresh clone of the public remote** after pushing (`git clone <public-url> <dir>` and run the
   scan there): local-only branches and `refs/pull/*` give false hits in your working copy. Then delete
   local branches and worktrees that still hold private commits.
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
