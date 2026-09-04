# AccessLens — Release Readiness

This is a living release gate. Milestone 0 establishes categories only; items are intentionally not started unless noted.

| Area | Status | Release evidence required |
|---|---|---|
| Build | DEBUG ONBOARDING BUILD PASSED | 2026-09-04 Debug `xcodebuild` passed against an iPhone 17 Pro Simulator (iOS 26.5). A clean Release build remains required. |
| Automated tests | FOUNDATION SUITES PASSED | `AccessLensTests`: 12 passed / 0 failed; `AccessLensUITests`: 2 passed / 0 failed on iPhone 17 Pro Simulator (iOS 26.5). Future focused and regression results remain required. |
| Accessibility | ONBOARDING FOUNDATION IMPLEMENTED | Onboarding uses text-visible progress, semantic headings, Dynamic Type-friendly scrolling/stacking controls, Reduce Motion-aware transitions, Voice Control-friendly labels, semantic colors, and practical touch targets. Manual audit remains required. |
| Privacy | ARCHITECTURE DEFINED | Verify no analysis uploads, no tracking/accounts/networking, retention disclosure, and export consent/data preview. |
| Camera permission | NOT STARTED | No usage description or permission request is present. Purpose text, denied/restricted/unavailable recovery, and physical-device permission paths remain required. |
| Data retention | ARCHITECTURE DEFINED | Default no-image policy, deletion/rename behavior, optional-image disclosure, recovery and storage checks. |
| Performance | NOT STARTED | Bounded work/cadence evidence, lifecycle cleanup, long-session and thermal/Low Power Mode validation. |
| Physical-device validation | NOT STARTED | Intended initial support is iPhone on iOS 17.0+ in portrait, landscape left, and landscape right. Validate the supported-device matrix including camera, interruption, lighting/OCR, long session, thermal, accessibility, and export. |
| AppIcon | NOT STARTED | Required asset variants, rendering, and accessibility/brand review. |
| Signing | NOT STARTED | Bundle identifier is `anoushka.AccessLens`; signing/archive configuration remains unverified. |
| Distribution | NOT STARTED | Archive/TestFlight/App Store readiness and truthful privacy metadata as applicable. |
| Documentation | IN PROGRESS | Product spec, architecture, limitations, privacy explanation, support/release notes, and milestone evidence current. |

## Foundation facts

- Deployment target: iOS 17.0.
- Device family: iPhone only.
- App target bundle identifier: `anoushka.AccessLens`.
- Test targets: `AccessLensTests` and `AccessLensUITests`.
- Third-party dependencies, camera permission, camera/Vision processing, persistence, networking, analytics, and accounts: not introduced.

## Milestone 2 manual accessibility validation

**USER VALIDATION REQUIRED:** verify the full onboarding flow with VoiceOver; at maximum Dynamic Type; with Reduce Motion and Differentiate Without Color enabled; using Voice Control commands for Back, Continue, and Continue to AccessLens; in Light and Dark Mode; on a smaller supported iPhone; and in each supported landscape orientation. Confirm reading order, progress wording, focus after each user-initiated page change, scrolling, reachable controls, and the absence of a camera permission dialog.

## Production-complete definition

AccessLens is production complete only when the full primary journey works; camera lifecycle is reliable; supported analyzers are validated within their documented limits; uncertainty and explanations are honest; local persistence and export work; accessibility and privacy are audited; errors are recoverable; performance is hardened; automated regressions and a Release build pass; physical iPhone QA passes; GitHub documentation is current; and distribution/signing status is accurately recorded. A feature is not complete merely because a Simulator path works.

## Required release decision record

Before a distribution decision, record build/test identifiers and dates, supported devices/OS, physical-device test evidence, known limitations, privacy data flow/export behavior, accessibility audit outcomes, unresolved defects/mitigations, signing/distribution status, and the approving owner. Any physical-only item without evidence remains **USER VALIDATION REQUIRED**.
