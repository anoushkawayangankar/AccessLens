# AccessLens — Release Readiness

This is a living release gate. Milestone 0 establishes categories only; items are intentionally not started unless noted.

| Area | Status | Release evidence required |
|---|---|---|
| Build | DEBUG FINDING-STABILIZATION BUILD PASSED | 2026-09-06 Debug `xcodebuild` passed against an iPhone 17 Pro Simulator (iOS 26.5). A clean Release build remains required. |
| Automated tests | FOUNDATION + CAMERA + OCR + CONTRAST + FINDING SUITES PASSED | `AccessLensTests`: 61 passed / 0 failed; `AccessLensUITests`: 6 passed / 0 failed on iPhone 17 Pro Simulator (iOS 26.5). Future focused and regression results remain required. |
| Accessibility | ONBOARDING + STABILIZED SCAN FINDINGS IMPLEMENTED | Onboarding, camera states, and stabilized potential-findings cards use semantic headings, explicit text/symbol state, controlled one-time VoiceOver promotion announcements, Dynamic Type-friendly scroll layouts, Voice Control-friendly labels, semantic colors, and practical touch targets. Manual audit remains required. |
| Privacy | ON-DEVICE TRANSIENT OCR + CONTRAST + FINDINGS; AUDIT PENDING | Camera frames are retained only while the one admitted analysis request or one latest pending request needs them; OCR, bounded pixel samples/crops, candidates, evidence summaries, and findings are transient and cleared when Scan ends. No content is persisted, uploaded, or logged, and no Photos/networking/accounts/analytics were added. Full privacy audit, retention disclosure, and future export consent/data preview remain required. |
| Camera permission | IMPLEMENTED; PHYSICAL QA PENDING | `NSCameraUsageDescription` is “AccessLens uses the camera to inspect your surroundings for potential accessibility barriers.” The app requests only from the explicit Enable Camera action and offers accessible denied/restricted guidance; physical-device permission, preview, interruption, and recovery validation remain required. |
| Data retention | ARCHITECTURE DEFINED | Default no-image policy, deletion/rename behavior, optional-image disclosure, recovery and storage checks. |
| Performance | BOUNDED ANALYSIS + FINDING FUSION IMPLEMENTED; DEVICE QA PENDING | Video output discards late frames; analysis permits one in-flight Task and one latest pending frame payload, applies cadence/backpressure, cancels on session end, and adapts policy for thermal/Low Power Mode. Contrast samples at most 1,024 pixels from an OCR crop; fusion retains at most 12 tracks × 6 evidence entries and 6 findings. Validate long sessions, thermal, and Low Power Mode on physical hardware. |
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
- Third-party dependencies, finding persistence, networking, analytics, accounts, Photos access, camera-frame/text/crop upload, accessibility scores, and legal/compliance certification: not introduced. Camera permission/runtime, bounded scheduling, on-device transient Vision text/signage analysis, conservative OCR-region contrast estimation, and bounded stabilized findings are implemented.

## Milestone 2 manual accessibility validation

**USER VALIDATION REQUIRED:** verify the full onboarding flow with VoiceOver; at maximum Dynamic Type; with Reduce Motion and Differentiate Without Color enabled; using Voice Control commands for Back, Continue, and Continue to AccessLens; in Light and Dark Mode; on a smaller supported iPhone; and in each supported landscape orientation. Confirm reading order, progress wording, focus after each user-initiated page change, scrolling, reachable controls, and the absence of a camera permission dialog.

## Milestone 3 physical iPhone camera validation

**USER VALIDATION REQUIRED:** reset/install the app, complete onboarding, tap Start Scan and then Enable Camera, and verify the camera system prompt appears once. Allow access and confirm the rear preview opens without stretching, remains correct in each supported orientation, stops when leaving Scan, resumes after returning, and recovers after background/foreground. Deny access and verify the accessible denied state and user-triggered Open Settings action. Exercise a realistic interruption where practical and run the camera for several minutes to check for obvious instability. Repeat the scan screen with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, a smaller supported iPhone, and supported landscape orientations. Simulator UI tests do not replace this release gate.

## Milestone 5 physical iPhone OCR validation

**USER VALIDATION REQUIRED:** on an authorized physical iPhone, start Scan and point the rear camera at clear environmental signage such as EXIT, Elevator, or Restroom. Verify the preview remains responsive, the displayed text/signage observations are plausible, duplicates do not create repeated cards or VoiceOver spam, and leaving Scan clears/stops analysis. Repeat with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, a smaller supported iPhone, supported landscape orientations, Low Power Mode, and a longer session. Validate actual OCR quality, orientation/box accuracy before any overlay work, lifecycle recovery, and thermal behavior on device; Simulator architecture tests do not prove these conditions.

## Milestone 6 physical iPhone visual-contrast validation

**USER VALIDATION REQUIRED:** on an authorized physical iPhone, scan clear signage with black-on-white text, light-gray-on-white text, white-on-dark text, glare/shadow, an angled sign, and a moving camera. Verify the preview remains responsive; only repeated, plausible potential-low-contrast estimates appear; text/ratio wording is clearly marked as estimated; duplicate cards and VoiceOver announcements do not occur; and uncertain/glare/motion cases do not make overconfident claims. Repeat with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, smaller supported iPhone, supported landscape, Low Power Mode, and a longer session. Validate crop/orientation accuracy and thermal/lifecycle recovery; Simulator tests cannot validate camera-image estimate reliability.

## Milestone 7 physical iPhone finding-stabilization validation

**USER VALIDATION REQUIRED:** on an authorized physical iPhone, hold the rear camera steadily on a clear low-contrast environmental sign and verify that a potential finding appears only after repeated usable evidence, keeps one identity/card while evidence updates, and is announced once with VoiceOver. Move to unrelated signs and confirm they are not merged; move away and confirm the finding expires after the bounded absence interval; leave Scan and confirm all findings clear. Repeat with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, smaller supported iPhone, supported landscape, Low Power Mode, and a longer session. Confirm the zero-finding state does not imply accessibility. Simulator tests verify the domain/UI policy but cannot validate live evidence quality or camera behavior.

## Production-complete definition

AccessLens is production complete only when the full primary journey works; camera lifecycle is reliable; supported analyzers are validated within their documented limits; uncertainty and explanations are honest; local persistence and export work; accessibility and privacy are audited; errors are recoverable; performance is hardened; automated regressions and a Release build pass; physical iPhone QA passes; GitHub documentation is current; and distribution/signing status is accurately recorded. A feature is not complete merely because a Simulator path works.

## Required release decision record

Before a distribution decision, record build/test identifiers and dates, supported devices/OS, physical-device test evidence, known limitations, privacy data flow/export behavior, accessibility audit outcomes, unresolved defects/mitigations, signing/distribution status, and the approving owner. Any physical-only item without evidence remains **USER VALIDATION REQUIRED**.
