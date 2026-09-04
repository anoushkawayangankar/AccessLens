# AccessLens — Production Architecture

**Scope:** Milestone 0 design. This document intentionally defines future boundaries without implementing camera, Vision, persistence, UI, export, or networking.

## Architectural shape

Use a straightforward SwiftUI feature structure with focused Apple-native services and domain models. Keep the domain independent of AVFoundation/Vision types by normalizing framework output at the boundary. Avoid “Clean Architecture” ceremony and giant managers.

```text
Camera frame → bounded scheduler → Vision requests → normalized observations
→ independent analyzers → finding candidates → confidence/evidence policy
→ stabilizer → live stable findings → SwiftUI presentation / save snapshot
```

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

Vision runs off the main actor. A Vision adapter owns requests/handlers for an analysis job, converts output to normalized value observations, and releases frame resources promptly. Domain analyzers receive normalized context, not `VNObservation` objects. Thermal state and Low Power Mode reduce cadence, disable optional work, and may surface `unableToAssess`; critical thermal state stops optional analysis safely. MainActor only receives compact presentation snapshots.

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

Initial justified analyzers are `TextAnalyzer` and `TextLegibilityAnalyzer`; the latter consumes documented quality signals and produces review/assessment candidates, not a compliance verdict. They remain unimplemented until Milestone 5. `SignageAnalyzer` is deferred until a definition and evidence source exist. `ContrastAnalyzer` is deferred until constrained sampling and validation demonstrate defensible behavior. Each analyzer has isolated deterministic test fixtures and a versioned policy.

## Result stabilization

Raw observation IDs exist only within a live analysis generation. A stabilizer groups candidates by category plus spatial overlap and semantic similarity, tracks temporal confirmation within a bounded window, and promotes only qualifying candidates to live stable findings. It applies per-category confidence thresholds, merges updated evidence into the same live finding, deduplicates repeated OCR, expires absent observations after a grace interval, and downgrades/removes unstable entries. Persisted finding IDs are minted only at explicit save/snapshot time. The UI does not display each raw result as a new finding.

## Presentation and navigation

Major surfaces: Onboarding, Camera Education/Permission, Scan, Finding Detail, Saved Scans, Saved Scan Detail, and Settings/About/Privacy. A simple root navigation coordinator owns route and sheet state. `Scan` combines optional visual overlays with a text-first current-findings list, a clear scan state, manual pause/resume/save controls, and accessible detail navigation. Finding Detail is the canonical explanation surface. Overlays must have labels or a list alternative; color/animation alone never carries finding, severity, confidence, or state.

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
│   ├── Findings/
│   ├── SavedScans/
│   └── Settings/
├── Core/
│   ├── Camera/
│   ├── Vision/
│   ├── Analysis/
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
| Live analysis session actor | generation ID, scheduler, analyzer tasks, transient raw observations, stabilization state. |
| Scan feature view model (`@MainActor`) | compact presentation snapshot and user actions, derived from the live session. |
| Scan repository | saved scan records and transactions. |
| Accessibility announcement coordinator (`@MainActor`) | coalescing/rate limit/deduplication of spoken announcements. |

Transient live state includes frame/sample-buffer references, raw Vision observations, in-flight work, analysis generation, quality signals, temporary overlays, and live stabilization history. Persisted user data includes saved scan metadata, confirmed finding snapshots, user names, retained-evidence references, and report-relevant information. Raw frames, runtime queues, temporary overlays, and mutable live state are never persisted.

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
