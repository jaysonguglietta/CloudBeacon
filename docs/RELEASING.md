# Build and release guide

## Local development

Run `bash Scripts/check-all.sh`, then `bash Scripts/build-app.sh --local`. The script uses Swift's default backend unless explicitly overridden with `CLOUDBEACON_BUILD_SYSTEM=native` for toolchains with the known backend initialization problem. `SWIFTPM_DISABLE_SANDBOX=1` is an explicit trusted-local-build escape hatch for environments that cannot run SwiftPM's nested sandbox; it does not disable App Sandbox in the built product and is not a default.

A clean staging directory prevents stale bundle files from entering the new artifact. Compilation, icon generation, plist assembly, signing, and strict verification must succeed before replacement of the local `dist/CloudBeacon.app`. The app is sandboxed and hardened but ad-hoc signed. This mode requires no signing secrets and is not an authenticated public release.

Version defaults are 1.1.0 (build 2). Override with `APP_VERSION=x.y.z` and numeric `BUILD_NUMBER`; malformed values fail before building. Increase build numbers for delivered artifacts. The internal executable/target remains AWSStatus; display name and bundle output are CloudBeacon. Keeping the existing local bundle ID preserves preferences and login registration.

## Public distribution gate

This repository does not contain signing keys or notarization credentials. On a properly provisioned release Mac:

```sh
export DEVELOPER_ID_IDENTITY='Developer ID Application: Your Team (TEAMID)'
export NOTARY_PROFILE='your-stored-keychain-profile'
export RELEASE_BUNDLE_ID='your.stable.bundle.identifier'
export APP_VERSION='1.1.0'
export BUILD_NUMBER='2'
bash Scripts/check-all.sh
swift test
bash Scripts/build-app.sh --release
```

The release script requires Developer ID Application identity, stored notarytool profile, and a validated explicit bundle ID. It signs with a timestamp and hardened runtime/entitlements, submits for notarization, staples and validates the ticket, assesses Gatekeeper, and verifies the bundle before output. Credentials are supplied outside source control; do not paste Apple passwords, API keys, private keys, or tokens into scripts, issues, or documentation. Source publication to GitHub does not imply a notarized binary release.

Decide the production bundle identity before the first public version. Do not casually change it afterward. Moving from the local test identifier requires explicit preference/cache/login migration or a documented clean installation. Maintain one stable installed location. The current script builds for its host architecture; if distributing to Intel and Apple Silicon, produce and verify the advertised artifacts with matching toolchains rather than claiming universal support.

## Before publishing a binary

1. Pass automated checks and resolve any CI failures for the exact commit.
2. Complete the manual matrix in [TESTING.md](TESTING.md), including install, permissions, accessibility, sleep/wake, and upgrade.
3. Record supported OS/architectures and toolchain. Validate minimum OS compatibility with a real supported system.
4. Verify Developer ID authority, notarization/stapling, Gatekeeper, bundle metadata, and app icon on a clean Mac.
5. Publish a versioned artifact and concise changes/known limits; keep credentials outside the repository.

No automatic updater is included. Initial upgrades are manual: quit all instances, replace at the same path, relaunch, and confirm version/preferences/login state. No release is considered complete just because source code was pushed.
