import Foundation
import SwiftData

/// Freeze v1 when a future version is introduced; changes then belong in a new
/// VersionedSchema and a tested SchemaMigrationPlan stage.
nonisolated enum ScanStorageSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredScan.self, StoredFinding.self] }

    @Model
    final class StoredScan {
        @Attribute(.unique) var id: UUID
        var recordVersion: Int
        var startedAt: Date
        var completedAt: Date
        var limitations: String
        var findingCount: Int
        @Relationship(deleteRule: .cascade, inverse: \StoredFinding.scan)
        var findings: [StoredFinding]

        init(id: UUID, startedAt: Date, completedAt: Date, limitations: String, findings: [StoredFinding]) {
            self.id = id
            recordVersion = 1
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.limitations = limitations
            findingCount = findings.count
            self.findings = findings
        }
    }

    @Model
    final class StoredFinding {
        var id: UUID
        var position: Int
        var category: String
        var title: String
        var explanation: String
        var evidenceSummary: String
        var evidenceStrength: String
        var regionX: Double?
        var regionY: Double?
        var regionWidth: Double?
        var regionHeight: Double?
        var firstObservedTime: Double
        var lastObservedTime: Double
        // Strings preserve the full UInt64 range without signed SQLite coercion.
        var firstSequence: String
        var lastSequence: String
        var supportingObservationCount: Int
        var analysisSessionID: UUID
        var sourceAnalyzerIDs: [String]
        var lifecycle: String
        var relevantText: String?
        var estimatedContrast: Double?
        var scan: StoredScan?

        init(_ finding: AccessibilityFinding, position: Int) {
            id = finding.id
            self.position = position
            category = finding.category.rawValue
            title = finding.title
            explanation = finding.explanation
            evidenceSummary = finding.evidenceSummary
            evidenceStrength = finding.evidenceStrength.rawValue
            regionX = finding.region?.x
            regionY = finding.region?.y
            regionWidth = finding.region?.width
            regionHeight = finding.region?.height
            firstObservedTime = finding.firstObservedTime
            lastObservedTime = finding.lastObservedTime
            firstSequence = String(finding.supportingFrameRange.first.rawValue)
            lastSequence = String(finding.supportingFrameRange.last.rawValue)
            supportingObservationCount = finding.supportingObservationCount
            analysisSessionID = finding.sessionID.rawValue
            sourceAnalyzerIDs = finding.sourceAnalyzerIDs.map(\.rawValue)
            lifecycle = finding.lifecycleState.rawValue
            relevantText = finding.relevantText
            estimatedContrast = finding.estimatedContrastRatio?.value
        }
    }
}

nonisolated enum ScanStorageMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ScanStorageSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
