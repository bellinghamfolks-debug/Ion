# DocConverter — Android

A native Android port of the DocConverter app. Talks to the same Ion backend as
the iOS app.

## Features
- **PDF → Word**: pick (or receive) a PDF, convert it on the server (Gemini
  vision, exactly like the iOS app), and save the .docx.
- **Glasses Live Reader**: mirror the screen (e.g. the eSight Companion camera
  view) via MediaProjection, OCR each frame on the server (`/convert/live-ocr`),
  and read the text aloud in Arabic/English with Android TTS. No Apple Developer
  account or App Group needed — one foreground service, standard Android APIs.

## Build
```
cd android
gradle assembleDebug        # or ./gradlew assembleDebug once a wrapper is added
```
CI builds the debug APK on every push (see .github/workflows/android.yml) and
uploads it as an artifact.

## Stack
- Kotlin, classic Views (no Compose), coroutines.
- Networking: plain HttpURLConnection (no third-party deps).
- minSdk 26, target/compile 34, AGP 8.5.2, Kotlin 1.9.24, Gradle 8.7.

## Notes / needs device testing
- MediaProjection + foreground service and TTS behaviour need testing on a real
  device (CI only verifies compilation).
- Signing for release/Play Store uses your own keystore (no Apple account needed).
