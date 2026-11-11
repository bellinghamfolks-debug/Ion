# Basir iOS build 43 — approved scope

Approved: improvements T1–T20, features M1/M2/M15/M19, major interface and terminology update, expanded quality report. Human Style remains removed.

## Implemented surfaces

- M1: still-scene conversation with bounded prior-turn context, reset on new photo, explicit paid request, VoiceOver answer focus.
- M2: structured image-relative object localization, reject invalid/unknown locations, left/center/right haptics. This analyzes captured frames; it does not offer live navigation.
- M15: local PDF/image OCR privacy review, custom sensitive phrases, selectable full-line redactions, orientation-normalized raster PDF export. Original text is not embedded in the redacted PDF. Users must review detection; names and missed OCR are not inferred.
- M19: local-video MP4 export with on-device speech. Short freeze intervals allow complete narration without losing original dialogue. YouTube streams are not downloaded/exported.

## Improvement coverage and limits

1. T1: stable IDs in provisional reading; explicit latest-answer focus. Existing reader and library navigation retained. Device VoiceOver acceptance remains required.
2. T2: named stages/byte progress retained; last recorded activity added.
3. T3: authenticated provisional PDF reading of up to 20 ordered pages/100,000 characters. Final artifact checks remain mandatory. Requires updated server endpoint.
4. T4: persistent queue hold and task priority; currently running task is not interrupted.
5. T5: existing persistent background transfer, checksum and server source verification retained. Transport resume remains constrained by the existing resumable-upload protocol.
6. T6: content-hash + complete-options deduplication of queued files and concurrent import reservations. Existing server idempotency retained.
7. T7: existing server cancellation confirmation retained; cancellation/status rechecked after local audit.
8. T8: thermal/Low Power Mode-aware local OCR parallelism and bounded page rendering.
9. T9: all warnings, exact available page evidence, checks, suggested next steps and shareable text report. Missing historical evidence is explicitly unknown.
10. T10: retry only failed PDF pages as a separate result; preserve the original partial result. Other types retain existing checkpoint resume.
11. T11: advisory normalized numeric and approved-glossary consistency audit for extractable full-source PDF/DOCX. No name inference or false accuracy guarantees; selected ranges/scan-only sources are not compared against an entire source.
12. T12: optional cell navigation with row/column/header announcements; existing row reading retained.
13. T13: speech-only pronunciation rules for complete terms; source/translation text unchanged.
14. T14: existing interruption handling, reading position and stuck-speech recovery retained. New pronunciation applies to document speech and local audio export.
15. T15: independent original/narration audio levels, existing duck/pause modes, pronunciation in video speech. VoiceOver retains system-controlled volume.
16. T16: in-app access to the existing owner-only detailed cost ledger through secure browser UI; no use of the shared app credential to bypass owner authentication.
17. T17: existing independent server ledger retains records 12 months from last activity and survives local result deletion.
18. T18: review file sizes and explicitly delete only generated temporary privacy/video exports. Source/library/task data excluded.
19. T19: generic errors no longer expose raw underlying exception text; actionable localized recovery retained. Bearer token redaction corrected in diagnostics.
20. T20: added migration, structured-location, numeric normalization, pronunciation and PDF redaction regression tests. Full source checks and backend suite passed; current iOS simulator/device builds remain subject to CI completion.

## Verification

- Source verification: 95 app Swift sources, 17 test files, 6 reference pages, 10 reference tables (unchanged binary icon checked in full-repository CI).
- Backend: 530 tests passed after provisional-preview changes.
- Build 42 removal: simulator tests and unsigned device build passed.
- Build 43: do not describe it as compiled/tested/released until the latest macOS workflow completes. Foreground video export and camera/OCR require real-device acceptance; simulator results do not establish camera accuracy or successful installed Arabic speech voices.
