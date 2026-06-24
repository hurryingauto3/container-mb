#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Builds ContainerMenuBar.app into dist/.
#
# Versioning: the marketing version is read from Sources/ContainerCore/AppVersion.swift so the
# bundle, the UI, and the git tag all agree on a single source of truth.
#
# Signing: by default the bundle is ad-hoc signed (codesign -s -) with the hardened runtime so it
# launches cleanly on the build machine. For distribution, export a Developer ID identity and let
# the script use it:
#
#     SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/package-app.sh
#
# then notarize and staple the result (see SECURITY.md).

set -euo pipefail

APP_NAME="ContainerMenuBar"
BUNDLE_ID="dev.local.ContainerMenuBar"
CONFIGURATION="${CONFIGURATION:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VERSION_FILE="$ROOT_DIR/Sources/ContainerCore/AppVersion.swift"

cd "$ROOT_DIR"

# Single source of truth for the version. Extract the string literal assigned to `marketing`.
MARKETING_VERSION="$(sed -n 's/.*marketing = "\([0-9][0-9.]*\)".*/\1/p' "$VERSION_FILE" | head -1)"
if [[ -z "$MARKETING_VERSION" ]]; then
  echo "error: could not parse marketing version from $VERSION_FILE" >&2
  exit 1
fi
# A monotonic build number derived from git commit count keeps CFBundleVersion increasing across
# releases even when the marketing version is unchanged; fall back to 1 outside a git checkout.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "Packaging $APP_NAME $MARKETING_VERSION (build $BUILD_NUMBER, $CONFIGURATION)"

swift build -c "$CONFIGURATION" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp ".build/$CONFIGURATION/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright (c) 2026 Ali Hamza. Licensed under Apache-2.0.</string>
</dict>
</plist>
PLIST

# Code signing. Ad-hoc by default; a real Developer ID identity when SIGN_IDENTITY is provided.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signing (set SIGN_IDENTITY for distribution builds)"
  codesign --force --sign - --options runtime --timestamp=none "$APP_DIR"
else
  echo "Signing with: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"
fi

codesign --verify --strict --verbose=2 "$APP_DIR"

echo "Built $APP_DIR"
