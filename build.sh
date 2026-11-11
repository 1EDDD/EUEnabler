#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required" >&2
  exit 1
}

xcodegen generate --spec project.yml

DERIVED="$ROOT/.build/DerivedData"
xcodebuild \
  -project "$ROOT/EUEnabler.xcodeproj" \
  -scheme EUEnabler \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/EUEnabler.app"
[[ -d "$APP" ]] || {
  echo "Build did not produce EUEnabler.app" >&2
  exit 1
}

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
[[ "$BUNDLE_ID" == "com.1eddd.eu-enabler" ]] || {
  echo "Unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 1
}

IPA_ROOT="$ROOT/.build/ipa"
rm -rf "$IPA_ROOT"
mkdir -p "$IPA_ROOT/Payload"
ditto "$APP" "$IPA_ROOT/Payload/EUEnabler.app"
(
  cd "$IPA_ROOT"
  /usr/bin/zip -qry "$ROOT/EUEnabler.ipa" Payload
)

unzip -tq "$ROOT/EUEnabler.ipa"
echo "Created $ROOT/EUEnabler.ipa"
