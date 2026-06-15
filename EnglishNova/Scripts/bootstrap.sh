#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen غير مثبت. ثبّته عبر: brew install xcodegen"
  exit 1
fi

xcodegen generate
open EnglishNova.xcodeproj
