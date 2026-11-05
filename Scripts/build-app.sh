#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:---local}"
case "$MODE" in
    --local) OUTPUT="$PWD/dist" ;;
    --release)
        : "${DEVELOPER_ID_IDENTITY:?Set a Developer ID Application signing identity}"
        : "${NOTARY_PROFILE:?Set a stored notarytool Keychain profile}"
        : "${RELEASE_BUNDLE_ID:?Set your stable reverse-DNS bundle identifier}"
        [[ "$DEVELOPER_ID_IDENTITY" == "Developer ID Application:"* ]] || { echo "Developer ID Application identity required" >&2; exit 1; }
        [[ "$RELEASE_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo "Invalid bundle identifier" >&2; exit 1; }
        OUTPUT="$PWD/dist/release"
        ;;
    *) echo "Usage: $0 [--local|--release]" >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 1; }
# Explicit local escape hatch for environments unable to run SwiftPM's nested sandbox.
BUILD_ARGS=(-c release)
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == 1 ]]; then BUILD_ARGS+=(--disable-sandbox); fi
if [[ -n "${CLOUDBEACON_BUILD_SYSTEM:-}" ]]; then BUILD_ARGS+=(--build-system "$CLOUDBEACON_BUILD_SYSTEM"); fi
APP_VERSION="${APP_VERSION:-1.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "APP_VERSION must be x.y.z" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "BUILD_NUMBER must be numeric" >&2; exit 1; }
swift build "${BUILD_ARGS[@]}"
mkdir -p "$OUTPUT"
STAGING="$(mktemp -d "$OUTPUT/.cloudbeacon.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/CloudBeacon.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/checks .build/module-cache
cp .build/release/AWSStatus "$APP/Contents/MacOS/AWSStatus"
cp Sources/StatusCore/Resources/aws-feeds.json "$APP/Contents/Resources/aws-feeds.json"
swiftc -module-cache-path .build/module-cache Scripts/GenerateIcon.swift -parse-as-library -o .build/checks/generate-icon
.build/checks/generate-icon "$STAGING/CloudBeacon.iconset"
iconutil -c icns "$STAGING/CloudBeacon.iconset" -o "$APP/Contents/Resources/CloudBeacon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.awspulse</string>
<key>CFBundleName</key><string>CloudBeacon</string>
<key>CFBundleDisplayName</key><string>CloudBeacon</string>
<key>CFBundleExecutable</key><string>AWSStatus</string>
<key>CFBundleIconFile</key><string>CloudBeacon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
if [[ "$MODE" == --release ]]; then
    plutil -replace CFBundleIdentifier -string "$RELEASE_BUNDLE_ID" "$APP/Contents/Info.plist"
    codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" --options runtime --entitlements Scripts/AWSStatus.entitlements "$APP"
    ditto -c -k --keepParent "$APP" "$STAGING/submission.zip"
    xcrun notarytool submit "$STAGING/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
else
    codesign --force --sign - --options runtime --entitlements Scripts/AWSStatus.entitlements "$APP"
    echo "LOCAL BUILD: ad-hoc signed, not authenticated for public distribution."
fi
codesign --verify --strict --verbose=2 "$APP"
# Publish only a complete verified bundle; never sign stale files from a prior build.
rm -rf "$OUTPUT/CloudBeacon.app"
mv "$APP" "$OUTPUT/CloudBeacon.app"
if [[ "$MODE" == --release ]]; then
    ditto -c -k --keepParent "$OUTPUT/CloudBeacon.app" "$STAGING/CloudBeacon.zip"
    mv "$STAGING/CloudBeacon.zip" "$OUTPUT/CloudBeacon.zip"
fi
echo "Built $OUTPUT/CloudBeacon.app"
