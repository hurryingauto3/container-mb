#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Builds a distributable DMG for ContainerMenuBar: the app plus a drag-to-install
# /Applications shortcut, a volume icon, and (when available) a styled Finder
# layout via `create-dmg`. Falls back to `hdiutil` if `create-dmg` is not present.
#
# The DMG is code-signed (ad-hoc by default; Developer ID when SIGN_IDENTITY is
# set). For a fully notarized download, notarize and staple the DMG afterwards
# (see SECURITY.md / the release workflow).

set -euo pipefail

APP_NAME="ContainerMenuBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON="$ROOT_DIR/Resources/AppIcon.icns"
VERSION_FILE="$ROOT_DIR/Sources/ContainerCore/AppVersion.swift"

cd "$ROOT_DIR"

# Build/sign the app bundle first (single source of truth for version + signing).
"$ROOT_DIR/Scripts/package-app.sh"

MARKETING_VERSION="$(sed -n 's/.*marketing = "\([0-9][0-9.]*\)".*/\1/p' "$VERSION_FILE" | head -1)"
DMG="$DIST_DIR/${APP_NAME}-${MARKETING_VERSION}.dmg"
VOLNAME="$APP_NAME $MARKETING_VERSION"
rm -f "$DMG"
# Remove any leftover create-dmg read-write intermediates from a previous run.
rm -f "$DIST_DIR"/rw.*.dmg

if command -v create-dmg >/dev/null 2>&1; then
  echo "Building styled DMG with create-dmg..."
  STAGING="$(mktemp -d)/payload"
  mkdir -p "$STAGING"
  cp -R "$APP_DIR" "$STAGING/"
  # create-dmg can exit non-zero for cosmetic reasons even when the DMG is fine.
  create-dmg \
    --volname "$VOLNAME" \
    --volicon "$ICON" \
    --window-pos 200 120 \
    --window-size 600 380 \
    --icon-size 120 \
    --icon "$APP_NAME.app" 150 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 450 190 \
    "$DMG" "$STAGING" || true
  rm -rf "$STAGING"
  rm -f "$DIST_DIR"/rw.*.dmg
fi

if [[ ! -f "$DMG" ]]; then
  echo "Building DMG with hdiutil..."
  STAGING="$(mktemp -d)/payload"
  mkdir -p "$STAGING"
  cp -R "$APP_DIR" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"
  rm -rf "$STAGING"
fi

# Sign the DMG (ad-hoc by default; Developer ID when SIGN_IDENTITY is set).
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"

echo "Built $DMG"
