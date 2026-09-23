# ARchScan — App Store and TestFlight checklist

Version target: **2.7.0**  
Bundle ID: **com.bet0.ARchScan**

## Implemented and checked in the repository

- [x] Store-readiness gate validates Android camera-only permissions, backup disabled, iOS camera-only usage declarations, tracking disabled and the declared UserDefaults privacy reason.
- [x] Store-readiness gate rejects accidental location/tracking declarations and incompatible Android permission declarations before a signed store build.

- [x] iOS deployment target 15.0 or later.
- [x] ARKit capability detection with Basic Scanner fallback.
- [x] RoomPlan hardware detection (iOS 16+ and LiDAR) available as an auxiliary native capability.
- [x] Versioned RoomPlan geometry contract.
- [x] Positioned walls, doors and windows exported in meters.
- [x] RoomPlan contour reconstruction and real 2D area calculation.
- [x] Invalid or incomplete RoomPlan contours rejected safely.
- [x] Camera permission localized in English and Spanish.
- [x] Privacy Manifest included in the Runner target.
- [x] Tracking disabled and no tracking domains declared.
- [x] Export encryption status declared with `ITSAppUsesNonExemptEncryption=false`.
- [x] Application data stored locally.
- [x] Signed IPA workflow prepared for external Apple credentials.
- [x] Store workflow enforces Xcode 26 or later.
- [x] Optional App Store Connect/TestFlight upload is disabled by default.
- [x] IPA audit includes SHA-256, Bundle ID, version, build, signature,
      embedded profile and Privacy Manifest.
- [x] IPA audit rejects expired, debug-enabled, enterprise or mismatched profiles.
- [x] Unsigned iOS compilation and Flutter tests run in CI.

## Apple Developer configuration

- [ ] Active Apple Developer Program membership.
- [ ] App ID registered for `com.bet0.ARchScan`.
- [ ] Apple Development Team ID available.
- [ ] Apple Distribution certificate created and securely stored.
- [ ] App Store provisioning profile created for the exact Bundle ID.
- [ ] Repository secrets configured:
  - `APPLE_TEAM_ID`
  - `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
  - `IOS_CERTIFICATE_PASSWORD`
  - `IOS_PROVISIONING_PROFILE_BASE64`
- [ ] Optional upload secrets configured when CI will upload the IPA:
  - `APP_STORE_CONNECT_API_KEY_ID`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

Never commit certificates, private keys, profiles or passwords.

## Google Play configuration

- [ ] Google Play Console developer account active.
- [ ] App created with application ID `com.bet0.ARchScan`.
- [ ] Play App Signing configured and verified.
- [ ] Production/upload keystore created and stored securely outside Git.
- [ ] GitHub Actions secrets configured:
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_STORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- [ ] Signed AAB workflow passes its final manifest, permission and native-library audit.
- [ ] Store listing, Data Safety answers and privacy/support URLs match the final binary.

Never commit `key.properties`, upload keystores, passwords or private signing material.

## App Store Connect

- [ ] Create ARchScan with Bundle ID `com.bet0.ARchScan`.
- [ ] Confirm app name, subtitle, category and age rating.
- [ ] Add the public support and privacy URLs.
- [ ] Complete App Privacy consistently with local-only storage.
- [ ] Declare that the beta contains no ads, purchases or subscriptions.
- [ ] Upload screenshots made from the final physical build.
- [ ] Run the signed workflow with `upload_to_app_store_connect=true`, or upload
      the audited IPA manually, and wait for processing.
- [ ] Confirm in App Store Connect that the export-compliance answer matches
      `ITSAppUsesNonExemptEncryption=false` and the final binary.
- [ ] Add TestFlight testing notes in English and Spanish.

## Mandatory physical tests

Test at least one non-LiDAR iPhone/iPad and one LiDAR-capable device.

- [ ] Automatic ARKit selection through the same shared AR scanner used by ARCore.
- [ ] Basic Scanner fallback where appropriate.
- [ ] Optional RoomPlan native bridge start, review, confirmation and cancellation.
- [ ] Walls, doors and windows match the physical room.
- [ ] Area and wall orientation match the 2D plan.
- [ ] Oblique walls and continuation from either endpoint.
- [ ] Background, screen lock, unlock and camera recovery.
- [ ] Camera permission denied, granted later and revoked.
- [ ] Project save, reopen and historical-project compatibility.
- [ ] JSON, PDF and DXF export through the iOS share sheet.
- [ ] Delete one project and all local projects.
- [ ] No red screens, frozen camera or duplicated room after cancellation.

## Release gate

Do not submit the open beta until:

1. All CI jobs are green.
2. The signed IPA audit succeeds.
3. TestFlight processing reports no blocking issue.
4. Mandatory physical tests are completed.
5. Store text and privacy answers match the shipped build.
