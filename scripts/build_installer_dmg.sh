#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacFeine"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$DIST_DIR/$APP_NAME-installer"
DMG_PATH="$DIST_DIR/$APP_NAME-Installer.dmg"
VOLUME_NAME="$APP_NAME Installer"

"$ROOT_DIR/scripts/build_app_bundle.sh"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

printf "Built installer: %s\n" "$DMG_PATH"
