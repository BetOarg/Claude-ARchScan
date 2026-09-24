# ARchScan — Secrets, security and release configuration audit

Target release: **2.7.0**  
Repository baseline: **main @ ae2e90ea5bb88a0ebf21ba9ab72e259bbaeef66f**

## Repository findings

- [x] Production signing material is excluded from Git.
- [x] Android `key.properties` and upload keystores are ignored.
- [x] iOS certificates, provisioning profiles and private keys are not stored in the repository.
- [x] Generated iOS `Flutter/ephemeral` content is ignored and excluded from the repository secret scanner.
- [x] The repository security audit scans text files for private keys, GitHub tokens, AWS access keys and JWTs.
- [x] The security audit rejects real `.env` files and sensitive binary formats, while allowing only the documented public test-key fixture.
- [x] Android release signing uses GitHub Actions secrets and creates temporary `key.properties`/keystore files only during the release job.
- [x] iOS release signing uses GitHub Actions secrets and temporary runner keychain/profile files.
- [x] Temporary Android/iOS signing material is removed in `always()` cleanup steps.
- [x] Release workflows use `permissions: contents: read`.
- [x] Android release configuration never falls back to the debug key for a release build.
- [x] iOS release audit rejects debug-enabled, expired, enterprise, or mismatched provisioning profiles.

## Android release secrets

Configure these as GitHub Actions secrets before a signed Play build:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The release workflow validates that all four exist before creating signing files.

## iOS release secrets

Configure these as GitHub Actions secrets before a signed App Store build:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`

Only when CI should upload directly to App Store Connect, additionally configure:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

The upload input is disabled by default.

## Runtime permissions and privacy surface

### Android

The manifest declares camera access as the only functional runtime permission and explicitly removes transitive microphone and network permissions from the merged manifest.

Camera and AR capabilities remain optional so unsupported devices can use the Basic Scanner.

The application also has:

- `android:allowBackup="false"`
- `android:fullBackupContent="false"`

### iOS

The app declares only `NSCameraUsageDescription` for camera access. The privacy manifest declares tracking disabled and the UserDefaults accessed-API reason already used by the app.

No location or tracking usage descriptions are present.

## Release procedure

1. Configure the production secrets in GitHub; never commit their values.
2. Run the Android store workflow and verify the signed AAB audit.
3. Run the iOS store workflow with upload disabled first and verify the signed IPA audit.
4. Only after the IPA has passed validation, optionally rerun with App Store Connect upload enabled.
5. Compare Bundle ID/application ID, version and build number with the store listing.
6. Retain the generated SHA-256 audit records with the release artifact.
7. Revoke/rotate production credentials immediately if they are ever exposed.

## Remaining external configuration

These cannot be completed safely from repository contents alone:

- Android Play Console signing configuration and production upload key creation.
- GitHub Actions production secrets.
- Apple Developer membership/team/certificate/profile setup.
- App Store Connect API key creation, if automated upload is desired.
- Final store privacy declarations and support/privacy URLs.
- Physical-device validation of the signed release binaries.

## Gate

The repository is security/release-configured for beta, but **production secrets are an external configuration step**. A signed store artifact must not be considered ready until the corresponding release workflow passes with the real production credentials and the final binary is physically validated.
