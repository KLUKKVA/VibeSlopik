#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$ROOT/dist/VibeSlopik.app}"
OUT_PATH="${2:-$ROOT/dist/VibeSlopik.ipa}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

if [ ! -f "$APP_PATH/Info.plist" ]; then
  echo "Info.plist not found in app bundle: $APP_PATH"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/Payload"
cp -R "$APP_PATH" "$TMP_DIR/Payload/VibeSlopik.app"
find "$TMP_DIR/Payload/VibeSlopik.app" -type d -exec chmod 0755 {} \;
find "$TMP_DIR/Payload/VibeSlopik.app" -type f -exec chmod 0644 {} \;
chmod 0755 "$TMP_DIR/Payload/VibeSlopik.app/VibeSlopik"
rm -rf "$TMP_DIR/Payload/VibeSlopik.app"/*.dSYM

rm -f "$OUT_PATH"
cd "$TMP_DIR"
zip -qry "$OUT_PATH" Payload
echo "Wrote $OUT_PATH"
