import Foundation

/// Apple-native passage evidence captured before the analyzer boundary.
/// RoomPlan framework values are converted into this value type immediately.
nonisolated struct PassageSurfaceEvidence: Equatable, Sendable {
    let surfaceID: UUID
    let kind: PassageSurfaceKind
    let region: NormalizedRegion?
    let estimatedWidth: PassageWidth?
    let measurementMethod: PassageMeasurementMethod
    let measurementQuality: PassageMeasurementQuality
}

nonisolated enum PassageSurfaceKind: String, Equatable, Sendable, Hashable {
    case door
    case opening
}

/// The only production metric method currently supported. Intrinsics without
/// aligned depth are deliberately represented as unavailable, never as scale.
nonisolated enum PassageMeasurementMethod: String, Equatable, Sendable, Hashable {
    case roomPlanLiDAR = "roomPlanLiDAR"
    case unavailable = "unavailable"
}

nonisolated enum PassageMeasurementQuality: String, CaseIterable, Equatable, Sendable, Hashable {
    case unavailable
    case insufficient
    case approximate
    case usable

    var supportsNumericPresentation: Bool {
        self == .approximate || self == .usable
    }

    var displayName: String {
        switch self {
        case .unavailable: String(localized: "Unavailable")
        case .insufficient: String(localized: "Insufficient")
        case .approximate: String(localized: "Approximate")
        case .usable: String(localized: "Usable")
        }
    }
}

/// Canonical storage is meters. Foundation Measurement is exposed for
/// locale-aware presentation without permitting unitless Doubles downstream.
nonisolated struct PassageWidth: Equatable, Sendable, Hashable {
    let meters: Double

    init?(meters: Double) {
        guard meters.isFinite, meters > 0, meters <= 10 else { return nil }
        self.meters = meters
    }

    private init(validatedMeters: Double) {
        meters = validatedMeters
    }

    static let defaultScreeningMaximum = PassageWidth(validatedMeters: 0.90)

    var measurement: Measurement<UnitLength> {
        Measurement(value: meters, unit: .meters)
    }
}

nonisolated struct PassageObservation: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let sourceSurfaceID: UUID
    let analyzerID: AnalyzerIdentifier
    let sessionID: AnalysisSessionID
    let frameSequence: AnalysisFrameSequence
    let presentationTimeSeconds: Double?
    let kind: PassageSurfaceKind
    let region: NormalizedRegion?
    let estimatedWidth: PassageWidth?
    let measurementMethod: PassageMeasurementMethod
    let measurementQuality: PassageMeasurementQuality
}

/// Finalized, persistable passage evidence. It contains no RoomPlan, ARKit,
/// image, mesh, transform, or depth-map object.
nonisolated struct PassageFindingEvidence: Equatable, Sendable, Hashable {
    let estimatedWidth: PassageWidth?
    let measurementMethod: PassageMeasurementMethod
    let measurementQuality: PassageMeasurementQuality
}

/// Product screening policy, not a building-code threshold. Width evidence
/// only creates a review candidate when RoomPlan supplies usable LiDAR-backed
/// classification and dimensions. A person must measure the clear opening.
nonisolated struct PassageInterpretationPolicy: Equatable, Sendable {
    let maximumScreeningWidth: PassageWidth

    init(maximumScreeningWidth: PassageWidth = .defaultScreeningMaximum) {
        self.maximumScreeningWidth = maximumScreeningWidth
    }

    func shouldCreatePotentialNarrowCandidate(for evidence: PassageSurfaceEvidence) -> Bool {
        guard evidence.measurementMethod == .roomPlanLiDAR,
              evidence.measurementQuality == .usable,
              let width = evidence.estimatedWidth else { return false }
        return width.meters < maximumScreeningWidth.meters
    }
}

/// Runs inside the existing one-in-flight/one-pending analysis pass. RoomPlan
/// owns semantic detection; this adapter normalizes and conservatively
/// interprets only the bounded snapshot attached to the admitted frame.
nonisolated final class PassageAccessibilityAnalyzer: AccessibilityAnalyzer {
    let identifier = AnalyzerIdentifier(rawValue: "roomplan.passage.v1")
    private let interpretationPolicy: PassageInterpretationPolicy

    init(interpretationPolicy: PassageInterpretationPolicy = PassageInterpretationPolicy()) {
        self.interpretationPolicy = interpretationPolicy
    }

    func analyze(_ context: AnalysisContext, priorOutput _: AnalyzerOutput) async throws -> AnalyzerOutput {
        try Task.checkCancellation()
        guard let surfaces = context.payload?.passageSurfaces, !surfaces.isEmpty else { return .empty }

        var observations: [PassageObservation] = []
        var normalized: [NormalizedObservation] = []
        var candidates: [FindingCandidate] = []
        observations.reserveCapacity(surfaces.count)

        for surface in surfaces.prefix(8) {
            try Task.checkCancellation()
            guard surface.measurementQuality.supportsNumericPresentation == (surface.estimatedWidth != nil),
                  surface.measurementMethod == (surface.estimatedWidth == nil ? .unavailable : .roomPlanLiDAR),
                  surface.region.map(NormalizedRegionAssociation.isValid) ?? true else { continue }

            let observation = PassageObservation(
                id: UUID(), sourceSurfaceID: surface.surfaceID, analyzerID: identifier,
                sessionID: context.frame.sessionID, frameSequence: context.frame.sequence,
                presentationTimeSeconds: context.frame.presentationTimeSeconds,
                kind: surface.kind, region: surface.region, estimatedWidth: surface.estimatedWidth,
                measurementMethod: surface.measurementMethod, measurementQuality: surface.measurementQuality
            )
            observations.append(observation)
            normalized.append(NormalizedObservation(
                id: observation.id, analyzerID: identifier, sessionID: observation.sessionID,
                frameSequence: observation.frameSequence, region: observation.region,
                evidenceKind: "roomplan.passage"
            ))

            guard interpretationPolicy.shouldCreatePotentialNarrowCandidate(for: surface) else { continue }
            candidates.append(FindingCandidate(
                sessionID: observation.sessionID,
                sourceObservationIDs: [observation.id],
                frameSequence: observation.frameSequence,
                region: observation.region,
                evidenceKind: "passage.potential-narrow",
                category: .potentialNarrowPassage,
                presentationTimeSeconds: observation.presentationTimeSeconds,
                sourceAnalyzerID: identifier,
                passageSurfaceID: observation.sourceSurfaceID,
                passageEvidence: PassageFindingEvidence(
                    estimatedWidth: observation.estimatedWidth,
                    measurementMethod: observation.measurementMethod,
                    measurementQuality: observation.measurementQuality
                )
            ))
        }

        return AnalyzerOutput(observations: normalized, passageObservations: observations, candidates: candidates)
    }
}

/// Bounded robust aggregation used by the finding stabilizer and tests.
nonisolated enum PassageMeasurementAggregator {
    static func medianRejectingOutliers(
        _ values: [PassageWidth],
        relativeTolerance: Double = 0.25
    ) -> PassageWidth? {
        guard !values.isEmpty, relativeTolerance.isFinite, relativeTolerance >= 0 else { return nil }
        let sorted = values.map(\.meters).sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        guard median > 0 else { return nil }
        let inliers = sorted.filter { abs($0 - median) / median <= relativeTolerance }
        guard !inliers.isEmpty else { return nil }
        let inlierMiddle = inliers.count / 2
        let result = inliers.count.isMultiple(of: 2)
            ? (inliers[inlierMiddle - 1] + inliers[inlierMiddle]) / 2
            : inliers[inlierMiddle]
        return PassageWidth(meters: result)
    }

    static func inliers(
        _ values: [PassageWidth],
        relativeTolerance: Double = 0.25
    ) -> [PassageWidth] {
        guard let center = medianRejectingOutliers(values, relativeTolerance: relativeTolerance) else { return [] }
        return values.filter { abs($0.meters - center.meters) / center.meters <= relativeTolerance }
    }
}
