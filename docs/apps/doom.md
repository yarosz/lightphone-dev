# Doom

[yarosz/light-doom](https://github.com/yarosz/light-doom): Doom as a LightOS Tool, 35 fps in pure
Kotlin. A tinkerer's proof of concept, dev-signed, not meant for Light's Tool directory.

## How it started

It began as a question: can a smooth game be drawn with Compose Canvas on the LP3, or does it need a
custom renderer? A throwaway frame-probe Tool answered it in an afternoon. 200 moving sprites, a text HUD
and a megabyte of garbage per frame held 60 fps, with the draw inside half the frame budget and a tap
showing on the next frame. `SurfaceView` and GL worked too and gained nothing. The numbers are in
[PLATFORM.md](../../PLATFORM.md), "Rendering and frame rate".

The maintainer's next question was whether Doom could run on it, as a Tool for our own phones rather
than one for Light's directory.

## How it works

[CharlieTap/mood](https://github.com/CharlieTap/mood) compiles C Doom to WebAssembly and runs it on
Chasm, a WebAssembly interpreter written in Kotlin. The stock Mood app ran on the LP3 at 35 fps, Doom's
own tick rate. Making it a Tool meant:

- **Vendoring.** Chasm is Kotlin Multiplatform, and a Tool module can't be. `scripts/vendor.py` flattens
  it: it keeps the source sets Android compiles, resolves `expect`/`actual`, and rewrites Kotlin 2.4
  syntax for the SDK's Kotlin 2.3.20. About 80,000 lines of Chasm (84,000 with its dependencies), passing the plugin's scans and the builder
  rehearsal.
- **Sideways on a portrait-only phone.** The content is laid out a quarter turn clockwise, and Compose
  maps touches through the rotation.
- **Controls from the maintainer's hands.** Held sideways, the thumbs are on the screen, the right index
  finger is on the shutter (fire) and the left one is on the volume keys. The wheel is left to LightOS.
  Floating sticks beat fixed ones.
- **Color.** LightOS runs a global grayscale filter. A dev-signed build can lift it while Doom is on
  screen, through a one-time `adb pm grant` and a small patch to Light's plugin. The default build is
  grayscale with a tuned palette and passes Light's checks unmodified.

## Agents on a proof of concept

Doom used far less process than Reader: one session and one subagent. The subagent was a report-only
smoke tester on the emulator, told never to touch the phone and to check focus before every input. It
found five bugs, including that the back gesture closes the Tool without asking it (a platform fact
now) and that quitting looked the same as a crash.

Hand testing found the rest. No agent could tell that the stick felt wrong, or that the shutter was out
of reach with the phone upright.

## Publishing

The working repo stayed private, with its evidence logs. The public repo is a history-free export as
one signed commit, scanned for serials, paths and names before `gh repo create`. The release APK was
checked on the phone, downloaded again from GitHub, and its checksum compared.

## Side result: Wi-Fi install

Installing over the cable got old. LightOS's File Manager, in its debug menu, can receive an APK over
Wi-Fi into a "Tool Inbox", but uploads failed. Reading the File Manager showed
why: the inbox folder doesn't exist until you add one of Light's own Tools once. The tool became its
own repo, [lightphone-wifi-install](https://github.com/yarosz/lightphone-wifi-install), and the setup
steps are in [PLATFORM.md](../../PLATFORM.md).
