# How to push this to a new GitHub repository

Below are the exact terminal commands to take this archive and turn
it into a brand-new GitHub repo. Replace `<USER>` and `<REPO>` with
your GitHub username and the new repo name (e.g. `basir-ios`).

## 1. Create the empty repo on GitHub

Browser: github.com → New repository → Name: `basir-ios` (or your
choice) → Public or Private → **Do NOT initialize with README,
.gitignore, or license** (we already have them). Click Create.

GitHub will show you the new repo's HTTPS / SSH URL. Copy it.

## 2. Initialize git and push

```bash
# Unzip this archive somewhere local, then:
cd Basir-iOS

git init
git add .
git commit -m "Initial commit: Basir iOS v0.2

Full iOS port of the Basir Android app.
- 31 Swift files, ~4,190 lines
- iOS 17+, SwiftUI, zero external dependencies
- Codemagic CI for cloud iOS builds (no Mac required)
- Features: ask, translate, math extraction, walking mode, PDF
  conversion, voice conversation, emergency, personal memory,
  archive, share extension"

git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

## 3. Connect Codemagic

1. Go to [codemagic.io](https://codemagic.io) → sign in with GitHub.
2. Click **Add application** → authorize Codemagic to see your repos.
3. Pick the repo you just pushed.
4. Codemagic detects `codemagic.yaml` automatically and shows the
   three workflows defined inside it.
5. Click **Start new build** → choose `ios-simulator-build`.
6. First build takes ~4-6 minutes. Watch the logs in the browser.

## 4. Verify the build

When the build succeeds Codemagic shows:
- ✅ green checkmark
- a downloadable `Basir.app` artifact (the simulator bundle)
- a `Basir.app.dSYM` artifact (debug symbols)

If the build fails, share the log output and we can fix it.

## 5. Next steps (when ready)

- **Buy an Apple Developer Program membership** ($99/year) to run on
  real devices and publish to App Store.
- **Create the App Store Connect app entry** for bundle id
  `com.basir.ai`. Upload an icon, a description, screenshots.
- **Upload your Distribution certificate** to Codemagic.
- **Uncomment the `ios-app-store-build` workflow** in `codemagic.yaml`.
- **Push to `release/ios` branch** to trigger an automatic TestFlight
  upload.
- **Add internal testers** in App Store Connect → TestFlight.
- **Submit for review** when internal testing is positive.

The whole "first commit → live on App Store" path typically takes
3-6 weeks of calendar time, mostly waiting on App Store review
(usually 1-3 business days per submission).
