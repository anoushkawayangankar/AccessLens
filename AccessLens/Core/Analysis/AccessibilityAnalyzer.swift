/// A narrow, independently testable analyzer boundary. Analyzers run in their
/// configured order and receive compact prior output from the same admitted
/// frame, allowing an evidence-dependent analyzer (for example contrast) to
/// operate on real OCR regions without re-running OCR or touching SwiftUI.
nonisolated protocol AccessibilityAnalyzer: Sendable {
    var identifier: AnalyzerIdentifier { get }

    func analyze(
        _ context: AnalysisContext,
        priorOutput: AnalyzerOutput
    ) async throws -> AnalyzerOutput
}
