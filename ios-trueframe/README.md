# TrueFrame

An accessible iPhone camera and **non‑generative** photo‑straightening app for
blind and low‑vision photographers.

> **Product principle:** *Correct the photographer's camera geometry — never
> rewrite the photographer's scene.*

The "Fix Photo" workflow only performs deterministic geometric operations
(rotate → level → crop the empty corners). It never uses generative AI,
outpainting, or synthetic fill. Every output pixel comes from the source image
(aside from normal interpolation), and the original is always preserved.

---

## Architecture

Clean, single‑responsibility modules (grouped by folder under `TrueFrame/`):

| Module | Responsibility |
|---|---|
| **`Core/ProcessingPolicy`** | Policy enum (`authenticitySafe` / `enhancedNonGenerative` / `generativeExperimental`) and operation taxonomy. |
| **`Core/AuthenticityGuard`** | Central gate that refuses generative ops in protected flows + the machine‑readable `EditingProvenance` record. |
| **`Core/CropSolver`** | Pure geometry: largest valid (source‑only) crop of a rotated image; "Maximum Original Content". |
| **`Core/GeometricImageProcessor`** | Core Image rotate + crop (+ perspective from 4 corners). Non‑generative. |
| **`Core/QualityScore`** | Purely *technical* 0–100 score (levelness/sharpness/exposure/framing/obstruction). |
| **`Core/BeforeAfterReport`** | Text‑first, VoiceOver‑ready description of exactly what changed. |
| **`Camera/MotionLevelManager`** | CoreMotion roll/pitch → live `LevelReading`; shake magnitude. |
| **`Camera/CameraManager`** | AVCaptureSession: sampled preview frames + full‑res photo capture. |
| **`Vision/FrameAnalyzer`** | On‑device luma analysis: blur (Laplacian variance), exposure (histogram), obstruction, sky/ground. |
| **`Vision/SubjectFramingEngine`** | Vision human/face **composition** boxes (no identity). |
| **`Vision/OCRManager`** | Vision text recognition (Arabic + English), read‑only. |
| **`Feedback/FeedbackPriority`** | Pure rules: one prioritized instruction + smart throttling. |
| **`Feedback/AccessibleFeedbackManager`** | Speech (script‑aware) + directional haptics. |
| **`Guidance/FrameGuidanceCoordinator`** | The real‑time loop fusing motion + vision → guidance → speech/haptics. |
| **`Photos/PhotoLibraryManager`** | Saves a **new** corrected copy + provenance JSON; never overwrites. |
| **`App/*`** | SwiftUI: Home, accessible Camera, post‑capture Review. |

### The correctness/priority loop (blind‑usability core)

Only **one** instruction is ever spoken at a time, in this order:
`safety → major framing → severe tilt → subject clipped → blur → exposure →
composition → status`. It is re‑announced only when severity meaningfully
changes, disappears, or returns (`GuidanceThrottle`). This is fully unit‑tested,
camera‑free.

---

## Build

Requires Xcode 15+ and [XcodeGen](https://github.com/yonsson/XcodeGen).

```bash
cd ios-trueframe
xcodegen generate
open TrueFrame.xcodeproj
```

CI (`.github/workflows/trueframe.yml`) builds for the iOS Simulator and runs the
unit tests on every push.

---

## Authenticity guarantee

- Protected workflows run under `ProcessingPolicy.authenticitySafe`.
- `AuthenticityGuard.authorize(_:)` **throws** on any generative operation — the
  app refuses to synthesize rather than doing it silently.
- Each correction writes an `EditingProvenance` record: rotation, crop rect,
  cropped‑area fraction, applied operations, whether AI analysis ran, and
  `generativeModelAlteredPixels` (always `false` in safe mode).
- The UI shows: *"Authenticity Safe: No generative image editing was used."*

## Privacy

On‑device by default. The camera guidance, leveling, straightening, crop,
perspective, blur detection, framing, and OCR all work **offline**. No image is
uploaded without explicit consent; a future optional AI‑description feature will
be architecturally separate and clearly disclosed.

---

## Status (this foundation) & next steps

**Implemented:** authenticity policy + guard + provenance; deterministic
rotate/crop engine with largest‑valid‑crop math; motion leveling; prioritized &
throttled guidance; on‑device blur/exposure/obstruction/sky‑ground; Vision
human/face framing; Arabic/English OCR; quality score; before/after report;
accessible SwiftUI camera + review; save‑as‑copy with provenance; unit tests +
CI.

**Next:** document‑mode auto‑capture & edge tracking; full keystone/perspective
auto‑estimation; import + batch analysis; reversible edit‑history UI; on‑device
voice commands (Speech); burst best‑frame selection; ProRAW/DNG passthrough;
the separate, opt‑in AI description feature; expanded accessibility test suite.

> This is a serious foundation, structured for daily real‑world use — not a
> throwaway prototype. Accuracy, accessibility, privacy, reversibility, and
> photographic authenticity are prioritized over flashy AI.
