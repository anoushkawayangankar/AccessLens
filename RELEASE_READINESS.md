# AccessLens — Release Readiness

This is a living release gate. Milestone 0 establishes categories only; items are intentionally not started unless noted.

| Area | Status | Release evidence required |
|---|---|---|
| Build | DEBUG ANALYSIS-FOUNDATION BUILD PASSED | 2026-09-04 Debug `xcodebuild` passed against an iPhone 17 Pro Simulator (iOS 26.5). A clean Release build remains required. |
| Automated tests | FOUNDATION + CAMERA + ANALYSIS SUITES PASSED | `AccessLensTests`: 33 passed / 0 failed; `AccessLensUITests`: 4 passed / 0 failed on iPhone 17 Pro Simulator (iOS 26.5). Future focused and regression results remain required. |
| Accessibility | ONBOARDING + SCAN FOUNDATION IMPLEMENTED | Onboarding and camera states use semantic headings, text-visible progress/status, Dynamic Type-friendly scroll layouts, Voice Control-friendly button labels, semantic colors, and practical touch targets. Manual audit remains required. |
| Privacy | CAMERA + METADATA-ONLY ANALYSIS FOUNDATION; AUDIT PENDING | Camera callbacks reduce frames to transient orientation/timestamp/dimension metadata; no sample buffer is retained, persisted, or uploaded, and no Photos/networking/accounts/analytics were added. Full privacy audit, retention disclosure, and future export consent/data preview remain required. |
| Camera permission | IMPLEMENTED; PHYSICAL QA PENDING | `NSCameraUsageDescription` is “AccessLens uses the camera to inspect your surroundings for potential accessibility barriers.” The app requests only from the explicit Enable Camera action and offers accessible denied/restricted guidance; physical-device permission, preview, interruption, and recovery validation remain required. |
| Data retention | ARCHITECTURE DEFINED | Default no-image policy, deletion/rename behavior, optional-image disclosure, recovery and storage checks. |
| Performance | BOUNDED ANALYSIS FOUNDATION IMPLEMENTED; DEVICE QA PENDING | Video output discards late frames; analysis permits one in-flight Task and one latest pending metadata descriptor, applies cadence/backpressure, cancels on session end, and adapts policy for thermal/Low Power Mode. Validate long sessions, thermal, and Low Power Mode on physical hardware. |
| Physical-device validation | CAMERA QA REQUIRED | Intended initial support is iPhone on iOS 17.0+ in portrait, landscape left, and landscape right. Validate first permission, preview/orientation, leave-return, background-foreground, denied/Open Settings, interruption, longer sessions, accessibility, and future analyzer/export behavior. |
| AppIcon | NOT STARTED | Required asset variants, rendering, and accessibility/brand review. |
| Signing | NOT STARTED | Bundle identifier is `anoushka.AccessLens`; signing/archive configuration remains unverified. |
| Distribution | NOT STARTED | Archive/TestFlight/App Store readiness and truthful privacy metadata as applicable. |
| Documentation | IN PROGRESS | Product spec, architecture, limitations, privacy explanation, support/release notes, and milestone evidence current. |

## Foundation facts

- Deployment target: iOS 17.0.
- Device family: iPhone only.
- App target bundle identifier: `anoushka.AccessLens`.
- Test targets: `AccessLensTests` and `AccessLensUITests`.
- Third-party dependencies, Vision requests/processing, OCR, persistence, networking, analytics, accounts, Photos access, and camera-frame retention/upload: not introduced. Camera permission/runtime and metadata-only analysis scheduling are implemented.

## Milestone 2 manual accessibility validation

**USER VALIDATION REQUIRED:** verify the full onboarding flow with VoiceOver; at maximum Dynamic Type; with Reduce Motion and Differentiate Without Color enabled; using Voice Control commands for Back, Continue, and Continue to AccessLens; in Light and Dark Mode; on a smaller supported iPhone; and in each supported landscape orientation. Confirm reading order, progress wording, focus after each user-initiated page change, scrolling, reachable controls, and the absence of a camera permission dialog.

## Milestone 3 physical iPhone camera validation

**USER VALIDATION REQUIRED:** reset/install the app, complete onboarding, tap Start Scan and then Enable Camera, and verify the camera system prompt appears once. Allow access and confirm the rear preview opens without stretching, remains correct in each supported orientation, stops when leaving Scan, resumes after returning, and recovers after background/foreground. Deny access and verify the accessible denied state and user-triggered Open Settings action. Exercise a realistic interruption where practical and run the camera for several minutes to check for obvious instability. Repeat the scan screen with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, a smaller supported iPhone, and supported landscape orientations. Simulator UI tests do not replace this release gate.

## Production-complete definition

AccessLens is production complete only when the full primary journey works; camera lifecycle is reliable; supported analyzers are validated within their documented limits; uncertainty and explanations are honest; local persistence and export work; accessibility and privacy are audited; errors are recoverable; performance is hardened; automated regressions and a Release build pass; physical iPhone QA passes; GitHub documentation is current; and distribution/signing status is accurately recorded. A feature is not complete merely because a Simulator path works.

## Required release decision record

Before a distribution decision, record build/test identifiers and dates, supported devices/OS, physical-device test evidence, known limitations, privacy data flow/export behavior, accessibility audit outcomes, unresolved defects/mitigations, signing/distribution status, and the approving owner. Any physical-only item without evidence remains **USER VALIDATION REQUIRED**.
