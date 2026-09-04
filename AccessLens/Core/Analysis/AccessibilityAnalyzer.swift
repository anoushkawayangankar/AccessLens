/// A narrow, independently testable future-analysis boundary. This milestone
/// supplies no production analyzers and performs no Vision request.
nonisolated protocol AccessibilityAnalyzer: Sendable {
    var identifier: AnalyzerIdentifier { get }

    func analyze(_ context: AnalysisContext) async throws -> AnalyzerOutput
}
