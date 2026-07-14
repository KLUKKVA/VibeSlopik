#!/bin/sh
set -eu

SDK_SOURCE="${1:-}"

if [ -z "$SDK_SOURCE" ]; then
  echo "Usage: sh ./scripts/install-sdk-wsl.sh /path/to/iPhoneOS6.1.sdk-or-archive"
  exit 1
fi

if [ -z "${THEOS:-}" ]; then
  THEOS="$HOME/theos"
fi

if [ ! -d "$THEOS" ]; then
  echo "Theos not found at $THEOS. Run scripts/setup-theos-wsl.sh first."
  exit 1
fi

mkdir -p "$THEOS/sdks"

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [ -d "$SDK_SOURCE" ]; then
  SDK_DIR="$SDK_SOURCE"
else
  TMP_DIR="$(mktemp -d)"
  case "$SDK_SOURCE" in
    *.zip)
      unzip -q "$SDK_SOURCE" -d "$TMP_DIR"
      ;;
    *.tar|*.tar.gz|*.tgz|*.tar.xz)
      tar -xf "$SDK_SOURCE" -C "$TMP_DIR"
      ;;
    *)
      echo "Unsupported SDK archive format: $SDK_SOURCE"
      exit 1
      ;;
  esac
  SDK_DIR="$(find "$TMP_DIR" -type d -name 'iPhoneOS*.sdk' | head -n 1)"
fi

if [ -z "${SDK_DIR:-}" ] || [ ! -d "$SDK_DIR" ]; then
  echo "Could not find iPhoneOS*.sdk in $SDK_SOURCE"
  exit 1
fi

SDK_NAME="$(basename "$SDK_DIR")"
DEST="$THEOS/sdks/$SDK_NAME"

if [ -e "$DEST" ]; then
  echo "SDK already exists: $DEST"
else
  cp -R "$SDK_DIR" "$DEST"
fi

echo "Installed SDK: $DEST"
sh ./scripts/check-ios-toolchain.sh
