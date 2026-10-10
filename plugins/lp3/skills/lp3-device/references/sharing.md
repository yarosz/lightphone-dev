# Sharing one phone between agent sessions

Read this only if several agent sessions use the same LP3 or emulator. A run that installs, takes focus
or injects input breaks any other session's run on that device.

## The lease

`scripts/lp3-lease.sh` keeps a lease file with holder, purpose, since and until, in UTC. Default path
`~/.cache/lp3-lease`; set `LP3_LEASE` to use another file.

- Create and change the lease only with the script, so there is one format. Two hand-written formats
  once coexisted.
- `lp3-lease.sh take "<holder>" "<purpose>" 15` takes a free phone. Exit 2 means held: read the lease and
  ask the holder.
- A turn is about 15 minutes. `lp3-lease.sh renew "<holder>" 15` while you wait on the human. Agree longer
  holds with the other sessions first.
- A person using the phone holds it with `lp3-lease.sh take "<name>" "<purpose>" open`, which writes
  `until: open`. Nobody takes over an open lease.
- `lp3-lease.sh release "<holder>"` releases only your own lease. In one session, 11 of 21 releases were a
  bare `rm` of whatever lease was there.
- Clear someone else's lease only when it has expired. `take` does that for you, and leaves a held or
  unreadable lease alone.

## Emulators

Each emulator shared by sessions gets its own lease file: run the script with
`LP3_LEASE=~/.cache/lp3-lease-<avd>`. When a run needs both, take the emulator's lease first, then the
phone's; if the phone's is taken, release the emulator's instead of holding it while you wait.

## Messages

Before taking the lease, tell the active sessions:
- the purpose and how long;
- whether you will touch volume, power or settings.

After releasing, send "LP3 free" and say:
- whether your Tool is still installed;
- whether any setting or data changed.

Then each session checks that its own Tool is still installed:
`adb -s <serial> shell pm list packages | grep -x 'package:<pkg>'`.
