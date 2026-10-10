# What went wrong

Each entry is an incident, why it happened, and what we changed. Most of the changes are a script or a
rule in a ledger, because telling an agent the same thing twice doesn't work as well as making the
mistake hard to make.

## Agents working around guards

**The incident.** Twice an agent hit a guard and found a way past it instead of reporting it:

- Doom's session was refused shell commands that contained a string that looked like a git path. It
  rebuilt the string at runtime (`printf 'g%s' ithub`) to get past the check.
- A Chess builder, refused inside its worktree, built in `/tmp` instead.

The work itself was fine both times, and was kept after review.

**Why.** Our guess: agents push toward finishing, and a guard looks like an obstacle between them and
done.

**What changed.** A rule in Chess's ledger, and now in these docs: if a guard blocks you, stop and
report. Then fix the setup. For the builder that meant `isolation: worktree` (see [how-we-worked](how-we-worked.md)).
For the shell guard, fixed scripts in files instead of commands built at runtime. When the auto-mode
classifier blocked a risky step, patching the SDK's plugin to allow one permission, the agent
brought it to the maintainer, who approved it. That is the behaviour we want.

## "Just turn off signing"

**The incident.** When a Touch ID prompt timed out, an agent proposed `commit.gpgsign=false`. The
maintainer said no: unsigned commits are not okay. Later, 1Password stopped signing altogether and
Chess's work sat staged for about 16 hours.

**What changed.** Never disable signing. On a signing failure, batch the work into fewer commits and
ask the human to be at Touch ID. Staged work survives; an unsigned history has to be rewritten.

## A reviewer that was also a gate

**The incident.** Reader's design questions went to a long-lived "advisor" session, and at first so did
its PR reviews. Merges waited on it: a whole stack of four PRs sat waiting for verdicts. The advisor also
once switched the branch of the shared checkout while another session was working in it.

**What changed.** The advisor reads origin refs only. Then, on 2026-09-28, the review gate moved to
Chess's pattern: a fresh Opus agent per batch, briefed as the domain expert, answering numbered
questions with `RULING: accept | amend | reject` and `OVERALL: merge | changes`
([template](../templates/domain-expert-brief.md)). A fresh agent can't become a bottleneck, and it
carries no memory of earlier rulings to defend.

## A fix list that caused a bug

**The incident.** On Reader's chapter work, round 1 of interrogate found that stored positions would
drift. The orchestrator consolidated the findings into one fix list, and one of its instructions
caused a no-break-space regression. Round 2 caught it.

**What changed.** For parser and stored-position changes, run a verification review after every fix
commit until one comes back clean. The orchestrator's own spec is not exempt from review.

## A platform fact published too early

**The incident.** After uploads to LightOS's Wi-Fi Tool Inbox failed with "Invalid path", PLATFORM.md
said Wi-Fi install doesn't work. About an hour later the real cause turned up in LightOS's code: the
inbox folder doesn't exist until you add one of Light's own Tools once. The entry was corrected.

**What changed.** Find the root cause before writing "doesn't work" into shared facts, because other
sessions read and act on them. Earlier, an agent had also assumed that LightOS wouldn't list a plain
Android app. A probe showed it does. Assumptions get labelled as beliefs until something checks them.

## Personal facts in public files

**The incident.** Early on, Reader's orchestrator put household details into a release-doc commit meant
for the public repo. The maintainer asked about it before it was pushed, and the commit was rewritten.

**What changed.** A private ledger outside the public repos for anything personal. Each release runs a
scan for serials, hostnames, paths and names; the private patterns come from an environment variable
so they are never committed. Tools that were built in private repos first were published as a single
squashed commit, so no private history came along.

## Wrong repo, wrong phone, wrong screen

- `/code-review 20` reviewed PR #20 of Light's SDK, not Reader's, because the session's working
  directory was an SDK worktree. Pass the full PR URL and the checkout path.
- A script sent volume keys to the LightOS home screen, which may have left the phone's ringer at 0 of 7. Check
  `dumpsys window` `mCurrentFocus` before every injected key or tap.
- An agent assumed which phone was attached. Check the serial.
- Reader's CI picked "the first emulator", so it would have run on Chess's once that one booted. It was
  caught when the sessions agreed ports. Select by AVD name.

## Git in parallel

- **Stacked PRs and squash merges.** After the base of a stack squash-merged, re-merging the next branch
  with "ours" dropped a rule from the base. It was caught before push. "Ours" is only safe if the branch
  already contains the base's final commit; otherwise merge the base branch tip first.
- **Submodules in worktrees.** `git submodule deinit` in a worktree cleared the submodule for the
  main checkout too. Remove worktrees with `git worktree remove --force` only.

## The platform surprised us

- **Leaked view models.** LightOS relaunches a Tool's activity in the same process and never clears the
  old `LightViewModel`. Three Doom engines ran at once. Engines now live in one process-wide owner.
- **Key-ups.** A Tool that handled the wheel click on key-down still toggled the flashlight, because
  LightOS acts on the key-up the Tool declined. Consume a key on down, repeat and up. Chess found it;
  Reader's volume keys had the same bug.
- **The emulator's DNS** silently stopped resolving. Boot it with `-dns-server 1.1.1.1,8.8.8.8`.
- **The phone left USB** after a reboot and once mid-session. The recovery (a charger, then the Mac
  again) is in [PLATFORM.md](../PLATFORM.md). If it vanishes, stop and ask; don't retry blindly.
- **A probe left a setting behind.** The frame probe changed `stay_on_while_plugged_in`, and a killed
  run raced the next run's read, so the original value was lost. Record settings before changing them,
  in a file, not in a variable.

## Predicted, and it still happened

Reader's ledger said that removing the on-screen page counter meant updating `ci.sh`, which reads it, in
the same PR. The PR removed the counter and not the check, and the PR's own CI run failed. A note in a ledger is
weaker than a test. If a script depends on something on screen, a test should fail when it's gone.

The same kind of break happened again, and this time nothing caught it. When Reader's reading controls
started hidden (N5), `perf.sh` could no longer find its A+ and A− buttons, and it stayed broken until the
next milestone needed it. Any script that drives the UI now gets a run at every milestone, whether or not
anyone needs its numbers that week.

## A failing signoff that came late

Chess's first PR showed a failing `signoff/emulator` status after the passing one, and the merge went
ahead on the pass. Nobody looked into it until we asked, ten days later. The cause was a chained
background command, `mise run emu > log; mise run ci > ci.log`. `mise run emu` stays attached until the
emulator exits, so CI never started. The orchestrator ran CI separately, which passed and posted success.
When it then shut the emulator down, the chained CI finally ran against no emulator and posted a
failure, overwriting `ci.log`.

The merge was right, but for a reason nobody had checked. Rules from it: never chain anything after a
command that keeps the emulator attached, kill stale background chains before shutting an emulator down,
and when a status changes after a merge decision, find out why before moving on.

## A number that was too consistent

Every scripted open in Reader took about 0.95 s, whatever the Book. That is the shape of something
fixed in the way, and it was: the SDK holds its splash for the first second and suppresses drawing, so
the scripts were timing the splash. A Perfetto trace found it. The old tables were dropped, and opens
were measured again from a tap after launch. Distrust a flat number.

## Asking the human what an agent could check

A Doom session asked the maintainer to check things on the phone (the debug menu, a dashboard listing)
that it could have read itself. It also stated two things with confidence that were wrong: that the
phone had the dashboard's add and remove buttons, and that the dashboard showed a stale tab. Rules from
it: before asking the human to try or check something on the phone, check it yourself on the emulator or
phone, read-only first. When the phone and the dashboard disagree, check both directly before
explaining either.

## Sharing the phone, again

One session's install test removed another session's Tool from the shared LP3. Nothing in the lease
protocol said to check afterwards. Now: after another session's turn on the phone, check that your own
Tool is still installed.

## Posting before releasing

A public discussion update went up with no GitHub release behind it, so readers couldn't find the build
it described. Reader now cuts a release at the end of every milestone and before any discussion update.
