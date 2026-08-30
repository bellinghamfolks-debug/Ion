#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${BASIR_SERVER_URL:?BASIR_SERVER_URL is required}"
: "${BASIR_CLIENT_TOKEN:?BASIR_CLIENT_TOKEN is required}"

DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/Release-iphoneos/BasirConvert.app"
EXTENSION="$APP/PlugIns/BasirShareExtension.appex"
IPA="$ROOT/dist/Basir_v3.0.0_unsigned.ipa"
SECRET_XCCONFIG="$(mktemp)"
trap 'rm -f "$SECRET_XCCONFIG"' EXIT
chmod 600 "$SECRET_XCCONFIG"
printf 'BASIR_CLIENT_TOKEN = %s\n' "$BASIR_CLIENT_TOKEN" > "$SECRET_XCCONFIG"

rm -rf "$DERIVED" "$ROOT/dist"
mkdir -p "$ROOT/dist"

xcodebuild \
  -project BasirConvert.xcodeproj \
  -scheme BasirConvert \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -xcconfig "$SECRET_XCCONFIG" \
  BASIR_SERVER_URL="$BASIR_SERVER_URL" \
  TARGETED_DEVICE_FAMILY=1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

test -d "$APP"
test -f "$APP/BasirConvert"
test -d "$EXTENSION"
test -f "$EXTENSION/BasirShareExtension"

# Package a genuinely unsigned app and embedded extension. Entitlements remain
# declared in the Xcode project for the distributor's later signing step.
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -name embedded.mobileprovision -delete

PAYLOAD="$ROOT/dist/Payload"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/BasirConvert.app"
(
  cd "$ROOT/dist"
  /usr/bin/zip -qry "$(basename "$IPA")" Payload
)
rm -rf "$PAYLOAD"

test -s "$IPA"
unzip -t "$IPA"
shasum -a 256 "$IPA" > "$IPA.sha256"
echo "Unsigned IPA created: $IPA"

