# AccessLens — Release Readiness

This is a living release gate. Milestone 0 establishes categories only; items are intentionally not started unless noted.

| Area | Status | Release evidence required |
|---|---|---|
| Build | M11 DEBUG BUILD PASSED | Concrete iPhone 17 Pro / iOS Simulator 26.5 Debug build passed on 2026-09-12 with RoomPlan and schema v2. A clean Release build remains required for distribution readiness. |
| Automated tests | M11 COMPLETE SUITES PASSED | On iPhone 17 Pro / iOS Simulator 26.5, 115/115 unit tests and 22/22 UI tests passed with no failures or skips. Passage coverage includes analysis, stabilization, migration, guidance, live review and historical review. |
| Accessibility | ONBOARDING + SCAN + REVIEW + GUIDANCE IMPLEMENTED | Semantic headings, explicit text state, controlled announcements, wrapping system fonts, current-rule guidance with spoken action-list context, and contextual controls. Largest-text landscape guidance reachability passed; full manual VoiceOver, focus, appearance and device audit remains required. |
| Privacy | FINALIZED LOCAL SCANS STORED; FULL AUDIT PENDING | Only completed scan metadata and stabilized explanatory finding evidence are now persisted, including relevant sign text. No image/frame/crop/raw OCR stream/Vision object/candidate buffer is stored or uploaded. Home, save status, and History disclose retention; no Photos/networking/accounts/analytics added. Backup eligibility follows system/user settings; full privacy and future export audits remain required. |
| Camera permission | IMPLEMENTED; PHYSICAL QA PENDING | `NSCameraUsageDescription` is “AccessLens uses the camera to inspect your surroundings for potential accessibility barriers.” The app requests only from the explicit Enable Camera action and offers accessible denied/restricted guidance; physical-device permission, preview, interruption, and recovery validation remain required. |
| Data retention | LOCAL SCANS + SCHEMA V2 PASSAGE EVIDENCE VERIFIED | SwiftData v2 adds optional finalized passage width/method/quality; automated v1→v2 migration and legacy-load coverage passed. No frame/image/depth/mesh/transform/per-frame measurement is stored. Device data protection/backup/restore remain pending. |
| Performance | BOUNDED MULTI-ANALYZER PIPELINE IMPLEMENTED; DEVICE QA PENDING | RoomPlan frames enter the existing one-in-flight/one-latest-pending scheduler and thermal/Low Power cadence. At most eight passage surfaces cross the boundary; passage evidence uses the existing 12 tracks × 6 entries and six findings. YUV contrast conversion downsamples only an OCR crop to at most 1,024 pixels. Validate preview, CPU/memory/task growth and thermal behavior on physical LiDAR hardware. |
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
- Third-party dependencies, networking, analytics, accounts, Photos access, camera-frame/text/crop upload, accessibility scores, and legal/compliance certification: not introduced. Camera/runtime and analysis remain unchanged by Milestone 9. Finalized completed scans now save through an actor-owned SwiftData repository and reopen through Scan History using the shared Scan Review. Raw camera/text streams remain transient.

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

## Milestone 8 physical iPhone completion and review validation

**USER VALIDATION REQUIRED:** on an authorized physical iPhone, build one or more stable potential findings, activate **Finish Scan**, and verify camera preview and analysis stop before the static Scan Review appears. Confirm the review contains only evidence from that session; no late card appears after completion; zero-finding review uses the stated limitation and never certifies accessibility; and **Done** returns Home. Start a new scan and verify it has a new identity with no inherited findings. Use **Leave Scan** during an active scan and verify the confirmation can continue or discard without producing a review. Background/foreground an active scan and confirm it does not complete automatically. Repeat Finish, review, confirmation, and Done with VoiceOver, maximum Dynamic Type, Reduce Motion, Differentiate Without Color, Voice Control, Light/Dark Mode, a smaller supported iPhone, and all supported orientations. Simulator tests verify deterministic lifecycle/UI policy but cannot validate live camera resource release or real evidence behavior.

## Milestone 9 storage/history validation

**Automated:** isolated SwiftData tests verify exact one/multiple/zero-finding round trips, scalar evidence provenance, stable enum mapping, duplicate and concurrent saves, conflict protection, deterministic ordering, selected/cascade deletion, disk-backed recreation, invalid/unknown records, and no silent memory fallback. View-model tests verify save failure preserves review, explicit retry, load failure/retry, delete failure consistency, refresh, missing historical records, and navigation. Complete UI evidence: 15 executed / 15 passed / 0 failed / 0 skipped.

**USER VALIDATION REQUIRED:** complete a real scan, confirm automatic saving and privacy copy, terminate/relaunch the app, reopen it from History, and verify evidence is unchanged without camera activation. Confirm individual Delete Scan → Cancel and Delete Scan → Delete behavior, zero-finding history/review wording, and other records remaining intact. Validate VoiceOver row/date/count/action order; largest Dynamic Type and scrolling; Voice Control labels; Light/Dark appearance; Differentiate Without Color; Reduce Motion; small iPhone and supported landscape. Validate on-device store/sidecar file protection with passcode/lock and actual system backup/restore under user settings. Reports, export/sharing, Release/archive/signing, and physical camera/evidence quality are not complete.

## Milestone 10 guidance validation

Guidance is local deterministic application logic for the single supported potential-low-contrast-text finding category. Current rule version 1 derives advice from finalized evidence in new and historical review. Stored schema v1, mapping, raw values, finalized text policy and backup behavior are unchanged. No new detector, generative AI, network call, analytics, content log, camera retention, OCR retention, standards determination, score, report, sharing or export was introduced.

Automated guidance coverage includes all supported categories, missing evidence, conservative text context, repeated-input determinism, discrete strength wording, unknown-category rejection/fallback, historical schema-v1 compatibility and independent detail routes. The complete 100-test unit suite and 19-test UI suite passed. An initial landscape test used synthetic swipes that left the Simulator surface at 0% scroll; diagnostic hierarchy/capture showed a coordinate mismatch. Native XCTest scroll-to-element behavior made the same heading/text reachability assertions pass, first in isolation and then in the complete suite. The Simulator's cropped landscape attachment is not evidence of a full visual audit; physical appearance/focus checks remain required. No product assertion or existing regression test was removed.

**USER VALIDATION REQUIRED:** open guidance from a newly completed scan and from History; verify heading/reading order and focus on entering and returning with VoiceOver; navigate the numbered checks/improvements; use Voice Control's contextual View Guidance and Back actions; inspect all content at maximum Dynamic Type on a smaller iPhone and landscape; inspect Light/Dark, Increase Contrast and Differentiate Without Color; enable Reduce Motion and verify navigation remains understandable. Confirm language remains potential/estimated and describes only retained evidence. Automated UI checks do not prove complete accessibility quality. Physical camera/evidence, Release/distribution, reports/export and final hardening remain open.

## Milestone 11 passage validation

The production passage path is restricted to RoomPlan-supported LiDAR devices. Intrinsics-only/unsupported devices receive no numeric width or passage finding and continue OCR/contrast normally. The new finding is `potentialNarrowPassage`; no obstruction claim is made. All width copy says “estimated,” requires direct physical verification, and makes no standards or legal determination. Schema v2 stores only finalized width/metre, method and quality scalars and migrates optional nil fields from v1.

**USER VALIDATION REQUIRED:** use at least one RoomPlan-supported LiDAR iPhone and, separately, one non-LiDAR supported iPhone. On LiDAR hardware scan a tape-measured wide opening, a narrower opening, a partially occluded opening, an opening with a temporary object nearby, an angled/partially clipped opening, poor lighting and rapid movement. Compare the estimated width with the tape-measured narrowest clear opening at multiple distances/angles; record raw errors before establishing any accuracy claim. Confirm wide/noisy/partial evidence does not create a finding, three consistent observations are needed, outliers do not dominate, and cards do not duplicate. Verify RoomPlan replaces rather than competes with the normal camera; Finish, leave, background/foreground and Low Power/thermal transitions release/recover capture and analysis. On non-LiDAR hardware verify OCR/contrast continue and no fake width or recurring error appears.

Repeat live/review/history/guidance with VoiceOver, maximum Dynamic Type, Voice Control, Reduce Motion, Differentiate Without Color, Increase Contrast, Light/Dark, smaller supported iPhone and supported landscape orientations. Validate projected region/orientation and any capture prompt. Run a longer LiDAR scan while observing preview responsiveness, task count, memory growth and thermal state. Physical-device status remains **NOT TESTED / USER VALIDATION REQUIRED**; Simulator cannot validate RoomPlan/LiDAR geometry or measurement accuracy.

## Production-complete definition

AccessLens is production complete only when the full primary journey works; camera lifecycle is reliable; supported analyzers are validated within their documented limits; uncertainty and explanations are honest; local persistence and export work; accessibility and privacy are audited; errors are recoverable; performance is hardened; automated regressions and a Release build pass; physical iPhone QA passes; GitHub documentation is current; and distribution/signing status is accurately recorded. A feature is not complete merely because a Simulator path works.

## Required release decision record

Before a distribution decision, record build/test identifiers and dates, supported devices/OS, physical-device test evidence, known limitations, privacy data flow/export behavior, accessibility audit outcomes, unresolved defects/mitigations, signing/distribution status, and the approving owner. Any physical-only item without evidence remains **USER VALIDATION REQUIRED**.
