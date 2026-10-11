# Fingerprint on the LP3

The LP3 has a working fingerprint sensor and a standard Android fingerprint stack, but no one can enroll a
fingerprint today, because LightOS sets no device credential (PIN, pattern or password). A Tool can't use the sensor.

Facts below were read on an LP3 (LightOS 582, firmware 1.440000, 2026-10-11, read-only) unless a source is cited.

## What Light has said

- In [light-sdk discussion #173](https://github.com/lightphone/light-sdk/discussions/173) (fenleon, 2026-08-21), a
  developer building a passkey Tool reported that fingerprints can't be enrolled because the LP3 has no enforced lock
  screen, and asked whether the lock screen will become a real Android credential.
- Light's reply (dupontgu, 2026-08-25): no short-term answer. Light has made progress with the sensor in recent
  months. Integrating with Android's lock screen needs help from its manufacturing partner, because it means changing
  Android (AOSP) screens that the partner controls. Light expects to offer "some level of fingerprint functionality
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
 sensor                       Fingerprint Cards (FPC) fpc1541s
```

- The phone declares the `android.hardware.fingerprint` feature. `dumpsys fingerprint` shows one sensor provider,
  no enrolled fingerprints, and no HAL crashes since boot.
- The HAL service runs as a system process with its own SELinux domain. The shell can neither read its binary nor
  call it, which is normal on a production build.
- **Why enrollment is impossible:** Android only enrolls fingerprints after the user sets a PIN, pattern or password.
  On the LP3, `locksettings get-disabled` reports the lock screen as disabled and the password quality is 0, so there
  is no credential to anchor a fingerprint to.
- LightOS (`com.lightos`) holds `MANAGE_FINGERPRINT`, `MANAGE_BIOMETRIC` and other privileged biometric permissions,
  so a Light-built fingerprint feature that doesn't go through the lock screen is technically possible, as Light hinted.
- A light touch on the sensor sends no input event (see [PLATFORM.md](../PLATFORM.md)); only the biometric stack sees it.
- The vendor image also ships a face-authentication HAL service, but the phone declares no face feature.

## What a Tool can do

- **Today:** nothing with the sensor. `BiometricPrompt` and `FingerprintManager` have no enrolled fingerprint to
  match, and a Tool can't set a device credential.
- **Passkeys and biometric-bound keys:** blocked for the same reason: Android binds them to a device credential.
  Passkeys on Android also need a credential-provider app (usually Google Password Manager, which needs Google Play
  services; the LP3 has none), so a third-party provider would be needed too.
- **Later:** whatever Light exposes through the SDK. A Tool-facing fingerprint check that doesn't depend on the lock
  screen would fit what Light described in #173.

## Open questions

- Does enrollment work end to end once a device credential exists? Not yet tested.
- Which fingerprint features will Light expose to Tools, and through which SDK method?
