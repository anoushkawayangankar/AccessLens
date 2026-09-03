# AccessLens — Release Readiness

This is a living release gate. Milestone 0 establishes categories only; items are intentionally not started unless noted.

| Area | Status | Release evidence required |
|---|---|---|
| Build | NOT STARTED | Clean Release build on supported configuration. |
| Automated tests | NOT STARTED | Focused and regression suite results recorded. |
| Accessibility | NOT STARTED | VoiceOver, Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, focus, touch targets, and nonvisual findings audit. |
| Privacy | ARCHITECTURE DEFINED | Verify no analysis uploads, no tracking/accounts/networking, retention disclosure, and export consent/data preview. |
| Camera permission | NOT STARTED | Purpose text, denied/restricted/unavailable recovery, and physical-device permission paths. |
| Data retention | ARCHITECTURE DEFINED | Default no-image policy, deletion/rename behavior, optional-image disclosure, recovery and storage checks. |
| Performance | NOT STARTED | Bounded work/cadence evidence, lifecycle cleanup, long-session and thermal/Low Power Mode validation. |
| Physical-device validation | NOT STARTED | Supported iPhone matrix including camera, interruption, lighting/OCR, long session, thermal, accessibility, and export. |
| AppIcon | NOT STARTED | Required asset variants, rendering, and accessibility/brand review. |
| Signing | NOT STARTED | Team, bundle identifier, entitlement, and archive configuration verified. |
| Distribution | NOT STARTED | Archive/TestFlight/App Store readiness and truthful privacy metadata as applicable. |
| Documentation | IN PROGRESS | Product spec, architecture, limitations, privacy explanation, support/release notes, and milestone evidence current. |

## Production-complete definition

AccessLens is production complete only when the full primary journey works; camera lifecycle is reliable; supported analyzers are validated within their documented limits; uncertainty and explanations are honest; local persistence and export work; accessibility and privacy are audited; errors are recoverable; performance is hardened; automated regressions and a Release build pass; physical iPhone QA passes; GitHub documentation is current; and distribution/signing status is accurately recorded. A feature is not complete merely because a Simulator path works.

## Required release decision record

Before a distribution decision, record build/test identifiers and dates, supported devices/OS, physical-device test evidence, known limitations, privacy data flow/export behavior, accessibility audit outcomes, unresolved defects/mitigations, signing/distribution status, and the approving owner. Any physical-only item without evidence remains **USER VALIDATION REQUIRED**.

