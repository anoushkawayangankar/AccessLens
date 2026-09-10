# AccessLens — Implementation Status

## Current milestone

| Milestone | Status | Completion gate |
|---|---|---|
| 0 — Product definition + production architecture | **COMPLETE** | Scope/claims, architecture, models, policies, roadmap, and release foundation documented; no feature implementation. |
| 1 — Production iOS application foundation | **COMPLETE** | App shell, typed navigation, composition root, lifecycle/logging/error boundaries, design/accessibility foundation, Xcode test targets, and hygiene established. Debug build and complete unit/UI suites passed on the documented iPhone Simulator. |
| 2 — Onboarding + accessibility foundation | **COMPLETE** | First-run gate, injectable completion store, four-page accessible onboarding, deterministic UI-test launch states, and unit/UI coverage added. No camera, Vision, scanning, or permission functionality introduced. |
| 3 — Production camera runtime | **COMPLETE** | Typed authorization and permission flow, real AVFoundation session/output/preview, lifecycle/interruption/runtime-error handling, deterministic simulator tests, and physical-iPhone QA checklist established. No Vision, analysis, persistence, or networking introduced. |
| 4 — Vision analysis architecture + frame scheduling foundation | **COMPLETE** | Session identity, metadata-only frame normalization, strict bounded scheduler/backpressure, cancellation/stale-result rejection, analyzer boundary, orientation mapping, and thermal/Low Power policy added. No Vision request, OCR, detection, user-facing finding, persistence, or networking introduced. |
| 5 — Production on-device text + signage analyzer | **COMPLETE** | Real local `VNRecognizeTextRequest` integration, normalized text observations, conservative signage candidates, transient Scan presentation/deduplication, and deterministic OCR-boundary tests added. No contrast analysis, persistence, upload, networking, analytics, score, or compliance claim introduced. |
| 6 — On-device visual contrast analysis | **COMPLETE** | OCR-region-only BGRA contrast sampling, testable luminance/ratio/evidence policies, conservative transient low-contrast candidates, Scan presentation, bounded confirmation, and deterministic tests added. No compliance claim, persistence, upload, networking, analytics, or score introduced. |
| 7 — Accessibility finding stabilization + evidence fusion | **COMPLETE** | Framework-independent, session-scoped findings now require repeated text-and-region-consistent usable contrast evidence. Bounded evidence fusion provides stable identity, provenance, expiry, controlled VoiceOver, and honest Scan presentation; findings remain transient and local. |
| 8 — Scan session completion + accessible review | **COMPLETE** | Explicit scan-session lifecycle, idempotent Finish/Discard, late-result rejection, immutable in-memory completed snapshot, accessible Scan Review/Done flow, and deterministic completion/review tests added. No persistence, history, export, new analyzer, networking, analytics, score, or compliance claim introduced. |
| 9 — Production persistence + complete scan history | **COMPLETE** | Actor-owned SwiftData schema v1, finalized-domain mapping, automatic idempotent save with failure/retry review, newest-first History, shared historical review, confirmed individual deletion, and isolated storage/UI regression tests. No raw frames/images/OCR streams, cloud sync, new analyzers, reporting, or export. |

## Planned staged workflow

| Milestone | Planned outcome | Depends on | Completion gate |
|---|---|---|---|
| 1 — App foundation | Minimal production app composition, accessible navigation/onboarding shell, permission education copy; no analysis claims beyond contract | M0 | Tests/build pass; accessibility navigation review; documentation updated. |
| 2 — Onboarding + accessibility foundation | First-run gate, accessible product/limitation/privacy education, deterministic onboarding test controls | M1 | Unit/UI tests, build, and manual accessibility validation plan. |
| 3 — Production camera runtime | Permission, lifecycle-safe camera preview/frame source, interruption/recovery states | M2 | Unit/UI checks plus **USER VALIDATION REQUIRED** physical iPhone camera lifecycle checks. |
| 4 — Analysis architecture + scheduling foundation | Session identity, bounded admission/backpressure, normalized metadata, analyzer boundary, cancellation/staleness, and performance policy; no Vision request | M3 | Deterministic scheduler/cadence/policy tests; camera frames remain metadata-only and local. |
| 5 — On-device text analysis | Vision text normalization, `TextAnalyzer`, and honest text observations | M4 | Analyzer/scheduling/stale-result tests; physical OCR quality validation. |
| 6 — On-device visual contrast analysis | Bounded OCR-region contrast estimation, evidence quality, conservative transient presentation | M5 | Deterministic contrast/policy/stability tests and physical-device visual validation. |
| 7 — Accessibility finding stabilization + evidence fusion | Bounded, explainable observation → candidate → finding promotion and expiry; no persistence | M6 | Domain geometry/association/promotion/expiry/memory tests; UI regression and build. |
| 8 — Scan session completion + accessible review | Finish/discard lifecycle, immutable in-memory review snapshot, accessible review and Done flow; no persistence | M7 | Completion/session-isolation/resource-cleanup tests; UI review regressions and build. |
| 9 — Local saved scans | SwiftData repository, migration/recovery, saved-scan history/review | M8 | Persistence/corruption/migration tests; device storage validation. |
| 10 — Reports/export | Versioned report composition, user-controlled sharing, export privacy UX | M9 | Export tests and physical share-sheet/document validation. |
| 11 — Hardening and release readiness | Accessibility audit, privacy audit, performance/lifecycle hardening, full regression and release build | M1–M10 | All release gates pass, including physical-device QA. |

Future capability expansion (for example, constrained contrast indicators or custom ML) is not implied by this roadmap. It requires a separately approved specification, defensibility review, tests, and validation.

## Milestone checkpoint protocol

At the end of every milestone: complete its scoped implementation; run focused tests, relevant regression tests, and required builds; update documentation; review `git status`; provide the milestone report and await user review; commit reviewed changes; push only with explicit user instruction. Do not begin the next milestone before this checkpoint completes.

## Current implementation inventory

- Foundation implementation: SwiftUI application shell, app-level typed navigation, dependency composition, lifecycle observation, OSLog categories, presentation-safe error value, design tokens, XCTest target, and UI-test target.
- Onboarding implementation: root-gated four-page first-run experience, injectable UserDefaults/in-memory completion store, accessibility-focused controls, and DEBUG-only deterministic test launch overrides.
- Camera runtime implementation: typed AVFoundation authorization service, explicit permission flow, back-camera `AVCaptureSession` controller, bounded/discarding BGRA video output, future frame-source handoff, aspect-fill native preview, lifecycle policy, interruptions/runtime-error recovery, and accessible unavailable states. Camera frames are neither retained nor uploaded.
- Analysis foundation: a one-in-flight/one-pending scheduler owns transient session identity, replacement, cadence, cancellation, stale-result rejection, analyzer protocol, and typed partial-failure output. It retains an opaque camera payload only while an admitted Vision task or the one latest pending frame needs it; frames are then released and never persisted/uploaded.
- Vision/OCR implementation: `VisionTextAnalyzer` performs real on-device `VNRecognizeTextRequest` work behind that scheduler. Results are normalized into text observations and conservatively classified as contextual signage candidates; a sign word alone is never a negative finding.
- Visual contrast implementation: `VisualContrastAnalyzer` consumes only same-frame OCR regions tied to signage candidates, directly samples bounded in-memory BGRA crops, calculates estimated luminance/contrast evidence, and emits a transient potential-low-contrast candidate only after usable evidence. Contrast estimates are not compliance measurements.
- Finding stabilization implementation: `AccessibilityFindingStabilizer` consumes only compact candidates and fuses category, conservative normalized text identity, normalized-region IoU, temporal proximity, usable evidence, and analyzer provenance. Its policy caps tracks at 12, entries at 6 per track, findings at 6, requires 3 consistent observations within 5 seconds, and expires unsupported tracks/findings after 6 seconds. The active Scan list contains only its session-scoped stable findings; it retains no frame, crop, raw Vision object, or persisted data.
- Scan completion/review implementation: `ScanSession` owns a deterministic per-scan lifecycle separate from the analysis generation. Finish invalidates analysis/camera work before taking an immutable `CompletedScan` of already-stabilized findings; Scan Review presents that snapshot with evidence strength, uncertainty, a truthful zero-finding state, limitations, and Done-to-Home. Leave Scan confirms discard instead of silently abandoning live work. Milestone 9 adds the automatic local save described below.
- Milestone 9 extends completed-review lifetime: Finish now automatically saves finalized `CompletedScan` evidence through `CompletedScanRepository`. SwiftData entities are separate from domain values and owned by one repository actor. Stable IDs make repeated equal saves idempotent; conflicting snapshots cannot overwrite original evidence. Failed saves retain review and offer Retry Save. Scan History shows completion dates and potential-finding counts newest first, opens the shared review, and confirms individual cascade deletion. Unsupported records remain listed/deletable rather than being silently discarded. No raw camera/image/crop, raw OCR stream, candidates, or stabilizer buffers are persisted.
- Third-party dependencies introduced: **none**.
- Deployment target: **iOS 17.0**.
- Supported device family: **iPhone**. Supported orientations are portrait, landscape left, and landscape right to support future camera scanning without forcing a single orientation.
- Bundle identifier: **`anoushka.AccessLens`** (preserved from the starter project).

## Milestone 1 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** using `xcodebuild` against that concrete Simulator on 2026-09-03.
- Unit tests: **PASSED**, 4 passed / 0 failed / 0 skipped (`AccessLensTests`).
- UI tests: **PASSED**, 1 passed / 0 failed / 0 skipped (`AccessLensUITests`).

## Milestone 2 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-04.
- Unit tests: **PASSED**, 12 passed / 0 failed / 0 skipped (`AccessLensTests`).
- UI tests: **PASSED**, 2 passed / 0 failed / 0 skipped (`AccessLensUITests`). The first-run flow reached the home shell without a camera permission dialog; the returning-user flow bypassed onboarding deterministically.
- Manual accessibility validation: **USER VALIDATION REQUIRED** for VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, smaller iPhone, and landscape.

## Milestone 3 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-04 with the concrete simulator. The build uses the generated Info.plist key `NSCameraUsageDescription`: “AccessLens uses the camera to inspect your surroundings for potential accessibility barriers.”
- Unit tests: **PASSED**, 22 passed / 0 failed / 0 skipped (`AccessLensTests`). Coverage includes AVFoundation authorization mapping, deterministic permission flow, and camera runtime lifecycle policy.
- UI tests: **PASSED**, 4 passed / 0 failed / 0 skipped (`AccessLensUITests`). Coverage includes onboarding regression plus deterministic denied and authorized camera-navigation states; it does not validate physical camera capture.
- Simulator behavior: an authorized test path enters the real Scan shell but handles absent hardware with an accessible unavailable state. No simulator-specific fake preview is provided.
- Physical iPhone camera validation: **USER VALIDATION REQUIRED** for first request, rear preview/orientation, leave-return, background-foreground, denied/Open Settings, interruption, and a multi-minute session. Vision, frame analysis, persistence, image retention, reports, networking, analytics, and Photos access remain unimplemented.

## Milestone 4 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-04 against the concrete simulator.
- Unit tests: **PASSED**, 33 passed / 0 failed / 0 skipped (`AccessLensTests`).
- UI tests: **PASSED**, 4 passed / 0 failed / 0 skipped (`AccessLensUITests`).
- Analysis policy: one in-flight analyzer Task plus at most one latest pending metadata frame; frames arriving while busy replace the pending descriptor. Normal/fair admission is 0.75 seconds, serious thermal admission is 1.5 seconds, Low Power Mode is at least 1.5 seconds, and critical thermal state suspends/cancels optional work.
- Automated coverage: deterministic scheduler tests verify bounded capacity, latest-frame replacement, stale-result rejection, cancellation, cadence, analyzer-failure isolation, monotonic frame ordering, orientation mapping, thermal policy, Low Power policy, and app composition of frame source to coordinator.
- Vision boundary: no `VNRecognizeTextRequest`, `VNRequest` execution, OCR, contrast analysis, accessibility detection, candidate production, or user-facing finding was introduced. Frames are reduced to metadata and neither retained, persisted, nor uploaded.

## Milestone 5 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-05 against the concrete simulator.
- Unit tests: **PASSED**, 41 passed / 0 failed / 0 skipped (`AccessLensTests`). Coverage includes text whitespace/confidence filtering, metadata/coordinate mapping, case-insensitive signage classification, bounded transient duplication, session isolation, cancellation, and analyzer failure isolation in addition to all prior regressions.
- UI tests: **PASSED**, 4 passed / 0 failed / 0 skipped (`AccessLensUITests`). The deterministic onboarding and camera-navigation paths remain intact; they do not purport to validate live OCR.
- OCR configuration: on-device `VNRecognizeTextRequest`, `.fast`, initial `en-US`, no language correction, minimum text height 0.02, raw confidence admission at 0.35, and normal/fair 0.75-second scheduler cadence. Serious thermal and Low Power Mode use the existing reduced cadence; critical thermal state suspends optional OCR.
- Privacy/lifetime: admitted camera frames and Vision text are in-memory and transient only. Neither camera frames nor recognized text are persisted, uploaded, logged as content, or sent through networking; no Photos, analytics, or third-party dependency was added.
- Physical OCR validation: **USER VALIDATION REQUIRED**. On an iPhone, point the authorized rear camera at clear environmental signs, verify recognized text/signage is plausible and non-spammy, leave Scan and verify analysis stops, then exercise lifecycle/accessibility/thermal conditions. Simulator tests cannot validate live-camera OCR quality or overlay coordinate accuracy.

## Milestone 6 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-05 against the concrete simulator.
- Unit tests: **PASSED**, 51 passed / 0 failed / 0 skipped (`AccessLensTests`). Coverage includes sRGB relative luminance, ratio ordering, normalized crop conversion/clamping/orientation, evidence quality, heuristic classification, outlier-resistant estimation, transient confirmation/deduplication, cancellation, stale-session rejection, and analyzer failure isolation in addition to all prior regressions.
- UI tests: **PASSED**, 4 passed / 0 failed / 0 skipped (`AccessLensUITests`). Existing deterministic onboarding and camera-navigation coverage remains intact; simulator UI tests do not claim live camera contrast validation.
- Contrast policy: process only OCR-derived environmental-signage regions; sample no more than 1,024 BGRA pixels per crop; use trimmed quartile medians; surface only two-confirmation, usable-evidence estimates below 3.0:1 as potential low contrast. The ratio is camera-derived evidence, not a standard/compliance result, and no text-size assumptions are made.
- Privacy/lifetime: crops, pixel samples, contrast observations, and candidates are on-device transient state. None is persisted, uploaded, or logged as content; networking, analytics, Photos, and third-party dependencies remain absent.
- Physical visual-contrast validation: **USER VALIDATION REQUIRED** for black-on-white, light-gray-on-white, white-on-dark, glare/shadow, angled-sign, and motion scenarios, including VoiceOver/Dynamic Type/appearance and thermal/Low Power checks. Simulator tests cannot validate camera-image estimate reliability.

## Milestone 7 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-06 against the concrete simulator.
- Unit tests: **PASSED**, 61 passed / 0 failed / 0 skipped (`AccessLensTests`). Coverage includes IoU and text association, promotion/noise rejection, stable IDs, distinct entities, expiry, session isolation, failure tolerance, bounded-memory behavior, and late-candidate rejection in addition to prior regressions.
- UI tests: **PASSED**, 6 passed / 0 failed / 0 skipped (`AccessLensUITests`). Deterministic Scan states verify a truthful zero-finding state and a stabilized potential-low-contrast presentation without a certification claim; they do not validate live camera evidence.
- Finding policy: only `.potentialLowContrastText` candidates with usable contrast evidence, valid region, and recognized contextual sign text are eligible. Three text-and-region-consistent observations within five seconds promote a finding; five retained observations raise evidence strength from moderate to strong. A finding expires after six seconds without supporting evidence. These are product evidence rules, not a legal or accessibility-certification threshold.
- Privacy/lifetime: findings, evidence summaries, text, ratios, and analyzer provenance remain on-device transient state and are cleared on Scan end/session replacement. They are not saved to UserDefaults, SwiftData, Core Data, files, reports, logs as content, or any network service.

## Milestone 8 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator 26.5, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-09 against the concrete simulator.
- Unit tests: **PASSED**, 73 passed / 0 failed / 0 skipped (`AccessLensTests`). Coverage includes completion snapshots, zero findings, idempotency, late-result rejection, session reset, discard, resource shutdown, snapshot immutability, review presentation, and all prior regressions.
- UI tests: **PASSED**, 10 passed / 0 failed / 0 skipped (`AccessLensUITests`). Deterministic flows cover stable-finding and zero-finding review, Done-to-Home, and a fresh scan without inherited previous findings; they do not validate live camera evidence.
- Privacy/lifetime: a completed scan is an in-memory domain snapshot only. It contains no frame/image/Vision object and is discarded on Done, discard, or app termination. No scan history, finding/text/image persistence, export, network service, analytics, or new analyzer was introduced.
- Physical completion/review validation: **USER VALIDATION REQUIRED** for Finish/Leave behavior, camera/analysis release, background recovery without accidental completion, review accessibility at supported device sizes/orientations, and live evidence behavior on an authorized iPhone.

## Milestone 9 verification record

- Simulator: **iPhone 17 Pro**, iOS Simulator **26.5**, device ID `488A5CFD-DCA8-42B5-8AE9-346DBFBDEE14`.
- Debug build: **PASSED** on 2026-09-09 against the concrete simulator (final source state).
- Complete unit suite: **PASSED**, **92 executed / 92 passed / 0 failed / 0 skipped**. New coverage includes exact domain round trips, zero/multiple findings and ordering, concurrent/idempotent/conflicting saves, deterministic date/ID ordering, missing IDs, selected and cascade deletion, actual disk-store recreation, invalid/unsupported records, unavailable-store handling, completion save failure/retry, history refresh/errors/deletion, and historical-review navigation.
- Complete UI suite: **PASSED**, **15 executed / 15 passed / 0 failed / 0 skipped**. Covers all prior flows plus empty/seeded history, newest-first rows, historical review, deletion confirmation/cancel/delete, and completion → save → History.
- Storage/privacy: only finalized scan metadata and explanatory stabilized finding values are persisted. Text is retained only as contextual evidence in a finalized finding. No schema field stores images, image URLs, frames, crops, screenshots, pixel/sample buffers, raw OCR histories, rejected text, Vision objects, transient candidates, or stabilization buffers. No uploads, networking, analytics, backend, third-party packages, new detector, score, or certification claim.
- Concurrency/schema: one actor lazily creates/owns the SwiftData context away from MainActor; explicit atomic save/rollback; versioned v1 schema and stable enum strings; no context in UI and no new unchecked Sendable annotation. No migration is needed for the first schema; future versions require tested migration stages.
- Accessibility: explicit Home/History/Delete/Retry controls, locale-aware dates, meaningful zero-finding rows/empty states, semantic system colors/fonts, scrolling and wrapping, and shared uncertainty/evidence presentation. Manual VoiceOver, maximum Dynamic Type, Voice Control, Light/Dark, Reduce Motion, Differentiate Without Color, small iPhone, and landscape remain **USER VALIDATION REQUIRED**.
- Storage is in private Application Support with normal iOS file protection and OS backup eligibility; CloudKit is disabled. Device passcode/lock and backup/restore checks remain **USER VALIDATION REQUIRED**. Reporting/export/remediation, future migrations, release hardening, and distribution remain incomplete. Milestone 10 has not begun.
