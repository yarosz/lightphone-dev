# LP3 platform facts (any Tool)

What building three Tools (Reader, Doom, Chess) taught us about the Light Phone III and LightOS. Every
entry was checked on an LP3 or in Light's SDK source ([lightphone/light-sdk](https://github.com/lightphone/light-sdk)),
and most carry the date we checked, because LightOS changes. Tested on LightOS 582 (firmware 1.440000)
unless an entry says otherwise. Paths like `light-reader/scripts/ci.sh` are in our public repos
([light-reader](https://github.com/yarosz/light-reader), [light-doom](https://github.com/yarosz/light-doom),
[light-chess](https://github.com/yarosz/light-chess)); `light-sdk/...` paths are in Light's SDK.

Start with Light's own SDK README and `docs/`; this file covers what they don't. Sections: hardware and
display, games, rendering and frame rate, build plugin rules, shipping through Light, SDK lifecycle,
getting adb on the phone, emulator, driving devices from scripts, measuring performance, local CI.

Some commands below use [mise](https://mise.jdx.dev), which pins the JDK and Android tools per repo;
`mise run <task>` runs a repo's tasks.

## Hardware and display

- The LP3 (model TLP301, Android 14) runs at 480 dpi on a 1080×1240 panel. The app area is 1080×1168
  px (365×360 dp), almost square. The system bars take the rest.
- LightOS is portrait. Its own `com.lightos.MainActivity` declares `screenOrientation=portrait`. Its
  tools never rotate mid-use; the camera, the one exception, opens in landscape and stays there.
  Users have no rotation control, because quick settings can't be reached from the LightOS launcher.
  Lock a Tool with `orientation = "portrait"` in `lighttool.toml`. That is the only value the plugin
  accepts.
- Android letterboxes a portrait-locked app whose area is shorter than it is wide. On the LP3 that
  margin is 5 dp, the same limit LightOS's own UI lives within (light-reader `DESIGN.md`).
- The panel has one display mode, 60.000004 Hz (`adb shell dumpsys display`, `renderFrameRate 60`):
  a refresh interval is 16.67 ms and nothing faster can be unlocked.
- Hardware keys that reach a Tool's `onKeyDown` (verified by physical press with the frame probe,
  2026-09-27): volume up `KEYCODE_VOLUME_UP` 24 (gpio-keys, scan 115), volume down `KEYCODE_VOLUME_DOWN`
  25 (pmic_resin, scan 114), the shutter's half press `KEYCODE_FOCUS` 80 and full press
  `KEYCODE_CAMERA` 27 (gpio-keys), the scroll wheel `KEYCODE_WHEEL_CCW` 317 and `KEYCODE_WHEEL_CW` 318
  (Pixart pat9126ja optical sensor, one event per detent; a short spin is 20–40 events) and its click
  `KEYCODE_WHEEL_CLICK` 319 (gpio-keys, scan 66). POWER and HOME never reach a Tool (`LightActivity`
  treats BACK/HOME as system keys; POWER sleeps the phone, which also drops adb). The `WHEEL_*`
  keycodes are Light's additions, mapped in `/system/usr/keylayout/Generic.kl`; `LightDeviceKeys` in
  the keyboard library names the same seven. Returning true from `onKeyDown` keeps LightOS from
  seeing the key while the Tool is open; return false and `LightActivity` forwards it to LightOS
  (`LightServiceMethod.DeviceKeyEvent`). Reader turns Pages with the volume keys.
- Consume a key on its key-up as well as its key-down (found by Chess on the LP3, 2026-09-28).
  `LightActivity.onKeyDown`, `onKeyUp` and `onKeyMultiple` each ask the screen separately, and forward
  any `LightDeviceKeys` key the screen declines to LightOS. So a wheel click that a Tool used on key-down
  still toggled the flashlight on its key-up (dumpsys media.camera: torch requested by `com.lightos`).
  For every key a Tool handles, return true from `onKeyDown` (auto-repeat arrives there, with
  `repeatCount > 0`) and from `onKeyUp`. `onKeyMultiple` only sees `ACTION_MULTIPLE`, which the input
  system hasn't sent since API 29, so returning true there too costs nothing (not checked on the LP3). A
  key a Tool doesn't handle should return false everywhere, so LightOS keeps the brightness and flashlight.
- Button positions (106 × 71.5 mm body, held upright): scroll wheel high on the left edge (click =
  flashlight, turn = brightness); on the right edge from the top, volume up, a long home button, volume
  down, and the two-stage shutter about three-quarters of the way down; power with the fingerprint
  sensor on the top edge, right end. With both thumbs on the lower screen, every one of these is out of
  reach without shifting grip, and the shutter sits under the ball of the right index finger at thumb
  height (checked by hand). Held sideways with the top to the left, the shutter is under the right index
  finger like a camera shutter and the volume keys under the left one.
- The fingerprint sensor is not an input device: a light touch emits no input event (`getevent`), and
  only the biometric stack sees it. A Tool can't use it as a button.
- LightOS applies Android's system grayscale filter (secure `accessibility_display_daltonizer_enabled`
  1, `accessibility_display_daltonizer` 0 = monochromacy). The panel shows color when it is off. A Tool
  can't change it; screenshots (`screencap`) are taken before the filter and show color. LightOS
  (`com.lightos`) runs as `android.uid.system` with `WRITE_SECURE_SETTINGS` granted. Its album flips the
  global filter off while a photo is open and back on when you leave (observed 2026-09-27: four
  1 → 0 → 1 cycles in 66 s, focus `com.lightos` throughout). The SDK has no service method for it, and a
  Light-signed Tool can't get it: lightphone/light-sdk#190 asks for one (a Light developer replied on
  2026-09-03 that it "should be easy", pending an internal check; labeled Internal Light Dev). A dev-signed Tool can: declare `WRITE_SECURE_SETTINGS`, which Light's plugin
  only allows with a local patch, grant it once with `adb shell pm grant <pkg>
  android.permission.WRITE_SECURE_SETTINGS`, and write the setting through a View's `context.contentResolver`,
  restoring it on pause and on crash (github.com/yarosz/light-doom, `color/`). A force-stop while the Tool
  shows leaves the filter off; LightOS doesn't restore it. This is unofficial and unsupported, and a
  Light-signed Tool can't do it.
- Fonts: LightOS UI uses Akkurat, and retail LP3s ship true italics (`/system/fonts/AkkuratLLTT-*Italic.ttf`).
  The emulator draws with Roboto, which is narrower, so a label that fits on the emulator can wrap on the
  phone ("Tap a piece, then a squ…" in Chess). Calibrate text-fit tests on LP3 screencaps.
- Compute limits seen by Chess (2026-09-28): `Runtime.maxMemory()` is 128 MB, and a single busy engine
  thread was scheduled only on the two big A78 cores (6-7). A debuggable build ran a chess engine 3.6×
  slower than a non-debuggable one, so measure a release-like build type.

## Games: what's possible (frame probe and light-doom, 2026-09-27)

- Real-time 2D in Compose Canvas at 60 fps (200 sprites, a text HUD, per-frame garbage), and a full 3D
  software renderer (Doom, 320×200, 35 fps) through a pure-Kotlin WebAssembly interpreter using one core.
  Tap-to-draw is one frame. Nothing needs native code, GL or extra dependencies.
- Landscape by drawing sideways, on-screen thumb controls, the shutter and volume keys as held-grip buttons,
  AudioTrack sound, keep-screen-on, and saves in `filesDir` all work inside the SDK's rules.
- The limits are ergonomic and policy, not speed: the edge buttons are out of reach with thumbs on the
  screen, back always closes the Tool, color needs #190, and whether Light would sign a
  WebAssembly-interpreter build is an open question.

## Rendering and frame rate (frame probe, 2026-09-27)

Measured with a throwaway frame-probe Tool (not published) that draws a fixed load, logs frame
intervals from `withFrameNanos`, and logs every hardware key.

- Compose Canvas holds 60 fps on the LP3 for a 2D game's load: 200 moving 48 px rects, with or without
  three `drawText` HUD lines relaid each frame, and with ~1 MB/frame of garbage: P99 frame interval
  16.62 ms and 0.0–0.1% missed vsyncs over 30 s per case. The draw callback costs 1.5 ms (JIT-warm)
  to 3.4 ms (first 30 s) for the 200 rects, less when a busier frame clocks the CPU up, and about
  2.3 ms more for the three text lines (P50). Use
  a `withFrameNanos` loop that bumps a state read only in the draw phase (no recomposition, no layout).
- Touch-to-draw on the LP3: pointer event time to the draw of the first frame that reflects it, with
  the loop running: P50 14–17 ms, P90 19–23 ms, max 41 ms (two runs of n=20). Scanout adds up to one more 16.67 ms,
  so budget roughly 30–50 ms tap-to-glass.
- `SurfaceView` (hardware or software canvas) and `GLSurfaceView`, hosted through Compose's
  `AndroidView` with the factory parameter left untyped, compile, pass the plugin's scans
  (`BLOCKED_IMPORTS` covers neither `android.view` nor `android.opengl`) and Light's builder simulation,
  and also run at 60 fps; at this load they gain nothing (software canvas misses 4.5% of vsyncs).
  For games we chose Compose Canvas.
- One `SurfaceView` per process: a second one added to the Tool's window after the first was removed
  never receives `surfaceCreated` (LP3 and emulator, Android 14; not root-caused).
- Emulator frame timings are the Mac's, not the SM4450's; use the emulator only to check that a probe
  runs, never for numbers.
- A landscape Tool, despite portrait-only: lay the content out a quarter turn clockwise with
  `Modifier.layout` (measure with swapped constraints, `placeWithLayer { rotationZ = 90f }`). Compose
  maps touches through the rotation, so pointer input needs no changes. The app area is nearly square,
  so nothing is lost. light-doom does this.
- Keep the screen on without the Activity: an attached `View` inside `AndroidView` with
  `keepScreenOn = true` sets the window's `FLAG_KEEP_SCREEN_ON` (visible in `dumpsys window windows`),
  and removing it clears the flag.
- Heavy compute (a WebAssembly interpreter running Doom at 35 fps, about one core) is fine in pure
  Kotlin on the SM4450: thermal status stayed 0 over 3 minutes (no longer soak measured). Run an engine on
  its own single-thread dispatcher and hand frames to the UI through two swapped buffers.
- Drawing an indexed 320×200 framebuffer: fill an ARGB `IntArray` from the palette on the engine thread,
  `Bitmap.setPixels` it in the draw callback, `drawImage(..., filterQuality = FilterQuality.None)` scaled up.
  Cheap at 35 fps; a second palette (tuned grays) costs nothing.
- The LP3 has no WebGPU adapter (`androidx.webgpu`: "No supported adapters"); the emulator does. Code with a
  WebGPU path takes its fallback on the phone (Mood's classic backend swaps red and blue).
- Audio: `android.media.AudioTrack` (16-bit PCM stereo, `USAGE_GAME`) plays from a Tool with no permission;
  the LP3 opened it at 44,100 Hz.
- Game controls that fit the hands: held sideways (top to the left) both thumbs are on the screen and the
  index fingers rest on the shutter (right) and the volume keys (left); the wheel falls under the left palm,
  so leave it to LightOS (return false: brightness and flashlight keep working). Floating sticks (origin at
  touch-down) beat fixed ones on the small screen. A held shutter auto-repeats `onKeyDown` with
  `repeatCount > 0`, and a full press comes after the half press (FOCUS 80, then CAMERA 27). Injected
  `adb shell input keyevent 317/318/319` reach a Tool like the physical wheel on the LP3, which makes controls
  testable there. The emulator maps them to keycode 0, so wheel handling can only be tested on the phone.

## Build plugin rules (enforced on every build)

Source of truth: `light-sdk/plugin/src/main/kotlin/com/thelightphone/plugin/` (`LightSdkPlugin.kt`,
`LightToolMetadata.kt`). A summary is in light-reader `AGENTS.md`, "Platform rules".

- Kotlin only, with Compose UI, inside `LightScreen` / `LightViewModel`. `.java` files fail the build.
- No reflection, including `.javaClass` (so no `getResourceAsStream`). No `android.content.Context`.
  NDK/JNI is disallowed by Light policy (light-sdk #139). Reach files through the screen's `filesDir`.
- Dependencies and permissions must be on the allowlist (`ALLOWED_DEPENDENCIES`). Already on the
  classpath through the SDK: `kotlinx-serialization-json` (use its JSON tree API; `@Serializable` with
  `ignoreUnknownKeys` drops unknown fields) and kotlinx coroutines. No EPUB, game-engine, or
  LLM-runtime libraries are allowlisted. Allowlisted for networking and crypto:
  `com.squareup.okhttp3:okhttp` (its WebSocket client included), `io.ktor`,
  `org.bouncycastle:bcprov-jdk18on` and `org.sol4k:tweetnacl` (`LightSdkPlugin.kt:26-44`, SDK 57bbbd0).
- `android.os.Process` and `java.lang.Thread` (priority, a `ThreadFactory`) and `java.util.concurrent` pass
  the scan.
- The plugin generates the manifest from `tool/lighttool.toml`, so cleartext HTTP is off.
- Android resources under `src/main/res/` (fonts, for example) are accepted.
- R8 with resource shrinking keeps `res/font` working (the paths shorten to `res/<xx>.ttf`).
- The plugin bans `srcDir`, so a debug-only source set shared with another build type is impossible.
  Add a separate build type instead (light-chess has a `benchmark` type on its v2 branch).
- Whatever `lighttool.toml` declares, the SDK merges INTERNET, CAMERA and six more permissions into every
  Tool APK and bundles ML Kit's `libbarhopper_v3.so`, about 20 MB of a 28 MB release APK (a debug APK was
  about 85 MB). Checked by Chess on SDK v0.1.2.
- The generated manifest leaves `allowBackup=true`. Keep anything secret out of backed-up storage (light-chess
  v3 keeps the credentials for its move-relay server under `no_backup`).
- XML on the device: Android's Expat parser silently drops undeclared entities (`&nbsp;` in XHTML with no
  DTD) where the JVM's parser in unit tests reports them. Rewrite named entities to numeric references
  before parsing. Treat every EPUB and feed as hostile: Reader sends all XML through one parser in which
  external entities and DTDs resolve to nothing, with size caps.
- Compose text on clipped pages: descenders leak into the next page unless the `LineHeightStyle` is
  centred and untrimmed. Hyphenation adds 15-25% to layout cost.
- Assets: `lightContext.readAsset(path)` reads `src/main/assets/`. Light's extractor accepts only listed
  extensions there (`.png .jpg .jpeg .webp .gif .svg .json .txt .md .ttf .otf .bin .dat .csv .html .css`; not
  `.wasm` or `.js`), at most 5 MB per file, 10,000 files and 100 MB in all (`light-sdk/builder/lightbuilder/
  allowlist.py`). Rename binaries to `.bin`.
- A library that isn't allowlisted can be vendored as source: the plugin scans it like your own code, so it
  must be reflection-free Kotlin. Kotlin Multiplatform libraries need flattening, because a Tool module
  can't be multiplatform: take commonMain plus the source sets Android compiles, delete each `expect` and
  strip `actual` (moving the `expect`'s default arguments onto the `actual`), and match the library's
  compiler flags and opt-ins in `tool/build.gradle.kts`. The SDK compiles with Kotlin 2.3.20, so Kotlin 2.4
  collection literals (`= []`) need rewriting. light-doom's `scripts/vendor.py` does all of this for Chasm
  (about 80,000 lines of Chasm, 84,000 with its dependencies); the result passes the plugin and the builder rehearsal.
- Two pure-Kotlin chess engines vendor cleanly (light-chess `spikes/`, 2026-09-27). Pirarucu
  (`pirarucu-common`, GPLv3) builds unchanged on Kotlin 2.3.20 with one replaced `expect object`, and the
  plugin's own scan rules find 0 violations. Karballo (MIT, Kotlin 1.2) needs 15 `lowercase()` fixes and
  its resource-loading book reader replaced. Both get perft exact. Neither has been built inside the plugin
  or run on the phone yet.

## Shipping through Light

- `serverPackage` must be `com.lightos` in the committed `lighttool.toml`: Light's builder builds
  releases from a committed hash. The emulator needs `com.thelightphone.sdk.emulator`, so swap it at
  build time and restore it afterwards (light-reader `scripts/emulator-build.sh`). light-sdk #231 /
  PR #234 proposes a plugin guard for this.
- Rehearse Light's builder locally before a release: an unsigned, minified release build
  (`./gradlew :tool:assembleRelease -DlightSdk.unsigned=true`), then `scripts/light-build.sh`, which
  clones the committed HEAD. Uncommitted work is invisible to it.
- Light's CONTRIBUTING AI policy: every issue, PR description, comment and reply in lightphone repos
  comes from a person, not an AI. PRs from a fork need a maintainer to approve their workflow runs.
- Two distribution tiers. Light-signed: Light builds the committed source with its unmodified plugin,
  signs it, and it installs from the Tool directory on any LP3. Dev-signed: signed with the SDK's public
  development key (`lightsdk-dev.jks`); it shows in the Tools list only on a phone with Allowed tools
  set to "All tools" (see Wi-Fi install below). `adb shell pm grant` only works for a permission the Tool declares, and the plugin decides
  what can be declared, so a grant-based feature (like color) exists only in dev-signed builds.
- Versions (light-reader `RELEASING.md`): `versionName` must be semver with no pre-release suffix and
  `versionCode` must go up with every release, so a rollback ships as a new release. Moving a phone from a
  dev-signed build to the Light-signed one of the same Tool means uninstalling, which deletes the Tool's
  data.
- With Allowed tools set to "All tools", LightOS lists and opens any installed app that has a launcher
  activity, not only SDK Tools (light-doom, 2026-09-27: garado's metronome, a plain Android app, runs next
  to the SDK Tool Cardinal Bible). The SDK marker only matters
  to the SDK server's `ClientFilterLevel`. Sensitive runtime permissions (RECORD_AUDIO,
  SYSTEM_ALERT_WINDOW) stay ungranted.
- Wi-Fi install through the File Manager's Tool Inbox works on LightOS 582 (light-doom, tested on the
  LP3, 2026-09-27). It is an install route only.
  - Setup, the minimum (tested 2026-09-28):
    1. Dial `*7412369#` in the Phone tool and press call. That reveals
       Settings > Debug, where the File Manager lives. Debug
       never appears without it. It toggles: dialing it again hides Debug. Installed Tools stay listed,
       because Allowed tools is unchanged.
    2. Set Allowed tools to "All tools". Dashboard developer mode is needed to reach that setting.
    Anything below "All tools" hides dev-signed Tools and ordinary apps from the Tools list; they stay
    installed.
  - Folder: the inbox is backed by `/data/user/0/com.lightos/files/apkInbox`. The File Manager never
    creates it, and an upload into a missing folder fails with "Invalid path". Adding one of Light's own
    Tools with the (+) button at the bottom of the Tools list creates it, and after that it persists.
  - Reaching it: the File Manager opens only from the debug menu (dialer code), and its web root lists
    only "Photos" and "Tool Inbox". Only the File Manager's on-screen Back button stops the server, and the
    next open gets a new `#key`. The Home gesture returns to the QR screen with the same key. The server
    and key survive screen-off and Doze: 31 of 31 Wi-Fi checks over 68 minutes, unplugged and idle. One
    scan covers several installs in a row (light-doom, 2026-09-27).
  - Upload: send `Authorization: Bearer <key>`. POST the raw bytes as `application/octet-stream` to
    `/api/upload/Tool%20Inbox/<name>.apk`, then send an empty POST to `/api/notify/Tool%20Inbox`.
    LightOS then installs the APK and deletes it. An update keeps `adb pm grant`s.
  - Quirks: `GET /api/files/Tool%20Inbox` returns 500 whenever the inbox is empty (LightOS can't
    serialize its own error), so only a refused upload shows the folder is missing. There are no CORS
    headers, and the OPTIONS preflight gets 401, so a hosted web page can't upload; curl, iOS Shortcuts
    or HTTP Shortcuts can. Chrome with secure DNS can't resolve `*.my.local-ip.co` to a LAN address, and
    a Tailscale route for the LAN subnet breaks it.
  - Over USB, `adb forward tcp:54449 tcp:54449` and `https://localhost:54449/#<key>` (the key from the
    phone's QR code) reach it without Wi-Fi.
  - Don't tap "service menu" in Settings > Debug during a session: it restarted the phone.
  - Tooling: [lightphone-wifi-install](https://github.com/yarosz/lightphone-wifi-install) uploads from
    the File Manager URL or from the phone's QR code read by the laptop camera.
  - There's no route into a Tool's own storage, so the inbox can't deliver a Tool's data files (your
    own EPUBs, say).

## SDK lifecycle

- `LightViewModel.onAppPause()` is driven by `LightActivity.onPause()`
  (light-sdk `sdk/client/.../LightActivity.kt`). It is the last hook guaranteed to run before the
  process can be killed, so flush state there. `onScreenHide(screen)` fires on screen navigation.
- LightOS relaunches a Tool's activity when it is reopened after being left, in the same process, and the
  previous screen's `LightViewModel` is never cleared (`onCleared` doesn't run). Anything expensive a view
  model starts (an engine, threads, loops) survives and piles up: three Doom engines ran at once. Keep
  such state in a process-wide object that a new view model re-attaches to.
- `goBack()` from the initial screen finishes the Tool; it calls `onBackPressed()` first, so a view model
  that consumes back must let it through when it wants to close.
- The system back gesture never reaches the screen: `LightActivity` registers its own
  `OnBackPressedCallback` that calls the activity's `goBack()`, which finishes the Tool from the initial
  screen without asking `LightViewModel.onBackPressed()`. A Tool can't intercept it (`androidx.activity` is a
  blocked import). Design for back = leave; keep in-Tool menus on a visible button.
- `LightActivity` keeps its splash up for at least 1 s after `onCreate` (`setKeepOnScreenCondition`), so a
  cold start can't show content sooner: Chess measured about 1.03 s to its first Puzzle (debug build). Set startup
  targets from there.
- Networking: `LightConnectivity` can't report whether a network is VALIDATED, and asking Android
  directly needs a `Context`, so a Tool can't tell a slow server from a captive portal or no route. Reader
  treats a timeout as "can't reach" with Retry.
- After the screen times out, the phone locks; unlocking returns to LightOS, and the Tool is reopened from
  the Tools list (it resumes if its process survived). Keep the screen on during active play instead.
- Background work: `LightWork` (WorkManager) runs one-off and periodic jobs while the Tool is off screen
  and across reboots. Periodic jobs have a 15-minute minimum (`LightWork.kt:155`), the system picks the
  timing, and `LightJobResult.Retry` backs off. LightOS disables Doze, so Doze can't defer these jobs:
  `dumpsys deviceidle` on the LP3 shows `mLightEnabled=false mDeepEnabled=false`, and `force-idle`
  refuses ("not enabled"). Chess checked this on the LP3 on 2026-09-29: a one-off job whose Move had
  failed to send (its relay server was down) delivered it through WorkManager (`Worker result SUCCESS`) once the server
  was back, with no user action.
- A Tool can't alert its user. `android.app.` is a blocked import, so `NotificationManager` is out, and
  LightOS shows no notification shade and ignores notifications from Tool processes
  (`light-sdk/docs/design_decisions/detached_audio.md`). `LightServiceMethod` has no badge or alert method.
- Remote push exists in the SDK as a silent wake: with `enablePushNotifications = true` on the
  `@EntryPoint`, LightOS supplies a UnifiedPush endpoint through Light's server and the payload reaches
  `LightEntryPoint.onPushNotification`. It is shown working only on the emulator (see Emulator below), and the
  client README's push section is a TODO. Whether production LightOS gives third-party Tools an endpoint
  is unknown.

## Getting adb on the phone

- Dial `*7412369#` in the Phone tool and press call. That reveals Settings > Debug. Turn on "Android Dev
  Mode" there: it is USB debugging, and it survives a reboot. A community modding guide warns that the
  toggle can reset LightOS's app layer; on firmware 1.440000 / LightOS 582 (2026-09-24) it didn't.
- Change only that toggle. Don't touch OEM unlocking, "change launcher" or "service menu" (the last one
  restarted the phone).
- "Dashboard developer mode" is a separate switch. It only adds Settings > Developer, where Allowed tools
  lives; you need it to set Allowed tools to "All tools" (see Wi-Fi install above), which dev-signed
  builds need.
- The LP3 drops off USB when its screen is off or its battery is low, so keep it charged and awake while
  scripting (see "Driving devices from scripts").

## Emulator

- Our AVD, `LightPhone3`: `system-images;android-34;default;arm64-v8a` (test keys, no Play Store),
  with `LightOSEmulator.apk` installed as a system app in `/system/priv-app`, set as the home activity,
  animations off. Light's `docs/system_app` says push and special permissions only work with the
  emulator app running as system.
- It must match the LP3: 480 dpi (`adb shell wm density`) and gesture navigation
  (`cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural`). With
  three-button navigation the app area differs and a portrait-locked Tool is pillarboxed.
  light-reader `scripts/ci.sh` refuses to run unless the emulator reports `app=1080x1168` at 480 dpi.
- Boot with `-writable-system -no-snapshot -dns-server 1.1.1.1,8.8.8.8`: the emulator's own DNS
  (10.0.2.3) has silently stopped resolving before.
- Steps to build the AVD: light-chess `scripts/emulator/RECIPE.md`.
- One emulator per Tool, never shared by two sessions at once. Give each its own AVD name and even port
  (`-port 5556`, 5558, ...). Rules for running several:
  - Address every adb call with `-s emulator-<port>`, and never `adb kill-server`. Select your emulator
    by AVD name (`adb -s <serial> emu avd name`), not by the first `emulator-*` line: light-reader
    `ci.sh` does this (`READER_AVD`, light-reader #18) and fails if two emulators report the same name.
  - Don't copy a running AVD's `.qcow2` files: qemu has them open for writing, so the copy can be
    inconsistent. Build the clone from the same system image and repeat the setup above.
  - `cmd package set-home-activity` is lost if the emulator is killed a few seconds later, before the
    setting is saved. Wait for it to persist first (light-chess `scripts/emulator/set-home.sh`).
  - On a fresh AVD, the "ImmersiveModeConfirmation" dialog can hold focus, so dismiss it before any
    `mCurrentFocus` check.
  - Each instance takes 2-4 GB of RAM and host CPU; two at once can slow both.
- Heavy host builds can raise a "System UI isn't responding" dialog on the emulator. light-reader
  `ci.sh` taps Wait.
- In GitHub Actions, `android-actions/setup-android@v3`'s default `tools` package no longer exists
  (2026-09-24); name the packages you need.

## Driving devices from scripts

- Drive with adb through `mise run ui` (`tap <label>`, `key`, `shot`), not android-mcp. `mise run ui` is a stdlib-Python task in
  light-reader (`.mise/tasks/ui`) that prints a compact UI tree with all text, taps by label and chains
  steps. android-mcp was about 0.5 s faster per call, but its snapshot left out non-interactive text,
  so checking content needed screenshots.
- Before every injected key or tap, check that `dumpsys window` `mCurrentFocus` names your Tool. A
  script once sent volume keys to the LightOS home screen and may have left the LP3 ringer at 0/7.
- Say whether the LP3 is attached (`adb devices`) before any step that needs it, and check its serial
  rather than assume which phone it is: an agent once assumed the wrong phone was attached.
- `wm dismiss-keyguard` unlocks a phone with no PIN, so a CI script can wake and unlock the LP3.
- To reach a server on your Mac from the phone, use `adb reverse`. A debug build may use cleartext to
  `127.0.0.1` (and `10.0.2.2` from the emulator); release builds can't.
- `run-as` doesn't work on non-debuggable builds, and a Tool can't read files that adb writes to
  `/sdcard/Android/data/<pkg>`, so trigger benchmark runs through `BuildConfig` fields instead.
- `adb shell dumpsys media.camera` records torch requests. Chess used it as the test oracle for the
  flashlight key-up leak above.
- The LP3 leaves adb the moment its screen turns off (POWER press, sleep, low battery) and comes back
  when woken: scripts must expect `device not found` mid-run, and a hardware-key session must not
  press POWER. A reboot re-enumerated it once when nothing else did (2026-09-27).
- After an LP3 reboot (2026-09-29) it stayed off adb, awake, on two cables and two Mac ports, and
  didn't charge from the Mac. The port controller showed the cause (`ioreg -r -c AppleHPMInterfaceType10
  -l`): `ConnectionActive` flapped Yes/No every ~5 s with `TransportsActive = ("CC")` only, never
  `USB2`. It charged from a USB-C charger, and after a spell on the charger, plugged back into the Mac
  it came up with `("CC","USB2")` and on adb. So: phone off adb, not charging from the Mac, CC-only
  flapping → plug it into a charger briefly, then back into the Mac. Rebooting the Mac doesn't help.
  The same drop can happen mid-session with the screen awake. Chess saw it about 2 minutes into a
  session (2026-09-29): the phone vanished from macOS's USB list, and the recovery also needed
  developer mode switched on again after the reboot. Afterwards `dumpsys battery` read "AC powered:
  true, USB powered: false" while adb worked. When the phone disappears, stop and ask the maintainer;
  don't retry blindly.
- One phone, several sessions: a run that installs, takes focus or injects input collides with any
  other session's run on the same phone. Take turns through a lease file
  ([docs/how-we-worked.md](docs/how-we-worked.md), [templates/lp3-lease.sh](templates/lp3-lease.sh)),
  and stop only your own package when you finish.

## Measuring performance

- Measure on the LP3, not the emulator, and on a non-debuggable build (3.6× faster for Chess's
  engine). Log timings under a dedicated logcat tag and report P90s;
  light-reader `scripts/perf.sh` is the template (`mise run perf`).
- Reader's reference numbers: Compose text layout costs about 10 ms per 1,000 characters on the LP3 with
  Reader's real styles (light-reader ADR 0007; an unstyled prototype measured 3-4 ms).
  Opening a 165K-character chapter went from 1,940 ms to 111 ms (P90) once only ~10K-character windows
  were laid out, with the rest measured on `Dispatchers.Default`. Frame rate, draw cost and
  touch-to-draw latency: see "Rendering and frame rate" above.

## Local CI pattern

- light-reader `scripts/ci.sh` (`mise run ci`) runs unit tests, the Light-builder simulation, and a
  scripted round trip on the emulator and, when attached, the LP3. It then posts the `signoff/emulator`
  and `signoff/lp3` statuses via `gh api .../statuses`, capping descriptions at GitHub's 140
  characters. Post statuses with `gh api` rather than `gh-signoff`, which hard-codes the description.
