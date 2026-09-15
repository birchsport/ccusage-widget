#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CCUsageWidget"
APP="${APP_NAME}.app"
BUILD_ARGS=(-c release --arch arm64 --arch x86_64)

echo "==> Building universal release binary"
swift build "${BUILD_ARGS[@]}"

# Ask SwiftPM for the output dir (it moved from .build/apple to .build/out in
# newer toolchains; hardcoding it shipped a stale binary).
BUILD_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

if [[ ! -f "${BUILD_DIR}/${APP_NAME}" ]]; then
    echo "error: binary not found at ${BUILD_DIR}/${APP_NAME}" >&2
    exit 1
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "${APP_NAME}/Info.plist" "${APP}/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP}"

echo "==> Zipping for transport"
rm -f "${APP_NAME}.zip"
ditto -c -k --keepParent "${APP}" "${APP_NAME}.zip"

echo
echo "Done: ${APP} and ${APP_NAME}.zip"
echo "Recipient: right-click → Open the first time, or run:"
echo "  xattr -dr com.apple.quarantine ${APP}"
