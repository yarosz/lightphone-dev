# Reader

[yarosz/light-reader](https://github.com/yarosz/light-reader): a DRM-free EPUB reader for the LP3.
Gutenberg and Standard Ebooks are built in, any OPDS catalogue can be added, it works offline, and it
has no accounts. It was the first Tool and the one the process grew up around.

## Why a reader

There was no EPUB reader for the LP3. It fits what the phone is for (intentional use, no feeds), and it
needs no dependency outside Light's allowlist, so it can be Light-signed. We decided against building an
audiobook player, because three good ones already exist on the SDK, and against an on-device language
model, because inference runtimes need native code, which Light doesn't allow.

## Timeline

- **09-23:** toolchain, emulator, the `mise run ui` driver.
- **09-24:** a pagination spike, then four rounds of design grilling that produced the glossary and
  ADRs 0001-0006. The repo was created, its history scanned, and it was made public.
- **09-25 to 26:** release docs, then Paginator v2 as a stack of PRs. Opening a 165,000-character chapter
  on the LP3 went from 1,940 ms to 111 ms (P90).
- **09-27:** the reading-data store (N2), then catalogues and the Shelf (N3).
- **09-28:** the glossary rename and a domain pass.
- **09-28 to 29:** chapters and the table of contents (N4 a), a volume-key fix found by Chess, then
  chapter titles and progress in the reading view (N4 b).

Nothing has been submitted to Light yet.

## What worked

- **Lay out once, draw clipped bands.** Pages are bands of one measured layout, and a reading position
  is the character offset at the top of a page, never rewritten by a relayout. Font round trips land on
  the same page (5/34 → 7/52 → 10/80 → 5/34). When long chapters were too slow on the phone, layout
  moved to about 10,000-character windows around the reading position (ADR 0007).
- **A position that survives a new parser.** A Place stores a snippet of text next to the offset. When
  the parser changed how it split chapters, `resolve` re-found old Places by their snippet.
- **The done-when on every ledger item**, and a public evidence table.
- **Domain passes** before each milestone, with `domain-drift.sh` at 0 and a signed tag.
- **Local CI** that runs on the real phone and posts signoff statuses.

## What it cost

The review gate was heavy. Chapters (N4 a) took three interrogate rounds, and one round existed only to
check the fixes from the round before. The design advisor was the bottleneck for a while (see
[what went wrong](../what-went-wrong.md)). What it bought is in
[review and verification](../review-and-verification.md): real bugs caught before merge in almost every
milestone.

## Reusable pieces

- `scripts/ci.sh`: local CI with a device round trip and GitHub signoff statuses.
- `scripts/light-build.sh`: rehearses Light's release builder on the committed HEAD.
- `scripts/emulator-build.sh`: swaps `serverPackage` for an emulator build and restores it.
- `scripts/perf.sh`: P90 timings from the phone.
- `scripts/domain-drift.sh` and `docs/domain-ignore.txt`.
- `.mise/tasks/ui`: tap by label, keys, screenshots.
- `RELEASING.md`: the checklist for Light's version rules.
