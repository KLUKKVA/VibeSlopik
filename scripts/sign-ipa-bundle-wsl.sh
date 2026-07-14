#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$ROOT/dist/VibeSlopik.app}"
LDID="${THEOS:-$HOME/theos}/toolchain/linux/iphone/bin/ldid"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH"
  exit 1
fi

if [ ! -x "$LDID" ]; then
  echo "ldid not found: $LDID"
  exit 1
fi

mkdir -p "$APP_PATH/_CodeSignature"

sha1_data() {
  openssl dgst -sha1 -binary "$1" | base64 | tr -d '\n'
}

INFO_SHA="$(sha1_data "$APP_PATH/Info.plist")"
RULES_SHA="$(sha1_data "$APP_PATH/ResourceRules.plist")"

cat > "$APP_PATH/_CodeSignature/CodeResources" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>files</key>
	<dict>
		<key>Info.plist</key>
		<data>$INFO_SHA</data>
		<key>ResourceRules.plist</key>
		<data>$RULES_SHA</data>
	</dict>
	<key>rules</key>
	<dict>
		<key>.*</key>
		<true/>
		<key>Info.plist</key>
		<dict>
			<key>omit</key>
			<true/>
			<key>weight</key>
			<real>10</real>
		</dict>
		<key>ResourceRules.plist</key>
		<dict>
			<key>omit</key>
			<true/>
			<key>weight</key>
			<real>100</real>
		</dict>
	</dict>
</dict>
</plist>
EOF

"$LDID" -S "$APP_PATH/VibeSlopik"
