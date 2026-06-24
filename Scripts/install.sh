#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# One-line installer for ContainerMenuBar.
#
#   curl -fsSL https://raw.githubusercontent.com/hurryingauto3/container-mb/main/Scripts/install.sh | bash
#
# Downloads the latest release, installs it to /Applications (falling back to
# ~/Applications if that is not writable), clears the Gatekeeper quarantine flag
# on this ad-hoc-signed build, and launches it.

set -euo pipefail

REPO="hurryingauto3/container-mb"
APP="ContainerMenuBar"
ASSET="${APP}.app.zip"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: ContainerMenuBar only runs on macOS." >&2
  exit 1
fi

echo "Finding the latest ${APP} release..."
TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
if [ -z "${TAG}" ]; then
  echo "error: could not determine the latest release tag." >&2
  echo "See https://github.com/${REPO}/releases" >&2
  exit 1
fi

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

DEST="/Applications"
if [ ! -w "${DEST}" ]; then
  DEST="${HOME}/Applications"
  mkdir -p "${DEST}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${APP} ${TAG}..."
curl -fsSL "${URL}" -o "${TMP}/${ASSET}"

echo "Installing to ${DEST}/${APP}.app..."
ditto -x -k "${TMP}/${ASSET}" "${TMP}/unpacked"
rm -rf "${DEST:?}/${APP}.app"
mv "${TMP}/unpacked/${APP}.app" "${DEST}/${APP}.app"

# This build is ad-hoc signed (not notarized); clear quarantine so Gatekeeper
# does not block the first launch.
xattr -dr com.apple.quarantine "${DEST}/${APP}.app" 2>/dev/null || true

echo "Launching ${APP}..."
open "${DEST}/${APP}.app"

echo ""
echo "Installed ${APP} ${TAG} to ${DEST}."
echo "Look for the box icon (\"ctr N\") in your menu bar."
