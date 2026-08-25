#!/usr/bin/env bash
set -euo pipefail

missing=0
for name in GOOGLE_IOS_CLIENT_ID GOOGLE_SERVER_CLIENT_ID GOOGLE_REVERSED_CLIENT_ID; do
  value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: $name is missing"
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

if [[ "$GOOGLE_IOS_CLIENT_ID" != *.apps.googleusercontent.com ]]; then
  echo "ERROR: GOOGLE_IOS_CLIENT_ID does not look like a Google OAuth client ID"
  exit 1
fi
if [[ "$GOOGLE_SERVER_CLIENT_ID" != *.apps.googleusercontent.com ]]; then
  echo "ERROR: GOOGLE_SERVER_CLIENT_ID does not look like a Google OAuth client ID"
  exit 1
fi
if [[ "$GOOGLE_REVERSED_CLIENT_ID" != com.googleusercontent.apps.* ]]; then
  echo "ERROR: GOOGLE_REVERSED_CLIENT_ID does not look like a reversed Google client ID"
  exit 1
fi
if [[ "$GOOGLE_IOS_CLIENT_ID" == *example* || "$GOOGLE_SERVER_CLIENT_ID" == *example* ]]; then
  echo "ERROR: Google OAuth settings still contain example values"
  exit 1
fi

echo "Google OAuth build configuration: PASS"
