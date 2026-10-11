# Fingerprint on the LP3

The LP3 has a working fingerprint sensor and a standard Android fingerprint stack. Out of the box no one can
enroll a fingerprint, because LightOS sets no device credential (PIN, pattern or password). With a PIN set, the
whole path works: enrollment, fingerprint unlock, and app keys that only a fingerprint can release. What's missing
is a LightOS way to set it up. Passkeys stay blocked for other reasons (see below).

Facts below were read on an LP3 (LightOS 582, firmware 1.440000, 2026-10-11) unless a source is cited. The stack
survey was read-only; the PIN test changed the phone and then restored it.

## What Light has said

- In [light-sdk discussion #173](https://github.com/lightphone/light-sdk/discussions/173) (fenleon, 2026-08-21), a
  developer building a passkey Tool reported that fingerprints can't be enrolled because the LP3 has no enforced lock
  screen, and asked whether the lock screen will become a real Android credential.
- Light's reply (dupontgu, 2026-08-25): no short-term answer. Light has made progress with the sensor in recent
  months. Integrating with Android's lock screen needs help from its manufacturing partner: Light has been asking it
  for changes to Android (AOSP) screens, and the partner has had more pressing work. Light expects to offer "some level of fingerprint functionality
  relatively soon", but independent of Android's lock screen.

## The stack on the LP3

```
 LightOS (com.lightos)        a privileged system app; holds the fingerprint and biometric management permissions
        │
 Android framework            biometric and fingerprint services; 1 sensor, Class 3 ("strong"), 0 fingerprints
        │
 vendor fingerprint HAL       android.hardware.biometrics.fingerprint (AIDL), plus a vendor extension from the
        │                     sensor maker (com.fingerprints.fpc.extension)
 kernel driver
        │
 sensor                       Fingerprint Cards (FPC) fpc1541s, built into the power button on the top edge
```

- The phone declares the `android.hardware.fingerprint` feature. `dumpsys fingerprint` shows one sensor provider,
  no enrolled fingerprints, and no HAL crashes since boot.
- The HAL service runs as a system process with its own SELinux domain. The shell can neither read its binary nor
  call it, which is normal on a production build. Its binary keeps the AOSP sample name (`…-service.example`), but
  it logs as `fpc_fingerprint_hal` while enrolling: it is FPC's real HAL.
- Android isn't told where the sensor is: the framework's side-mounted (`config_sfps_sensor_props`) and
  under-display sensor settings are empty. So Android's enrollment screen says "It's on the back of your phone".
- **Why enrollment is impossible:** Android only enrolls fingerprints after the user sets a PIN, pattern or password.
  On the LP3, `locksettings get-disabled` reports the lock screen as disabled and the password quality is 0, so there
  is no credential to anchor a fingerprint to.
- LightOS (`com.lightos`) holds `MANAGE_FINGERPRINT`, `MANAGE_BIOMETRIC` and other privileged biometric permissions,
  so a Light-built fingerprint feature that doesn't go through the lock screen is technically possible, as Light hinted.
- A light touch on the sensor sends no input event (see [PLATFORM.md](../PLATFORM.md)); only the biometric stack sees it.
- The vendor image also ships a face-authentication HAL service, but the phone declares no face feature.

## The PIN test (2026-10-11)

A temporary PIN was set over adb (`locksettings set-pin`), a fingerprint enrolled, and both removed afterwards
(`locksettings clear` also deletes the enrolled fingerprints).

- **Enrollment:** `am start -a android.settings.FINGERPRINT_ENROLL` opens stock Android Settings: confirm the PIN,
  an introduction, then "touch the sensor" until "Fingerprint added", about 30 seconds of touches. `dumpsys
  fingerprint` went from 0 to 1 enrolled fingerprint.
- **App keys:** a test app (plain Android, not a Light Tool) found `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`
  = success. It generated an AES key that needs a strong biometric for every use; Keystore placed it in the TEE
  (`KeyInfo.getSecurityLevel()` = TEE) and enforces the rule in secure hardware. Using the key without a fingerprint
  failed (`KEY_USER_NOT_AUTHENTICATED`). `BiometricPrompt` with the key as its `CryptoObject` accepted one touch,
  and the key then encrypted data.
- **Locking and unlocking:** with a PIN set, pressing the power button locks the phone. Pressing it again shows
  Android's stock lock screen (keyguard: big clock, date, notifications, a lock icon). Unlocking it leads to the
  LightOS clock screen (date and a circle), which asks for nothing. So the phone shows two screens in a row.
  - Fingerprint: a touch on the sensor at the keyguard unlocks. A press of the power button with the finger on
    the sensor wakes and unlocks in one step, skipping the keyguard.
  - PIN: tapping the keyguard's lock icon opens the PIN pad (bouncer); the PIN unlocks.
- The keyguard's look can't be changed without system access, but an app can draw its own screen on top of it
  (`Activity.setShowWhenLocked` with `KeyguardManager.requestDismissKeyguard`), and the fingerprint still unlocks
  through it. The community launcher [Luma](https://github.com/vandamd/Luma) uses this to give a Light-styled
  fingerprint lock screen. The stock keyguard and PIN pad still appear after a restart or when the PIN is asked for.
  Not tested in this survey.
- Not tested: the restart case. On an emulator, Android required the PIN after a restart before it accepted a
  fingerprint, as stock Android does.

## What a Tool can do

- **Today, out of the box:** nothing with the sensor. `BiometricPrompt` and `FingerprintManager` have no enrolled
  fingerprint to match.
- **Once the owner has set a PIN and enrolled a fingerprint:** standard `BiometricPrompt` and biometric-bound
  Keystore keys work (see the PIN test). LightOS has no screen for this, but Android's stock screens are on the
  phone: the `android.app.action.SET_NEW_PASSWORD` and `android.settings.BIOMETRIC_ENROLL` intents open them.
  Whether a Light Tool may launch them is up to Light's Tool rules; this was not tested from a Tool.
- **Later:** whatever Light exposes through the SDK. A Tool-facing fingerprint check that doesn't depend on the lock
  screen would fit what Light described in #173.

## Passkeys

Not possible on stock LightOS, even with a PIN and an enrolled fingerprint. Two separate things block them:

1. **Android's Credential Manager is switched off.** On Android 14, passkey providers (for example KeePassDX,
   Bitwarden or Proton Pass, which work without Google Play services) plug into the framework's Credential
   Manager. The LP3 ships its UI package (`com.android.credentialmanager`), but the system doesn't declare the
   `android.software.credentials` feature, so the `credential` service never starts and no provider can be
   selected. Only the system image can declare that feature; adb can't.
2. **The bundled browser can't do passkeys without Google Play services.** Upstream Chromium on Android (the LP3
   ships Chromium 133) answers WebAuthn calls with "not implemented" when Google Play services is missing.
   [Cromite](https://github.com/uazo/cromite/blob/master/build/patches/Add-setting-to-enable-Credman-for-passkeys.patch)
   added a setting (October 2025) that routes passkeys through Credential Manager without Google Play services
   on Android 14, so with item 1 fixed, Cromite and a provider app would cover websites.

Native apps using Jetpack `androidx.credentials` reach the framework Credential Manager directly on Android 14, so
they would work too once item 1 is fixed. Using the phone as a passkey for a computer (QR code and Bluetooth) needs
more than that and isn't covered here.

## Open questions

- Which fingerprint features will Light expose to Tools, and through which SDK method?
- Will LightOS declare `android.software.credentials`, so passkey providers can work?
- May a Tool open Android's PIN and fingerprint setup screens?
