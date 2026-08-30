#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 "$PROJECT_DIR/tools/verify_project.py" "$PROJECT_DIR"

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -list -project "$PROJECT_DIR/BasirConvert.xcodeproj" >/dev/null
  echo "Xcode project enumeration: OK"
fi


