#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacFeine"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_NAME="$APP_NAME-Installer.dmg"
ZIP_NAME="$APP_NAME-Installer.zip"
CHECKSUM_NAME="$APP_NAME-Installer.sha256.txt"
DMG_PATH="$DIST_DIR/$DMG_NAME"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
CHECKSUM_PATH="$DIST_DIR/$CHECKSUM_NAME"

"$ROOT_DIR/scripts/build_installer_dmg.sh"

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"

(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$DMG_NAME" "$ZIP_NAME"
)

shasum -a 256 "$DMG_PATH" "$ZIP_PATH" > "$CHECKSUM_PATH"

printf "Built release assets:\n"
printf "  - %s\n" "$DMG_PATH"
printf "  - %s\n" "$ZIP_PATH"
printf "  - %s\n" "$CHECKSUM_PATH"
