#!/bin/sh
set -eu

echo "== VibeSlopik WSL/Theos setup =="
echo "This script installs Linux packages and Theos inside the current WSL distro."
echo

if [ "$(uname -s)" != "Linux" ]; then
  echo "Run this inside WSL/Linux."
  exit 1
fi

echo "== Updating apt package lists =="
sudo apt update

echo "== Installing build dependencies =="
sudo apt install -y \
  bash \
  ca-certificates \
  clang \
  curl \
  git \
  ldid \
  make \
  perl \
  sudo \
  unzip \
  xz-utils \
  zip

if [ -z "${THEOS:-}" ]; then
  export THEOS="$HOME/theos"
fi

if [ ! -d "$THEOS" ]; then
  echo "== Installing Theos to $THEOS =="
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
else
  echo "== Theos already exists at $THEOS =="
fi

PROFILE="$HOME/.profile"
if ! grep -q 'export THEOS=' "$PROFILE" 2>/dev/null; then
  {
    echo ''
    echo '# VibeSlopik/Theos'
    echo 'export THEOS="$HOME/theos"'
    echo 'export PATH="$THEOS/bin:$PATH"'
  } >> "$PROFILE"
fi

mkdir -p "$THEOS/sdks"

echo
echo "== Toolchain status =="
echo "THEOS=$THEOS"
command -v clang || true
command -v make || true
command -v ldid || true

if ls "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; then
  echo "iPhoneOS SDK found:"
  ls "$THEOS"/sdks/iPhoneOS*.sdk
else
  echo "No iPhoneOS SDK yet. Put iPhoneOS6.1.sdk into:"
  echo "$THEOS/sdks/"
fi

echo
echo "Setup complete. Restart WSL shell or run:"
echo "  export THEOS=\"$THEOS\""
echo "  export PATH=\"\$THEOS/bin:\$PATH\""
