# Chess

[yarosz/light-chess](https://github.com/yarosz/light-chess): puzzles (v1), a strong offline computer
opponent (v2), and correspondence games with a friend, where both phones hold the whole game (v3). It
is meant for Light's Tool Library. All three are merged and released (0.1.0 to 0.5.0), and 0.5.0 was
submitted to the Tool Library on 2026-10-09 and is awaiting Light's approval.

Chess was the third Tool, and it started with everything the first two had learned: PLATFORM.md, the
Reader repo as a template, a lease on the phone, and advice from the other sessions.

## Design by expert agents

The maintainer delegated the design questions. The orchestrator drafted numbered questions, each with a
recommended answer. Fresh Opus agents, briefed as chess and mobile-chess experts, ruled on each one:
accept, amend or reject, with a reason, plus the follow-up questions the orchestrator had missed.

- Round 1 covered the product. Three branches (puzzles, engine, network) then ran in parallel, followed
  by rounds 2a and 2b: 8 expert agents in all, plus an engine feasibility spike.
- Round 3 compared the parallel rulings with each other and found 9 contradictions.
- Round 4 found no new questions ("frontier empty").

That took about 20 minutes and produced the glossary, the first three ADRs and a decision log with an
id for every ruling. Later batches (relay edge cases, the opening book, v3's second PR) used the same
brief. Reader then adopted the pattern for its own reviews. The brief is in
[templates/domain-expert-brief.md](../../templates/domain-expert-brief.md).

The maintainer's own calls were few and specific: the licence (GPL-3.0-or-later for now, where the
orchestrator had recommended MIT), trying a second engine for reasons other than the licence, going public,
parking play against strangers, and the look of the pieces.

## The engine

The peer sessions advised against running Stockfish through Doom's WebAssembly interpreter. Modern builds
need SIMD and threads, NNUE through an interpreter is slow, and the networks are larger than Light's 5 MB
asset limit. Two pure-Kotlin engines were spiked instead. Pirarucu vendored almost unchanged and beat
Karballo 18.5 to 1.5 over 20 games. On the LP3, a non-debuggable build searched about 558,000 nodes per
second, enough for a real challenge. At the default think time, 3 s, that is about 1,674,000 nodes a
move at the top level, which is how the calibration played it.

To calibrate the levels, an agent played them against Stockfish 19 on the Mac: 1,280 games in
4 h 40 min. The estimates run from about 1263 at Level 2 to about 2948 at Level 8, but the fit against
Stockfish's Elo settings wasn't consistent (Level 5's fit: p = 0.0003), so the Tool shows levels, not Elo numbers
(light-chess `docs/levels.md`). An honest "we don't know" beat a precise-looking label.

## The relay server

v3 needs the two phones to exchange moves, so a small relay server passes moves between them. Each
phone keeps the full game, and the relay only stores and forwards: a Cloudflare Worker with one
SQLite-backed Durable Object per game (light-chess `relay/`). An independent review agent found three
concurrency and rate-limit bugs in it before merge. On the LP3, a move that had failed to send while the
relay was down went out through WorkManager once it was back, with no user action. LightOS disables
Doze, so such jobs aren't deferred.

Where the relay runs, and on whose account, was the maintainer's call; it was deployed on 2026-09-29.
Live play came later (light-chess #31): while both phones have the game open, moves travel over a
WebSocket. It closes as soon as the Tool is paused, or 10 s after another screen covers the board, and
moves fall back to HTTPS plus a WorkManager job.

## What the phone showed

- The wheel click toggled the flashlight on key-up, although the Tool handled it on key-down.
- Labels that fit on the emulator wrapped on the phone, because the LP3's font is wider.
- The wheel can't be tested on the emulator at all.
- A debug build is 3.6× slower than release, so the first go/no-go measurement was wrong.
- The APK carried about 22 MB of QR-scanner libraries it never used; excluding them took it from 29.4
  to 7.4 MB (light-chess #30).

Each is now in [PLATFORM.md](../../PLATFORM.md).

## Reusable pieces

- `scripts/release-check.sh`: `apk`, `run`, `upgrade`, `scan` and `relay` checks before a release.
- `scripts/light-build.sh`: Light's v0.2.0 builder flags, and a check that fails on non-arm64 native
  libraries.
- `scripts/emulator/RECIPE.md` and friends: build a second LightOS emulator AVD.
- `scripts/vendor-pirarucu.py --check --parity`: vendor an engine and prove it still counts the same
  nodes.
- `scripts/bench.sh`, which has its own test against a fake adb.
- `relay/`: the Worker and Durable Object relay, with tests.
- `RELEASING.md`: Light's submission steps.
- `docs/design/decision-log.md`: rulings with ids, contradictions and supersessions.
