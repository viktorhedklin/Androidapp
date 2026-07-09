#!/usr/bin/env bash
set -euo pipefail

# Builds GameAutopilot.app from the Swift package in this directory.
#
# Usage:
#   ./build.sh                          # ad-hoc signed (see warning below)
#   ./build.sh --sign "Cert Name"       # signed with a persistent identity
#
# Ad-hoc signing (the default, codesign -s -) derives its identity from
# the binary's content hash, so it changes on *every rebuild* -- macOS
# will make you re-grant Accessibility and Screen Recording permissions
# after every single build. For iterative development, create a one-time
# self-signed "Code Signing" certificate:
#   Keychain Access > Certificate Assistant > Create a Certificate...
#   Name: "GameAutopilotMac Dev", Identity Type: Self Signed Root,
#   Certificate Type: Code Signing.
# Then build with: ./build.sh --sign "GameAutopilotMac Dev"
# That identity is stable across rebuilds, so permissions only need
# granting once. See README.md for the full walkthrough.

cd "$(dirname "$0")"

SIGN_IDENTITY="-"
if [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then
    SIGN_IDENTITY="$2"
fi

APP_NAME="GameAutopilot"
BUNDLE_ID="com.gameautopilot.mac"
BUILD_DIR=".build/release"
APP_DIR="${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/GameAutopilotMac" "${APP_DIR}/Contents/MacOS/GameAutopilotMac"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
if [[ -d "Resources/Assets.xcassets" ]]; then
    cp -R "Resources/Assets.xcassets" "${APP_DIR}/Contents/Resources/" || true
fi

echo "==> codesign (identity: ${SIGN_IDENTITY})"
codesign --deep --force --sign "${SIGN_IDENTITY}" "${APP_DIR}"

echo "==> Done: ${APP_DIR}  (bundle id: ${BUNDLE_ID})"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "    Signed ad-hoc -- identity changes every rebuild, see the"
    echo "    comment at the top of this script for the one-time fix."
fi
echo "    Run:  open ${APP_DIR}"
