#!/bin/sh
set -eu

if [ -z "${THEOS:-}" ]; then
  echo "THEOS is not set. Install Theos first."
  exit 1
fi

if ! command -v make >/dev/null 2>&1; then
  echo "make is not installed."
  exit 1
fi

if ! ls "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; then
  echo "No iPhoneOS SDK found under \$THEOS/sdks/."
  echo "Put iPhoneOS6.x.sdk or another compatible legacy SDK there first."
  exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT/ios/LegacyRemote"
make clean package FINALPACKAGE=1

APP_PATH="$(find .theos -type d -name VibeSlopik.app | head -n 1)"
if [ -n "$APP_PATH" ]; then
  sh "$ROOT/scripts/package-ipa.sh" "$ROOT/ios/LegacyRemote/$APP_PATH" "$ROOT/dist/VibeSlopik.ipa"
fi
