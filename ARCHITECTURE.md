# AccessLens — Production Architecture

**Scope:** Production contract with implementation refinements through Milestone 11. Sections labeled with prior milestones record their scope at that time; the Milestone 9 persistence section supersedes the former in-memory-only completed-review lifetime. Export and reporting remain future work.

## Architectural shape

Use a straightforward SwiftUI feature structure with focused Apple-native services and domain models. Keep the domain independent of AVFoundation/Vision types by normalizing framework output at the boundary. Avoid “Clean Architecture” ceremony and giant managers.

```text
Camera frame → bounded scheduler → Vision requests → normalized observations
→ independent analyzers → finding candidates → confidence/evidence policy
→ stabilizer → live stable findings → Finish Scan → immutable completed snapshot
→ local repository save → Scan Review / Scan History → historical Scan Review
```

On a RoomPlan-supported LiDAR iPhone, the Scan camera owner changes—not duplicates—to `RoomCaptureSession`: captured image + reconstructed door/opening surfaces → the same bounded scheduler → OCR/contrast/passage analyzers. Other devices retain the existing AVFoundation path and never infer metric scale from pixels alone.

## Domain model contract

All persistent entities use an opaque UUID (or a future stable typed wrapper) created once; display text is never identity. Timestamps are `Date` in UTC semantics. Persisted records carry a schema version at the scan/document envelope and migrate forward explicitly.

| Model | Core responsibility / fields |
|---|---|
| `AccessibilityScan` | `id`, `schemaVersion`, `createdAt`, `updatedAt`, optional user name, app/model capability metadata, `findings`, retention references. A saved user record. |
| `AccessibilityFinding` | `id`, `scanID` when saved, `category`, `severity`, `assessmentState`, `confidence`, `observation`, `evidence`, `interpretation`, `remediation`, optional spatial region/reference, `createdAt`, `updatedAt`. |
| `FindingCategory` | Closed versioned taxonomy, initially `visibleText` and `textLegibility`; future values only after migration/report compatibility planning. |
| `FindingSeverity` | Impact-priority label (`informational`, `needsReview`, `important`) assigned only by documented policy, not raw Vision scores. It is distinct from confidence. |
| `FindingConfidence` | Product evidence band: `high`, `moderate`, `low`, or `unavailable`, with optional non-user-facing rationale/provenance. |
| `AssessmentState` | `detected`, `possible`, `uncertain`, `unableToAssess`; state governs language and presentation. |
| `Evidence` | Analyzer identifier/version, observation time, source/frame session token, framework evidence summary, quality signals, optional redacted excerpt, and limitations. No raw frame by default. |
| `RemediationSuggestion` | Stable ID, human-readable action, rationale, applicability/limitations, and optional external-standard reference only when separately curated—not asserted as a compliance result. |
| `CapturedSceneReference` | Optional future record of an explicitly retained image: ID, encryption/protection policy, file name (not arbitrary path), capture date, pixel metadata, retention status, and content hash. Findings must work without it. |
| `NormalizedSceneContext` / `FindingCandidate` | Ephemeral, Sendable-friendly value types at analysis boundaries. Candidate IDs are observation/session IDs, never persisted finding IDs. |

`observation` says what the system saw; `interpretation` says why it may matter; `remediation` says what a person may consider doing. These are separate fields and UI sections. Codable applies to value-only persistence/export DTOs; AVFoundation, Vision requests/observations, images, actors, and UI objects never cross Codable boundaries. Keep persistent DTO decoding strict and size bounded. Models crossing actors should be immutable `Sendable` values; framework objects are confined to their owning executor/actor.

## Confidence architecture

An analyzer maps raw signals to a product outcome using category-specific, versioned policy. Vision confidence may contribute but can never be exposed alone or converted directly to an accessibility certainty. Inputs may include repeatability over time, text/OCR quality, image conditions, spatial consistency, and analyzer availability.

| Product outcome | Meaning and presentation |
|---|---|
| `detected` + high/moderate confidence | A defined observation repeated with adequate evidence. “Detected text …”; interpretation remains limited. |
| `possible` + moderate/low confidence | Some evidence merits human review. Explain missing/weak evidence. |
| `uncertain` | Conflicting, unstable, or ambiguous evidence; do not elevate to a stable issue. |
| `unableToAssess` | The requested category cannot be assessed under present conditions or capability; say why and offer a recoverable action. |

Severity communicates review priority, never truth or compliance. No “accessibility score,” pass/fail label, or unqualified percentage is allowed.

## Future camera architecture

- `CameraAuthorizationService`: query/request permission and map it to product-ready states; no UI wording embedded in service errors.
- `CameraSessionController`: owns one configured `AVCaptureSession`, device selection/configuration, start/stop, orientation, and explicit teardown on its designated serial executor/queue.
- `CameraFrameSource`: delivers a bounded stream of sample buffers/frame descriptors; never retains an unbounded queue or copies pixels without a measured need.
- `CameraLifecycleCoordinator`: translates app scene phase, capture interruptions, runtime errors, and capability changes into idempotent session operations and recovery state.

The feature state machine will represent authorization, unavailable, configuring, running, interrupted, failed, and stopped states. It observes background/foreground transitions, audio/video interruptions, media-services reset, orientation, and unsupported hardware. UI does not own AVCaptureSession directly.

## Camera runtime implementation (Milestone 3)

`CameraAuthorizationService` maps `AVCaptureDevice` authorization into the product-ready `CameraAuthorizationState`; `ScanViewModel` owns permission-flow presentation and requests access only from the explicit Enable Camera action. `AppDependencies` composes this service with one application-scoped `CameraSessionController` and `CameraLifecycleCoordinator`. DEBUG launch arguments can substitute an in-memory authorization service for deterministic UI tests; this test-only service never supplies a camera feed and is not selectable from Release UI.

`CameraSessionController` owns a single `AVCaptureSession`, a broadly available back-facing wide-angle camera input (with a back-facing discovery fallback), and one `AVCaptureVideoDataOutput`. All capture session mutation, lifecycle policy, and configuration execute on its dedicated serial session queue; compact `CameraSessionState` updates are delivered on the main actor. The output uses BGRA pixels and `alwaysDiscardsLateVideoFrames`; its delegate does no interpretation and hands buffers immediately to `CameraFrameSource`. No consumer is registered in this milestone, no frame is retained, and neither Vision nor analysis scheduling is present.

The pure `CameraRuntimePolicy` permits the session to run only while Scan is visible, the application is active, authorization is granted, and the session is not interrupted. Repeated policy inputs are idempotent. Leaving Scan, becoming inactive/backgrounded, denial/restriction, and interruption stop or prevent the session. A media-services reset receives at most one recovery attempt; other runtime failures become a typed, presentation-safe unavailable state. `CameraPreview` bridges the controller-owned session through `AVCaptureVideoPreviewLayer`, uses aspect fill, and applies supported modern video rotation angles from the current interface orientation. Physical-device orientation and recovery behavior remain a release-gated validation item.

The Scan surface hides the raw preview from VoiceOver and exposes text-first status and controls. It makes one-time accessibility announcements only for denied/restricted authorization, interruption, and unavailable-camera transitions; it does not announce configuration, camera-running status, frames, or future raw observations.

## Future Vision and analysis pipeline

`AnalysisScheduler` accepts only a current session generation and uses latest-frame-wins behavior. It admits at most one (or a small documented bound of) in-flight analyses; frames arriving while busy replace/drop the pending frame. It sets a cadence based on scene state and device policy, rather than analyzing every capture frame. Each work item carries session generation, frame timestamp, orientation, and cancellation token. Results are rejected if cancelled, stale, from a prior camera generation, or superseded by newer user state.

Vision runs off the main actor. A Vision adapter owns requests/handlers for an analysis job, converts output to normalized value observations, and releases frame resources promptly. `VNObservation` objects terminate at that adapter boundary; only the adapter receives the scheduler's opaque, bounded frame payload. Thermal state and Low Power Mode reduce cadence, disable optional work, and may surface `unableToAssess`; critical thermal state stops optional analysis safely. MainActor only receives compact presentation snapshots.

## Analysis scheduling foundation (Milestone 4)

Milestone 4 introduces the runtime plumbing but **no Vision request, OCR, contrast measurement, analyzer implementation, candidate production, or user-facing finding**. `AnalysisCoordinator` is the focused camera-to-analysis boundary. It creates an opaque `AnalysisSessionID` whenever a visible, active, authorized Scan starts; ending Scan, backgrounding/inactivation, or replacing the session invalidates that ID and cancels current work. `ScanViewModel` owns this transient start/end decision, while `AppDependencies` connects the camera frame source to the coordinator. Neither navigation nor persistence owns analysis state.

The video-output callback does only bounded metadata extraction: presentation timestamp, image-buffer dimensions, connection rotation angle, and mirror state. It immediately reduces that to an immutable, Sendable `AnalysisFrame` descriptor and releases the `CMSampleBuffer`; neither the coordinator nor scheduler retains an AVFoundation/CoreMedia image or sample buffer. Frame sequence is a scheduler-issued monotonic `UInt64`, including across session changes. `AnalysisImageOrientation` maps the output connection rotation/mirroring to `CGImagePropertyOrientation` semantics for a future Vision adapter; device/interface orientation changes must first be applied to the capture/preview connection, then the resulting output connection rotation supplies the analysis mapping. This mapping has deterministic tests.

`AnalysisScheduler` is a lock-protected bounded state machine: exactly **one in-flight analyzer Task** and **one latest pending descriptor** are allowed. New frames during work replace the pending descriptor; no Task is made per frame and no capture-rate queue exists. When work completes, only the latest retained descriptor is considered. An injected performance policy admits work at conservative metadata-timestamp intervals (normal/fair: 0.75 seconds; serious thermal: 1.5 seconds; Low Power Mode: at least 1.5 seconds; critical thermal: suspend/cancel optional analysis). These values are admission controls, not performance claims. A central process-state monitor refreshes this policy on thermal and Low Power Mode notifications. Dropped/replaced-frame counters are transient diagnostic state, not user data.

The scheduler gives each future `AccessibilityAnalyzer` an immutable `AnalysisContext` and accepts only framework-independent `AnalyzerOutput`: `NormalizedObservation` values and pre-stabilization `FindingCandidate` values. A candidate has no severity, compliance meaning, persistence behavior, or presentation path. One analyzer failure becomes a typed `AnalysisFailure` for that pass while remaining analyzers continue; cancellation and stale work produce no published pass. There is currently no output consumer—transient results are deliberately not placed in SwiftUI, navigation, UserDefaults, or persistence.

The coordinator and scheduler use lock-protected mutable state and therefore declare their *container classes* `@unchecked Sendable`; this does not apply to AVFoundation/CoreMedia buffers, which never cross the capture callback. Analyzer protocol inputs/outputs are immutable `Sendable` metadata. The only analyzer Task is the bounded in-flight task, and it runs off the main actor. Result handlers receive compact values only after session/work-ID checks reject stale completion. OSLog categories record session/policy transitions, stale results, and analyzer failures without frame payloads or per-frame log spam.

### Analyzer boundary

Future conceptual protocol:

```swift
protocol AccessibilityAnalyzer: Sendable {
    var identifier: AnalyzerIdentifier { get }
    func analyze(_ context: NormalizedSceneContext) async throws -> [FindingCandidate]
}
```

Initial justified analyzers are `VisionTextAnalyzer`, `VisualContrastAnalyzer`, and a future `TextLegibilityAnalyzer`; the latter consumes documented quality signals and produces review/assessment candidates, not a compliance verdict. `VisionTextAnalyzer` is implemented in Milestone 5 as the sole real Vision request. It uses `VNRecognizeTextRequest` at the scheduler's conservative cadence, maps OCR output to `RecognizedTextObservation`, and applies a small, conservative signage-keyword classifier. `VisualContrastAnalyzer` is implemented in Milestone 6 as a dependent analyzer that consumes only same-frame OCR observations that already produced environmental-signage candidates. `SignageAnalyzer` as a separate semantic engine remains deferred. Each analyzer has isolated deterministic test fixtures and a versioned policy.

## On-device text and signage analyzer (Milestone 5)

`AppDependencies` composes exactly one `VisionTextAnalyzer` into the existing `AnalysisCoordinator`; camera frames cannot reach it except through the one-in-flight/one-pending scheduler. The analyzer uses `VNRecognizeTextRequest` with `.fast` recognition for live environmental signage, no language correction (to avoid rewriting short observed labels), initial `en-US` configuration structured for later localization, a minimum text height of 2% of the image, and a centralized 0.35 raw-Vision-confidence admission filter. The existing normal/fair 0.75-second cadence is the initial OCR cadence; serious thermal/Low Power Mode uses the existing 1.5-second policy and critical thermal state suspends optional OCR.

The scheduler now holds an immutable `AnalysisFramePayload` only for its bounded in-flight/pending lifetime. This narrowly justified `@unchecked Sendable` wrapper encloses a read-only `CMSampleBuffer` because CoreMedia lacks a Sendable annotation; it has one owner after capture handoff, is accessed by only the admitted analyzer task, is never exposed to UI/domain/persistence, and is released on completion, replacement, or cancellation. `AnalysisFrame` remains a compact Sendable metadata value. There is no frame queue, copy, upload, persistence, or frame logging.

`VisionTextObservationMapper` removes empty/pathologically long text, collapses repeated whitespace while preserving recognized display casing, and maps Vision's lower-left normalized box into AccessLens's top-left normalized image space (`x`, `y`, `width`, `height` in `0...1`). `RecognizedTextObservation` is the framework-independent boundary: ID, analyzer ID, session/frame sequence, timestamp, text, raw confidence evidence, and transformed region. Vision framework types and raw framework observations never reach SwiftUI.

`SignageCandidateClassifier` recognizes only bounded, high-enough-confidence environmental-sign wording (`EXIT`, `ENTRANCE`, `RESTROOM`, `TOILET`, `ACCESSIBLE`, `ACCESS`, `ELEVATOR`, `LIFT`, `STAIRS`, `EMERGENCY`, `PUSH`, `PULL`, `FLOOR`, and `ROOM`, including selected phrases such as “Emergency Exit”). A match creates a transient `.environmentalSignage` candidate, not a barrier, severity, accessibility finding, or compliance claim. `ScanViewModel` owns a maximum-four, eight-second transient candidate list and deduplicates text case-insensitively with spatial intersection-over-union before publishing a compact presentation snapshot. New distinct candidates receive one VoiceOver announcement; repeated OCR does not. Ending or invalidating a scan clears this entire live state.

The Scan view shows only real, transient “Recent signage observations” from those candidates plus limitation language. It includes no bounding overlay because physical-device coordinate accuracy has not yet been validated. Findings stabilization, confidence policy, severity, remediation, saved scans, and reporting remain later work.

## On-device visual contrast analyzer (Milestone 6)

`VisualContrastAnalyzer` follows `VisionTextAnalyzer` in the existing analyzer sequence. The scheduler provides accumulated same-frame output to each analyzer, so contrast uses only real text observations that already originated an `.environmentalSignage` candidate; it does not inspect arbitrary full-frame contrast. It receives the existing bounded `AnalysisFramePayload`, validates the OCR region, maps the top-left oriented normalized region through `AnalysisImageOrientation` back into a clamped raw-buffer crop, and samples at most 1,024 BGRA pixels directly from that crop. The pixel buffer is read synchronously off the main actor and unlocked before the analyzer returns; no crop, `CIImage`, sample array, or frame is retained/persisted/uploaded.

The calculation converts sRGB values to relative luminance using IEC linearization and coefficients 0.2126 / 0.7152 / 0.0722. To reduce single-pixel glare/noise influence, it estimates lower and higher luminance using the medians of the lower and upper quartiles after sorting samples—not the darkest and brightest individual pixels. It calculates the image-space ratio as `(Llighter + 0.05) / (Ldarker + 0.05)`. This is explicitly an **estimated text/background contrast from a camera image**, not a material, display, or laboratory measurement. Exposure, HDR, white balance, glare, shadows, blur, angle, reflectivity, and OCR-region uncertainty can invalidate its semantic meaning.

`ContrastObservation` is a compact framework-independent value containing source text ID, session/frame/timestamp, normalized region, lower/higher luminance estimates, estimated ratio, and evidence quality. Evidence is `insufficient`, `low`, or `usable`, determined by bounded sample count, crop size, and luminance separation. Only usable evidence is interpreted. The central heuristic classifies a ratio below 3.0 as `potentiallyLow`, 3.0–4.5 as `borderline`, and greater estimates as `likelyAdequate`; these bands are explanatory heuristics only, avoid text-size assumptions, and are never a WCAG/ADA/legal conformance decision. Only `potentiallyLow` creates a `.potentialLowContrastText` candidate.

`VisualContrastAnalyzer` emits a compact candidate only for usable, potentially-low contrast evidence. It does not decide presentation, retain history, or announce results. Critical thermal state continues to suspend the existing whole analysis pass; serious thermal and Low Power Mode keep the existing reduced cadence. Physical iPhone validation for image estimate quality, orientation, glare, shadows, motion, and accessibility remains a release gate.

## Result stabilization

Raw observation IDs exist only within a live analysis generation. An **observation** is normalized analyzer evidence; a **candidate** is a pre-stabilization accessibility-relevant interpretation; an `AccessibilityFinding` is a session-scoped, user-facing value promoted only from bounded supporting candidates. These are distinct models and a candidate is never persisted or displayed as a finding.

`AccessibilityFindingStabilizer` is the focused, lock-isolated owner of this small bounded domain work, running outside `MainActor`; only its compact result is published to `ScanViewModel` on `MainActor`. It accepts candidates only for its active `AnalysisSessionID`, and uses category, case/diacritic-folded whitespace-normalized exact text identity, valid normalized top-left image regions, IoU ≥ 0.50, and a five-second temporal window to associate evidence. It requires three usable `.potentialLowContrastText` candidates before promotion, retains no more than 12 tracks, 6 evidence entries per track, or 6 active findings, and expires unsupported tracks/findings after six seconds. A promoted UUID remains stable for its track; further support updates that same finding. A new session or Scan end clears every track and finding, so late previous-session evidence is rejected.

Each finding retains a compact evidence summary, contextual recognized text, latest estimated ratio, time/frame range, support count, evidence strength (`moderate` at promotion and `strong` at five retained observations), normalized region, and unique analyzer IDs. It retains no image, crop, buffer, or Vision/AVFoundation type. The deterministic explanation is cautious: text *may* be difficult to distinguish from its background and should be reviewed directly. No remediation, severity, legal/compliance decision, score, or persistence is introduced in Milestone 7. The Scan UI shows only active stable findings, or “No potential issues identified yet. This does not mean the environment is accessible,” and announces a newly promoted finding once rather than observations or updates.

## Scan completion and review (Milestone 8)

`ScanSession` is a framework-independent, value-oriented domain lifecycle for one user scan: `idle → preparing → scanning → completing → completed` (or `discarded`). It has its own UUID and start/completion timestamps; it contains no camera, frame, Vision, Core Image, or SwiftUI state. It complements rather than replaces the short-lived `AnalysisSessionID`: background/inactive lifecycle handling can stop analysis and later establish a fresh analysis generation while the user’s `ScanSession` remains active. Backgrounding never silently completes a scan.

Live scan state is mutable and session-scoped: camera resources, bounded scheduler work, frame payloads, candidate tracks, stabilizer evidence, and the latest accepted findings. `CompletedScan` is a separate immutable value snapshot containing only the scan identity/timestamps, stabilized `AccessibilityFinding` values, count, and review limitation text. It has no sample buffer, image, crop, Vision object, or mutable analyzer state. It is deliberately in-memory only for this milestone: app termination loses it, and it is not written to UserDefaults, SwiftData, Core Data, files, reports, or exports.

`ScanViewModel` coordinates the explicit Finish Scan intent but delegates analysis shutdown to `AnalysisCoordinator`. Finish is idempotent: it first enters `completing`, makes the camera invisible to the runtime policy, then clears the coordinator’s session gate, cancels bounded scheduler work, obtains the final already-stabilized finding snapshot, and clears the stabilizer. Only then does it create `CompletedScan` and request typed navigation to `AppRoute.scanReview`. Clearing the gate before cancellation rejects late OCR, contrast, and candidate output; the review value cannot change after creation. Completion is a bounded domain snapshot operation and never waits for fresh image/Vision work on the main actor.

While an active scan is visible, the normal back affordance is replaced with an accessible **Leave Scan** action and confirmation. **End Scan** discards the live session without a snapshot; **Finish Scan** creates the review snapshot. Both stop camera and analysis work, release transient frame/evidence state, and prevent stale publication. The Review feature is presentation-only: `ScanReviewViewModel` transforms immutable `CompletedScan` data and has no service dependencies. **Done** returns the app navigator to Home rather than resuming the old camera session. A new scan always creates a new `ScanSession` and begins with empty transient evidence.

Review uses text-first cards for potential findings, explainable evidence strength, contextual signage, an estimated-evidence uncertainty statement, and one concise scan-level limitation. A zero-finding review says that no potential issues were identified during this scan and explicitly says this does not guarantee full accessibility. It never says a scene is accessible, compliant, passed, or free of barriers. The Review title, summary, cards, limitations, and Done action are in logical VoiceOver order; controls have stable Voice Control names; semantic text/symbols—not color alone—communicate state; and scroll-based layouts support Dynamic Type and small/landscape screens. No new animation is required, so Reduce Motion has no essential motion to suppress.

## Presentation and navigation

Major surfaces: Onboarding, Camera Education/Permission, Scan, Scan Review, Finding Detail, Saved Scans, Saved Scan Detail, and Settings/About/Privacy. A simple root navigation coordinator owns route and sheet state. `Scan` combines optional visual overlays with a text-first current-findings list, a clear scan state, explicit Finish/Leave actions, and accessible detail navigation. `ScanReview` is the ephemeral completed-session surface and is not saved-scan history. Overlays must have labels or a list alternative; color/animation alone never carries finding, severity, confidence, or state.

## Accessibility architecture

Requirements are acceptance criteria, not polish:

- VoiceOver: semantic labels, values, hints, traits, ordered rotor traversal, and text alternatives for every overlay/camera state.
- Dynamic Type: support system text styles, wrapping/reflow, no clipped essential controls; test largest accessibility sizes.
- Reduce Motion: no essential animated feedback; respect setting and replace motion with static/status feedback.
- Differentiate Without Color: pair color with icon, text, pattern, and explicit state/severity words.
- Voice Control: visible, stable, uniquely named controls; no gesture-only paths.
- Touch targets: meet current Apple platform guidance and never make a camera overlay the sole tiny target.
- Focus: explicitly move focus only after user-initiated navigation/error recovery; preserve it during live updates.
- Findings: spoken text includes category, assessment state, confidence wording, and a concise next action; severity is not color-only.
- Announcements: announce only meaningful state changes (permission result, scan start/stop/interruption, and a newly stabilized high-value finding). Coalesce/rate-limit announcements, do not announce raw frames, duplicates, or continuous confidence changes; provide an accessible current-findings summary.

## Persistence decision

Adopt **SwiftData** as the planned primary local store, with a dedicated repository and explicit mapping between SwiftData entities and Codable domain/export DTOs. It is Apple-native, supports queryable saved scans/findings, and fits the iOS-only local-first app. The repository—not UI or analyzers—owns transactions, migration planning, and recovery. Persist a schema/version envelope and app/analyzer policy versions even if SwiftData performs underlying store migration. For an incompatible future change, use a tested migration path or preserve/recover readable records and mark unsupported data; never silently reinterpret findings.

Writes use one transaction to save a complete scan/finding snapshot; autosave is deliberate and debounced, never per frame. Failed writes preserve the in-memory scan and offer retry. On launch/import, decode/validate IDs, enum compatibility, reference integrity, and bounded fields. Quarantine unreadable/corrupt records, log non-sensitive diagnostics, and offer delete/recovery without crashing. Rename/delete operations are repository transactions. Avoid sync/cloud configuration until an explicit future product decision.

## Local persistence and scan history (Milestone 9)

SwiftData is the production local store for the existing iOS 17+ target. `CompletedScanRepository` exposes asynchronous save, fetch-by-ID, newest-first summary fetch, and delete operations using domain values only. SwiftUI has no `@Query`, `ModelContext`, `@Model`, or SwiftData import. `SwiftDataCompletedScanRepository` is one application-composed actor: it lazily creates its private `ModelContainer`/`ModelContext` on its own executor, disables autosave, and keeps each fetch/mutate/save or rollback sequence synchronous within actor isolation. No managed object/context crosses executors and no new unchecked Sendable annotation is used. Store initialization failures retain the existing store and retry on a later operation; they never erase the database or silently fall back to memory.

`ScanStorageSchemaV1` is a `VersionedSchema` (1.0.0) with `StoredScan` and dependent `StoredFinding` entities. Scan UUID is unique. The scan holds Date timestamps, record version, finding count, limitations, and a cascade-delete relationship. Each finding retains its stable ID and explicit position, category/title/explanation, evidence summary and strength, relevant finalized signage text, estimated ratio, normalized region if present, analysis provenance ID, bounded support count/time/sequence range, lifecycle meaning, and source analyzer identifiers. Supporting sequence endpoints are scalar provenance, not frames or a per-frame history. String identifiers preserve the full UInt64 range. Explicit string enum raw values are stable; no enum integer ordering is stored.

This paragraph records the original v1 contract. Milestone 11 freezes it and adds the compatible v2 passage fields described below.

`ScanStorageMapper` validates finite dates/numbers, date/sequence order, complete normalized regions, unique finding IDs, relationship positions/counts, ratio range, and bounded strings/finding/source counts. It reconstructs the exact domain evidence without recomputing contrast. Unknown record versions/categories/strengths/lifecycle values produce typed unsupported-record errors and are never guessed or silently omitted. Invalid or unsupported records remain logically quarantined in place: history metadata is still listed, opening shows a safe recoverable error, and the user can explicitly delete that record. A future schema change must preserve v1, add a new `VersionedSchema` and tested `SchemaMigrationPlan` stage, and verify old-store migration/rollback behavior. The v1 plan has no artificial migration stages.

Completed snapshots are immutable. Saving an identical scan ID/value is an idempotent no-op; saving different evidence under that same ID fails as a conflict and preserves the first record. Save and delete use explicit `ModelContext.save()` with rollback on failure. Deleting an absent ID is a no-op; deleting an existing scan cascades only to its own finding records. There are no image assets to delete. Disk-backed recreation and cascade-delete integration tests verify persistence beyond actor/context lifetime.

Finish Scan retains Milestone 8's stop/cancel/freeze boundary. The live navigation route is replaced by the completed route so Back cannot reopen a stopped scan. `CompletedScanSaveViewModel` owns the one automatic repository save; `CompletedScanReviewView` shows a saving state then the shared review on success or failure. Save failure keeps the full immutable value, shows product-safe text, and offers explicit Retry Save. Reappearance does not retry indefinitely or duplicate a successful save. Save work has no camera/image processing and runs off MainActor. Unsaved review data is lost if the user leaves or the process terminates; successful saves survive relaunch.

Home exposes a secondary **Scan History** action with retention copy. `ScanHistoryViewModel` owns loading, sorted summary values, operation identity, delete state, and recoverable errors on MainActor. It refreshes when History is entered/returned to and after successful deletion, without polling. A stale pre-delete load cannot reinsert a deleted row. Rows sort by completion Date descending, then UUID string ascending, use locale-aware dates, and say “No potential findings” for zero-finding scans. Historical navigation reuses `.savedScans` and `.scanDetail(id:)`; the latter loads by ID and renders the same `ScanReviewView` in `.historical` context. It never saves again or touches camera/analysis. Live review Done returns Home; historical review Back returns History. Explicit Delete Scan buttons are available without a swipe gesture and always require confirmation. Failed deletes keep the row and provide retry guidance.

Privacy boundary: the schema accepts only finalized `CompletedScan` evidence. Recognized text is stored only when it is explanatory context within a stabilized finding (including its evidence summary). No raw OCR stream, rejected text, transient candidate, stabilizer buffer, camera frame/video, raw image/image URL, crop, screenshot, pixel/sample buffer, or Vision object is stored. Home, save status, and History explain this retention. No networking, analytics, third-party dependency, new detector, export, or sharing is added. OSLog records only save/delete outcomes and load failures, never environmental text/evidence content or file paths.

The store is `Library/Application Support/AccessLens/CompletedScans.store` inside the private application sandbox with SwiftData-managed sidecars. CloudKit is explicitly `.none`; no shared group or cloud container is configured. The directory requests `completeUntilFirstUserAuthentication`, consistent with the iOS default file-protection class; protection depends on device passcode/security configuration and actual database/sidecar behavior remains a physical-device check. No custom cryptography is introduced. Saved scans are user-created data and are not excluded from normal system backups: inclusion depends on the user's backup settings. OS backup is distinct from app-implemented synchronization and may retain earlier copies beyond deletion on this device. See [Apple file protection](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files) and [Apple backup exclusion guidance](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup).

Testing uses isolated SwiftData stores (in-memory plus temporary on-disk recreation tests) and a DEBUG-only actor test repository with configured errors. Every UI test launches with a fresh deterministic history; no test seeds or resets the user's production store. No storage model/context is used in views. Manual VoiceOver, maximum Dynamic Type, Voice Control, Light/Dark, small-screen/landscape, device-lock, and OS backup/restore behavior remain release validation requirements.

## Deterministic accessibility guidance (Milestone 10)

`Core/Guidance` contains immutable, framework-independent `AccessibilityGuidance`, `GuidanceObservation`, and `GuidanceAction` values and the synchronous, Sendable `AccessibilityGuidanceProviding` boundary. `DeterministicAccessibilityGuidanceProvider` is stateless and composed in `AppDependencies`. It accepts finalized findings only and performs no I/O, pixel processing, inference, or logging. Guidance generation does not depend on timestamps, random IDs, raw OCR confidence, or display text matching.

The only supported finding category is `potentialLowContrastText`. Environmental signage remains contextual evidence, not a separate negative finding. The rule preserves any finalized recognized text and estimated ratio, explains why text/background distinction may matter, supplies direct checks from the expected viewing position and representative lighting, and offers three optional improvements: increase visual difference, simplify a complex background **if present**, and re-check after changes. Words such as EXIT do not select legal, tactile/Braille, route, or sign-placement assumptions. Missing text or estimates remain missing. Camera limitations are explicit, and limited evidence adds a stronger verification prompt without duplicating the advice list. Evidence strength remains a discrete description, never a probability or verdict.

Observation, interpretation, and advice are separate fields and sections. Detail does not expose internal frame counts, raw framework confidence, candidate buffers, or analyzer IDs. Existing finalized evidence is preserved in storage; current human-readable advice does not rewrite it. Whole sentences use Foundation localization APIs, SwiftUI headings use localizable keys, and action IDs remain independent of translated text. Localization beyond the initial English wording remains future work.

**Historical strategy: Option B.** Persist evidence only; derive guidance from current rules when opening either new or historical review. Rules carry a stable semantic ID and integer version (`text.potential-low-contrast`, version 1); change the version when rule meaning changes. Guidance is ephemeral and is never represented as advice captured at scan time. The screen explains that suggestions are general rules for that finding type. SwiftData schema v1, enum raw values, mapping, duplicate-save semantics, and migration plan are unchanged. Unknown stored categories retain M9's safe unsupported-record behavior and are still deletable; they are not reinterpreted as contrast. A general fallback rule has no category-specific improvements, recognized evidence, or inferred evidence strength for future unsupported-category presentation.

Concise review cards link through the existing `AppRoute.findingDetail(AccessibilityFinding)` to one `FindingDetailView`. The route owns a compact immutable finding value, not camera resources or a repository. `AppNavigator` remains the sole navigation owner. Back removes only the detail route, returning to the same live-completion or historical scan review. Opening details cannot save again, restart analysis, or alter the snapshot. Two findings have distinct route values and detail identity. Zero-finding reviews have no guidance control.

The detail hierarchy is title → observed evidence → possible impact → direct checks → possible improvements → evidence strength/estimate → limitations. It uses semantic headings, primary text on system background, wrapping system fonts, a scroll layout, contextual View Guidance labels, numbered actions with spoken item/count context, and an explicit 44-point Back control. No automatic announcements are added. Native navigation supplies focus context; `accessibilityReduceMotion` disables app navigation transaction animation when requested. Manual VoiceOver/focus, Voice Control, maximum text size, small-screen/landscape, Light/Dark, Differentiate Without Color, and Reduce Motion checks remain release gates.

## LiDAR passage evidence (Milestone 11)

### Feasibility and capability tiers

Apple's generic Vision rectangle APIs provide projected shapes, not semantic door identity or metric scale. Camera intrinsics describe projection but do not supply real-world scale for an uncalibrated monocular frame. AccessLens therefore does not use either mechanism to invent a doorway width. The production metric path uses RoomPlan only when `RoomCaptureSession.isSupported` confirms a LiDAR-capable device. RoomPlan supplies semantically classified `doors` and `openings`, a metric surface width, transform and reconstruction confidence.

- **Tier A — RoomPlan/LiDAR:** supported. `RoomCaptureSession` supplies the camera frame and room surfaces. High-confidence surfaces may contribute usable metric evidence; medium confidence is retained only as approximate observation and cannot create a finding; low confidence has no numeric presentation.
- **Tier B — camera intrinsics without scale:** passage measurement is unsupported. The existing AVFoundation camera, OCR and contrast pipeline continues; intrinsics are not converted to physical units.
- **Tier C — no relevant geometry:** passage analysis is quietly unavailable and other analyzers continue.

No ARKit session runs beside AVCaptureSession. On Tier A, `RoomPlanPassageCaptureController` owns a `RoomCaptureView`/RoomPlan capture session and `ScanViewModel` makes the existing AVCapture controller non-visible before starting it. On Tier B/C the RoomPlan controller never runs. Camera authorization, foreground/background, Scan visibility, Finish, discard and teardown drive both controllers idempotently. RoomPlan's internal ARSession is used only through its capture session; AccessLens does not configure a second independent ARKit capture system.

### Boundary, scheduling, and evidence

`RoomPlanPassageDeliveryBridge` immediately converts a bounded maximum of eight current RoomPlan door/opening surfaces into framework-independent `PassageSurfaceEvidence`. It projects each surface's metric rectangle into AccessLens's top-left normalized image coordinates using `ARCamera.projectPoint`. It passes the current captured image, timestamp, orientation and compact surface snapshot to `AnalysisCoordinator`; RoomPlan, ARKit, transforms and depth objects terminate at this boundary. The scheduler still allows exactly one in-flight pass and one latest pending frame, with normal 0.75-second cadence, reduced 1.5-second thermal/Low Power cadence and critical suspension. The payload retains at most the bounded current/pending pixel buffers and surface values. Neither depth nor geometry history is retained.

`PassageAccessibilityAnalyzer` is the third analyzer in the existing ordered pass. It produces `PassageObservation` values and creates `.potentialNarrowPassage` candidates only from usable RoomPlan/LiDAR width evidence below the centralized 0.90-metre product screening heuristic. The heuristic is deliberately separated from metric extraction and is not a code, ADA, or compliance threshold. Approximate, insufficient and unavailable measurements never create that candidate. No obstruction category is implemented: RoomPlan surface reconstruction alone does not defensibly prove that a visible object blocks the usable opening, and this milestone adds no segmentation/custom model.

Widths use `PassageWidth`, canonically metres with Foundation `Measurement<UnitLength>` for locale-aware display. Every value records `.roomPlanLiDAR` or `.unavailable` provenance and `unavailable` / `insufficient` / `approximate` / `usable` quality. The stabilizer remains the one evidence-fusion owner. Passage tracks associate by stable RoomPlan surface ID or region IoU within the existing five-second window; each track retains at most six observations. Three consistent usable widths are required, a 25% relative window rejects outliers, and their median becomes the finding estimate. Existing global limits remain 12 combined tracks and six findings. Session replacement, cancellation, expiry and scan completion clear the same bounded state.

The only new finding category is `potentialNarrowPassage`. It says the RoomPlan opening surface was repeatedly estimated as relatively narrow and requires direct physical verification. RoomPlan's surface width is not represented as a verified usable clear width. Evidence retains only the median width, method, quality, normalized region and existing provenance—not images, depth maps, meshes or per-frame geometry. Live and completed review label the value “Estimated opening width.” Deterministic current-rule guidance asks the reviewer to physically measure the narrowest clear opening, check projected/temporary objects, and recapture squarely if desired. It explicitly describes RoomPlan/LiDAR and camera/reconstruction limitations and never issues a legal verdict.

### Persistence and compatibility

SwiftData schema v2 adds three optional finalized-finding fields: canonical passage width in metres, stable measurement-method raw value and stable measurement-quality raw value. The frozen v1 schema remains unchanged and a lightweight v1→v2 migration is declared. Nil defaults preserve every Milestone 9/10 low-contrast record without fabricated passage evidence; both record envelope versions 1 and 2 map through strict validation. New passage records require a valid width, `.roomPlanLiDAR` and `.usable`; partial or inconsistent data is rejected. Guidance remains Option B: persisted evidence is rendered through current deterministic rules.

There is no overlay in Milestone 11 because physical-device projection accuracy has not been validated. RoomPlan coaching instructions may provide truthful, transient capture prompts (move back/closer, slow down, add light, or difficult scene). They do not create findings. Physical LiDAR accuracy, projection/orientation, camera lifecycle, accessibility and performance remain **USER VALIDATION REQUIRED**.

## First-run onboarding preference

The sole first-run preference is a non-sensitive, namespaced Boolean stored through an injectable `OnboardingCompletionStoring` boundary. Production composition uses `UserDefaults`; tests, previews, and DEBUG-only UI-test launch overrides use deterministic in-memory storage. `OnboardingState` is the only owner of this completion state and gates the root view before `NavigationStack`, so onboarding completion cannot leave a history entry. This preference is deliberately separate from the future SwiftData scan repository. Onboarding intentionally has no global Skip action: its privacy and limitation explanations are essential context before reaching the app shell.

## Image-retention policy

Default: do not retain full camera images or raw frames. Saved findings retain textual/derived evidence and an optional normalized region descriptor without an image. A later explicit “attach image” user action may create a `CapturedSceneReference`; it must disclose retention, allow per-scan deletion, use app-managed safe filenames/private storage and appropriate iOS file protection, be excluded from reports unless chosen, and have storage/retention controls. No automatic background image capture.

## Export architecture

Export is a future, explicit action from a saved scan. `ReportComposer` reads stable domain/export DTOs and produces a versioned human-readable report (initially PDF or a system-shareable document) through a presentation adapter such as PDFKit/native Core Graphics generation and `UIActivityViewController`. Structured JSON is optional only if a real interoperability use case is approved. Internal store representation is never the report schema. The export preview states included data, image inclusion, limitations, and creation date; no export occurs until user shares/saves it.

## Concurrency model

SwiftUI view state/navigation and accessibility focus/announcement coordination are `@MainActor`. Camera configuration/capture callbacks remain on a dedicated capture serial executor/queue. Analysis scheduling/stabilization and persistence use focused actors (or explicitly serial executors where framework constraints require), communicating immutable `Sendable` DTOs. Vision/framework objects and `CVPixelBuffer`/sample-buffer lifetimes do not cross arbitrary actor boundaries. Session task ownership supports cancellation on stop, background, error, or generation change. Avoid actor proliferation; isolate mutable shared lifecycle state only.

## Typed error model and recovery

Define typed technical errors: `cameraPermissionDenied`, `cameraRestricted`, `cameraUnavailable`, `captureInterrupted`, `captureRuntimeError`, `analysisUnavailable`, `analysisFailed`, `persistenceFailed`, `corruptScan`, `migrationFailed`, and `exportFailed`. Each includes a safe cause/context and maps through a separate user-facing recovery presentation: open Settings, retry, resume, use saved scans, discard/quarantine corrupt data, or try export again. Never show raw OS/framework strings, sensitive content, or developer stack traces as user copy.

## Performance and lifecycle policy

Use bounded cadence, bounded in-flight work, latest-frame behavior, cancellation, stale-result rejection, compact result DTOs, scoped autorelease/resource cleanup where appropriate, and no needless image conversion/copies. Adapt analysis behavior to thermal state and Low Power Mode; reclaim session/frame resources on stop/background/interruption. Measure before setting performance targets. Use OSLog signposts for configuration, analysis latency/cadence, dropped-frame reasons, stabilization, writes, and export without payload contents.

## Privacy and data flow

```text
Camera → in-memory AVFoundation frame → on-device Vision/analyzers → transient observations
  → stabilized finding text/metadata → optional local saved scan → explicit user-selected export
```

Camera frames do not leave the device and are not stored by default. Derived saved data is scan metadata, user-entered name, confirmed findings, evidence summaries, policy versions, and optional explicitly retained images. V1 has no network calls, accounts, backend, analytics SDK, or third-party tracking. Export is user-directed data sharing; the destination’s privacy policy then applies.

## Security model

No embedded secrets or credentials. Generate opaque IDs and app-managed filenames; never derive file paths from user text or import paths. Use bounded decoding/input lengths, validate persisted/imported schemas and media metadata, reject path traversal and unsupported/oversized data, and safely handle malformed records. Keep retained images in app-private storage with appropriate platform data protection. Share only a generated temporary export through system APIs and clean it according to the export lifecycle. This is proportionate local-app security, not unnecessary enterprise infrastructure.

## Logging policy

Use `OSLog` categories: `camera`, `vision`, `analysis`, `persistence`, `lifecycle`, and `export`. Log state transitions, error classifications, timing, counts, and recovery outcomes at appropriate privacy levels. Never log camera frames, full recognized text, exact user scan content, unredacted evidence, file paths that reveal user data, secrets, or export destinations unless essential and safely redacted.

## Dependency policy and Apple framework plan

Milestone 0 and intended V1 introduce **no third-party dependencies**. Any later dependency requires a documented substantial benefit, privacy/security/license review, maintenance owner, and removal/fallback plan.

| Technology | Intended responsibility |
|---|---|
| Swift | Type-safe domain, concurrency, and app implementation. |
| SwiftUI | Accessible native presentation and navigation. |
| AVFoundation | Camera authorization, session, device, and frame capture. |
| Vision | On-device text recognition and supported normalized observations. |
| RoomPlan / ARKit | LiDAR-capable semantic room surfaces, metric geometry and projection for conservative passage evidence; no independent AR camera session. |
| Core Image / Core Graphics | Future bounded image-region measurement/processing when validated. |
| SwiftData | Planned local scan/finding persistence behind repository. |
| OSLog | Privacy-aware diagnostics and signposts. |
| UniformTypeIdentifiers | Export/import type declaration and validation if needed. |
| PDFKit or native PDF generation | Future report rendering/viewing after format decision. |

## Project structure

```text
AccessLens/
├── App/                 # app composition, root navigation
├── Features/
│   ├── Onboarding/
│   ├── Scan/
│   ├── ScanReview/
│   ├── ScanHistory/
│   ├── Findings/
│   ├── SavedScans/
│   └── Settings/
├── Core/
│   ├── Camera/
│   ├── Vision/
│   ├── Analysis/
│   ├── Guidance/
│   ├── Persistence/
│   ├── Export/
│   ├── Accessibility/
│   └── Logging/
├── Models/
├── Resources/
├── Support/
└── AccessLensTests/     # mirrors meaningful domain boundaries
```

Organize by feature first and place reusable, platform-facing capabilities in `Core`; do not duplicate models/services across features. Tests mirror `Models`, `Core`, and feature boundaries, with fixtures separate from production resources.

## State ownership and data lifetime

| Owner | Single source of truth |
|---|---|
| App/root navigation coordinator (`@MainActor`) | app route, modal route, onboarding completion routing—not data stores. |
| Camera session controller | capture authorization/session/lifecycle state. |
| Live analysis session coordinator | generation ID, scheduler, analyzer tasks, bounded opaque frame payload, stale-result gate, and handoff to evidence fusion. |
| Finding stabilizer (lock-isolated, non-MainActor) | bounded candidate tracks/evidence, promotion, expiry, stable finding identity, and session isolation. |
| Scan feature view model (`@MainActor`) | current `ScanSession` lifecycle, compact stabilized-finding presentation snapshot, VoiceOver deduplication, and explicit finish/discard intent. |
| Scan completion workflow | deterministic lifecycle transitions and immutable `CompletedScan` construction; no resource ownership or persistence. |
| App navigator (`@MainActor`) | ephemeral `CompletedScan` route for Review and the Done-to-Home transition; not scan-history storage. |
| Completed scan repository actor | sole private SwiftData context, schema mapping, saved scan records and explicit transactions. |
| Completion save view model (`@MainActor`) | one immutable snapshot and retryable save status; does not own live analysis. |
| History / historical review view models (`@MainActor`) | loading/error/delete state and domain summary/review values; no storage context. |
| Guidance provider / finding detail | stateless current-rule derivation / immutable presentation; detail route belongs to AppNavigator and owns no services or camera state. |
| RoomPlan passage capture controller | Tier-A camera/room capture lifecycle and immediate framework-to-value conversion; replaces AVCapture while active and retains no geometry history. |
| Accessibility announcement coordinator (`@MainActor`) | coalescing/rate limit/deduplication of spoken announcements. |

Transient live state includes frame/sample-buffer references, raw Vision observations, in-flight work, analysis generation, quality signals, temporary overlays, and live stabilization history. Milestone 9 persists only completed scan metadata and finalized finding evidence through the repository. The navigation route holds an in-memory domain copy; persistence is independently owned. Names, image retention, reports, and export remain future work. Raw frames, runtime queues, temporary overlays, candidates, and mutable live state are never persisted.

## Testing strategy

Deterministic automated tests cover domain invariants/IDs/version DTOs; confidence mapping; analyzer fixtures and limitation states; stabilization/deduplication/expiry; camera authorization mapping; lifecycle state transitions; scheduler bounds/cadence/cancellation/stale-result rejection; repository transactions/migration/corrupt-data recovery; export DTO/report content; navigation; and accessibility labels, traits, Dynamic Type layouts, VoiceOver announcement policy, color-independent semantics, and Voice Control control names. Performance policy tests assert bounds/decisions, not invented timing targets. UI tests use deterministic fakes for camera/analysis.

Physical-iPhone validation is a release gate for real camera behavior/permissions, lighting and OCR quality, orientation, interruption and media reset recovery, backgrounding, long sessions, thermal behavior, Low Power Mode, memory, VoiceOver plus a live camera, motion/appearance settings, real export sharing, and supported-device capability differences. Simulator tests complement this work but cannot certify it.

## Future engineering rules

- Inspect before modifying; make the smallest coherent change; avoid duplicate architecture and giant manager objects.
- No force unwrap or `try!` for recoverable runtime conditions.
- No fake AI, confidence, scores, or unsupported claims.
- No third-party service or core network dependency without explicit justification.
- No debug feature in Release UI; never weaken tests merely to pass; report PASS only when executed.
- Mark physical-device-only checks as **USER VALIDATION REQUIRED** until actually performed.
- At each future milestone: implement, run focused and relevant regression tests/builds, update docs, review git status, report for user review, commit only after approval, push only when explicitly instructed, then and only then begin the next milestone.
