#!/bin/sh
set -eu

fail=0

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "ok: $1"
  else
    echo "missing: $1"
    fail=1
  fi
}

check_cmd bash
check_cmd make
if [ -z "${THEOS:-}" ] && [ -d "$HOME/theos" ]; then
  THEOS="$HOME/theos"
fi

if [ -n "${THEOS:-}" ] && [ -d "$THEOS" ]; then
  echo "ok: THEOS=$THEOS"
else
  echo "missing: THEOS"
  fail=1
fi

if [ -n "${THEOS:-}" ] && ls "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; then
  echo "ok: iPhoneOS SDK found"
  ls "$THEOS"/sdks/iPhoneOS*.sdk
else
  echo "missing: iPhoneOS SDK under \$THEOS/sdks/"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Toolchain is incomplete."
  echo "On Windows, install WSL Ubuntu, install Theos there, then put iPhoneOS*.sdk into \$THEOS/sdks/."
  exit 1
fi

if [ -x "$THEOS/toolchain/linux/iphone/bin/clang" ] || [ -x "$THEOS/toolchain/linux/iphone/bin/clang-11" ]; then
  echo "ok: Theos iOS clang"
else
  echo "missing: Theos iOS clang"
  fail=1
fi

if [ -x "$THEOS/toolchain/linux/iphone/bin/ldid" ]; then
  echo "ok: Theos ldid"
else
  echo "missing: Theos ldid"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Toolchain is incomplete."
  exit 1
fi

echo "iOS build toolchain looks usable."
