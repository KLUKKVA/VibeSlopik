#!/bin/sh
set -eu

APP_PATH="${1:-}"
OUT_PATH="${2:-VibeSlopik.ipa}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Usage: sh ./scripts/package-ipa.sh /path/to/VibeSlopik.app [output.ipa]"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
case "$OUT_PATH" in
  /*) FINAL_PATH=$OUT_PATH ;;
  *) FINAL_PATH="$PWD/$OUT_PATH" ;;
esac
mkdir -p "$(dirname -- "$FINAL_PATH")"
rm -f "$FINAL_PATH"
mkdir -p "$TMP_DIR/Payload"
cp -R "$APP_PATH" "$TMP_DIR/Payload/"

(cd "$TMP_DIR" && zip -qry "$FINAL_PATH" Payload)
echo "Wrote $FINAL_PATH"
