# AccessLens — Product Specification

**Document status:** Milestone 0 complete — product and architecture contract only.  
**Product posture:** Native iOS, accessibility-first, local-first, privacy-first.

## Product statement

AccessLens helps people inspect a real-world scene through an iPhone camera for *potential* accessibility and usability barriers. It presents explainable observations, calibrated uncertainty, and practical remediation guidance so a person can decide what to inspect further. It is an assistive inspection aid, not a compliance authority.

## Target users

- Disabled people and their supporters who want a repeatable way to notice possible barriers in a space.
- Small-business owners, venue operators, and facilities teams doing an early, informal accessibility walk-through.
- Accessibility advocates, designers, and educators documenting observations for follow-up.

The product must be usable by people who are blind or low vision, Deaf or hard of hearing, have mobility, speech, cognitive, or vestibular disabilities, and by people using accessibility settings.

## Problem and intended value

Many environmental barriers are easy to overlook, especially when an inspector is unfamiliar with the space or needs to document what was seen. A camera can surface limited, visible clues (for example, text detected in a sign) and preserve an evidence-backed record. AccessLens does not replace lived experience, site measurements, specialist judgment, or formal assessment.

## Primary use cases

1. Inspect visible signage and receive a text summary plus a prompt when legibility cannot be assessed reliably.
2. Record a potential visual obstruction or insufficiently supported text-contrast observation for human review.
3. Inspect an explanation, evidence, limitations, and suggested next step for a finding.
4. Save a named local scan, review its findings later, and export a human-readable report.

## Non-goals and prohibited claims

V1 excludes legal accessibility certification; ADA, WCAG, building-code, or equivalent compliance certification; a universal accessibility score; cloud accounts; social/collaborative features; tracking/analytics; remote camera analysis; generative-AI chat; crowdsourced databases; navigation/routing; and custom ML training unless a later milestone separately justifies it.

AccessLens must not claim that a location is accessible/inaccessible, that an image proves a measured dimension or code requirement, that detected text is complete/correct, or that a camera-only inference establishes legal compliance. It must not turn raw framework confidence into a factual or percentage accessibility claim.

## Product principles

1. **Accessibility-first:** equivalent nonvisual paths, semantic controls, adaptable presentation, and no essential color-, animation-, overlay-, or gesture-only action.
2. **Privacy-first:** analyze on device; retain the least data needed; add neither networking nor tracking by default.
3. **Evidence before claims:** retain a separable observation, interpretation, evidence, limitation, and remediation suggestion.
4. **Uncertainty first-class:** support detected, possible, uncertain, and unable-to-assess states.
5. **Local-first:** core capability works without account or network.
6. **Production engineering:** lifecycle, bounds, recovery, migrations, tests, performance, and physical-device validation are requirements.

## Complete primary journey

1. Launch and complete (or revisit) accessible onboarding.
2. Read camera education describing purpose, limitations, and privacy; request camera permission only after that context.
3. Start a live scan with a clear nonvisual status summary and manual controls.
4. Receive a small, stabilized set of potential findings—not a stream of raw detections.
5. Inspect a finding’s observation, confidence/state, evidence, explanation, limitations, and remediation guidance.
6. Save the scan locally, optionally name it, and later review findings without reopening the camera.
7. Export an explicitly user-initiated, shareable report. The user chooses the sharing destination and is reminded what data is included.

## Accessibility philosophy

The live camera view is an enhancement, never the sole source of information. Findings have text-first, VoiceOver-readable equivalents. Severity is expressed with words and symbols/text, never color alone. Motion is optional; the product minimizes changing focus and announcements. The app respects Dynamic Type, contrast and color-differentiation preferences, Voice Control, light/dark appearance, and platform touch-target guidance.

## Privacy philosophy

Frames are processed in memory on the device and are never uploaded for analysis. Default saved scans contain metadata and confirmed finding records, not images. There are no accounts, analytics SDKs, trackers, or network services in V1. An export is the only intended data egress and is always user initiated.

## Confidence and uncertainty philosophy

Framework output is evidence, not truth. Product confidence reflects evidence quality, repeatability, scene conditions, and analyzer-specific limitations. Product language is categorical and explanatory (for example, “possible issue—review in person”), not falsely precise (for example, “87% inaccessible”). `unableToAssess` is a useful outcome when visibility, orientation, lighting, or available evidence is inadequate.

## Observation boundaries

| Boundary | AccessLens may say |
|---|---|
| **Can observe** | Text was recognized in a visible image region; the image contains pixels from which a bounded, documented visual indicator was calculated; a visual region or text is not sufficiently observable in the current frame. |
| **May reasonably infer** | A repeated, bounded observation could merit human review, such as text that may be difficult to read under the captured conditions. It can suggest a practical follow-up. |
| **Must not claim** | Legal/code conformance, universal accessibility, physical dimensions/clearances, actual usability for every person, a definitive obstruction, or that a location passes/fails any standard solely from camera analysis. |

## Initial on-device analysis scope

The following is a capability contract, not an implementation commitment. Availability must be verified against the deployment target at implementation time.

| Category | Input and Apple-native candidate | Observable output | Limits / likely errors | V1 decision |
|---|---|---|---|---|
| Visible text / signage transcription | Camera frame; Vision `VNRecognizeTextRequest` | Recognized text, bounding regions, orientation/language metadata where available | False positives: stylized, reflected, partial, or background text. False negatives: blur, glare, small text, scripts/languages, occlusion. Recognition does not establish sign purpose or adequacy. | **Include** |
| Text legibility indicators | Frame plus OCR regions; Vision OCR confidence, pixel geometry; possibly Core Image/Core Graphics image metrics | Evidence quality signals such as recognized-region size, blur/exposure/contrast proxies, and “unable to assess” | Not a human legibility measurement; display size, viewing distance, acuity, lighting, font and context are unknown. | **Include, cautiously**; show as an indicator/review prompt only |
| Text-background contrast indicator | OCR region and adjacent pixels; Core Image/Core Graphics sampling | A bounded image-space contrast estimate only when foreground/background segmentation and sampling are defensible | Shadows, gradients, transparency, anti-aliasing, glare, camera processing, unknown actual colors and sign material make false judgments likely. Cannot claim WCAG/ADA/code contrast compliance. | **Defer from initial V1 release** pending validation; no general scene contrast scoring |
| Visual obstruction / visibility observation | Frame; potentially Vision foreground/person segmentation where supported, or custom model | No reliable generic “obstruction” semantic capability from current generic Vision APIs | Segmentation identifies pixels/classes, not whether something blocks access, signage, or a route. A custom trained model and rigorous data/validation would be required for a defined object/obstruction category. | **Reject/defer** |
| Scene semantics (doors, ramps, stairs, clearances, hazards) | Frame; Vision classification/detection only where model support exists | Generic pretrained labels at most | No Apple-native API establishes measurements, slope, route accessibility, tactile information, or legal conditions. Custom ML plus calibrated measurement methods would be needed. | **Reject/defer** |

No custom ML model is introduced in V1. A future model must have an explicit target definition, dataset provenance, fairness/quality evaluation, privacy review, offline runtime plan, limitation copy, and physical-device validation before being represented as a product capability.

