#!/bin/zsh
set -euo pipefail

APP_NAME="Fantasy Draft"
VERSION="1.0.10"
APP_PATH="./Export/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME}"
NOTARY_PROFILE="fantasy-draft-notary"

rm -rf "./dist"
mkdir -p "./dist"

create-dmg \
  --volname "$VOLUME_NAME" \
  --window-pos 200 120 \
  --window-size 640 420 \
  --icon-size 96 \
  --icon "$APP_NAME.app" 180 190 \
  --app-drop-link 460 190 \
  --hide-extension "$APP_NAME.app" \
  "./dist/$DMG_NAME" \
  "$APP_PATH"

xcrun notarytool submit "./dist/$DMG_NAME" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "./dist/$DMG_NAME"
xcrun stapler validate "./dist/$DMG_NAME"
