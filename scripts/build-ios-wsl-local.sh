#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

export THEOS="${THEOS:-$HOME/theos}"
export PATH="$THEOS/bin:$PATH"

SRC="$ROOT/ios/LegacyRemote"
BUILD_ROOT="$HOME/VibeSlopik-build"
BUILD_APP="$BUILD_ROOT/LegacyRemote"
APP_OUT="$ROOT/dist/VibeSlopik.app"

rm -rf "$BUILD_APP"
rm -rf "$APP_OUT"
mkdir -p "$BUILD_ROOT" "$ROOT/dist"
cp -R "$SRC" "$BUILD_APP"

cd "$BUILD_APP"
chmod -R u+rwX,go-rwx .
make clean package FINALPACKAGE=1

cp -R "$BUILD_APP/.theos/_/Applications/VibeSlopik.app" "$APP_OUT"
bash "$ROOT/scripts/package-ipa-wsl.sh" "$APP_OUT" "$ROOT/dist/VibeSlopik.ipa"
echo "Wrote release package $ROOT/dist/VibeSlopik.ipa"
