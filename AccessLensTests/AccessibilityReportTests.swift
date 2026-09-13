import PDFKit
import XCTest
@testable import AccessLens

final class AccessibilityReportTests: XCTestCase {
    private var generator: AccessibilityReportGenerator {
        AccessibilityReportGenerator(locale: Locale(identifier: "en_AU"), timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    func testReportMetadataSummaryGuidanceAndDeterministicOrder() throws {
        let base = ScanPersistenceFixtures.scan(findingCount: 2)
        let passage = ScanPersistenceFixtures.passageFinding()
        let scan = CompletedScan(sessionID: base.id, startedAt: base.startedAt, completedAt: base.completedAt,
                                 findings: [passage] + base.findings)
        let report = try generator.generate(from: scan)
        XCTAssertEqual(report.title, "AccessLens Accessibility Review")
        XCTAssertEqual(report.formatVersion, 1)
        XCTAssertEqual(report.scanDate, scan.completedAt)
        XCTAssertTrue(report.scanDateText.contains("1970"))
        XCTAssertEqual(report.findings.count, 3)
        XCTAssertTrue(report.summary.contains("3 potential issues"))
        XCTAssertTrue(report.findings[0].sections[0].paragraphs.contains("Recognized text: ELEVATOR"))
        XCTAssertEqual(report.findings.last?.title, "Potential narrow passage")
        let guidance = DeterministicAccessibilityGuidanceProvider().guidance(for: base.findings[1])
        XCTAssertTrue(report.plainText.contains(guidance.whatToCheck[0].text))
        XCTAssertTrue(report.plainText.contains(guidance.possibleImprovements[0].text))
        XCTAssertTrue(report.limitations.contains(ReportCopy.disclaimer))
    }

    func testZeroFindingReportDoesNotCertifyEnvironment() throws {
        let report = try generator.generate(from: ScanPersistenceFixtures.scan(findingCount: 0))
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.summary, ReportCopy.zeroFindings)
        XCTAssertTrue(report.plainText.contains("does not confirm"))
        XCTAssertTrue(report.plainText.contains("does not perform a formal"))
    }

    func testAllEvidenceStrengthLabelsAndLimitedVerificationArePreserved() throws {
        let reports = try [ScanPersistenceFixtures.scan(findingCount: 2), ScanPersistenceFixtures.fusedScan()]
            .map { try generator.generate(from: $0).plainText }.joined()
        for label in ["Limited evidence", "Moderate evidence", "Strong evidence"] {
            XCTAssertTrue(reports.contains(label))
        }
        XCTAssertTrue(reports.contains("Evidence is limited. Verify"))
        XCTAssertFalse(reports.contains("confidence"))
    }

    func testPassageWidthIsLocalizedAndExplicitlyEstimatedWithProvenance() throws {
        let report = try generator.generate(from: ScanPersistenceFixtures.passageScan())
        let passage = report.findings[0].sections.first { $0.title == ReportCopy.evidence }
        let measurement = try XCTUnwrap(passage?.paragraphs.first { $0.hasPrefix("Estimated opening width:") })
        XCTAssertTrue(measurement.contains("84") || measurement.contains("0.84"))
        XCTAssertTrue(report.plainText.contains("Measurement method: RoomPlan with LiDAR"))
        XCTAssertTrue(report.plainText.contains("Measure the clear opening directly"))
    }

    func testFusedEvidenceAndQualitySurviveWithoutReanalysis() throws {
        let scan = ScanPersistenceFixtures.fusedScan()
        let report = try generator.generate(from: scan)
        XCTAssertTrue(report.plainText.contains(scan.findings[0].evidenceSummary))
        XCTAssertTrue(report.plainText.contains(scan.findings[0].qualityContext!.summary))
        XCTAssertTrue(report.qualitySummary!.contains("Limited"))
        XCTAssertTrue(report.qualitySummary!.contains(scan.qualitySummary!.summary))
    }

    func testUnknownCategoryGuidanceRendersGenericReportWithoutInventingEvidence() {
        let fallback = DeterministicAccessibilityGuidanceProvider().fallbackGuidance()
        let finding = generator.reportFinding(guidance: fallback)
        XCTAssertEqual(finding.title, "Review this finding")
        XCTAssertTrue(finding.sections[0].paragraphs[0].contains("cannot interpret"))
        XCTAssertFalse(finding.sections.contains { $0.title == ReportCopy.improvements })
        XCTAssertFalse(finding.sections.flatMap(\.paragraphs).contains { $0.contains("Strong evidence") })
    }

    func testLegacyVersionOneRecordWithoutNewMetadataGeneratesReport() throws {
        let scan = ScanPersistenceFixtures.scan()
        let record = try ScanStorageMapper.stored(scan)
        record.recordVersion = 1
        let legacy = try ScanStorageMapper.domain(record)
        let report = try generator.generate(from: legacy)
        XCTAssertNil(report.qualitySummary)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertTrue(report.plainText.contains("EXIT"))
    }

    func testReportIsEquivalentForRepeatedGenerationAndInputPermutation() throws {
        let scan = ScanPersistenceFixtures.scan(findingCount: 3)
        let reordered = CompletedScan(sessionID: scan.id, startedAt: scan.startedAt,
            completedAt: scan.completedAt, findings: scan.findings.reversed())
        XCTAssertEqual(try generator.generate(from: scan), try generator.generate(from: scan))
        XCTAssertEqual(try generator.generate(from: scan), try generator.generate(from: reordered))
    }

    func testReportContainsNoInternalIdentifiersOrFrameMetadata() throws {
        let scan = ScanPersistenceFixtures.fusedScan()
        let content = try generator.generate(from: scan).plainText
        XCTAssertFalse(content.contains(scan.id.uuidString))
        for finding in scan.findings {
            XCTAssertFalse(content.contains(finding.id.uuidString))
            XCTAssertFalse(content.contains(finding.sessionID.rawValue.uuidString))
            for source in finding.sourceAnalyzerIDs { XCTAssertFalse(content.contains(source.rawValue)) }
        }
        XCTAssertFalse(content.contains("18446744073709551615"))
    }

    func testInvalidAndOversizedScansReturnTypedFailure() {
        let scan = ScanPersistenceFixtures.scan(findingCount: 101)
        XCTAssertThrowsError(try generator.generate(from: scan)) { XCTAssertEqual($0 as? ReportError, .invalidReportData) }
    }

    func testPDFHasSelectableTextMetadataAndAllReportSections() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = AccessibilityReportPDFExporter(generator: generator, directory: folder)
        let report = try await exporter.report(for: ScanPersistenceFixtures.passageScan())
        let url = try await exporter.export(report)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 0)
        XCTAssertLessThanOrEqual(document.pageCount, 4)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains(report.title))
        XCTAssertTrue(text.contains("Estimated opening width:"))
        XCTAssertTrue(text.contains("Possible improvements"))
        XCTAssertTrue(text.contains("certify compliance"))
        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, report.title)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1_000)
        attachPDF(url, name: "Passage report layout")
    }

    func testLongPDFPaginationPreservesEveryUniqueParagraphIncludingLast() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base = try generator.generate(from: ScanPersistenceFixtures.scan(findingCount: 0))
        let paragraphs = (0..<120).map {
            "UniqueParagraph\($0) " + String(repeating: "Review the environment directly and verify the observation. ", count: 12)
        }
        let report = AccessibilityReport(formatVersion: base.formatVersion, title: base.title,
            scanDate: base.scanDate, scanDateText: base.scanDateText, introduction: base.introduction,
            summary: "Long report layout fixture", qualitySummary: nil,
            findings: [.init(title: "Long finding", sections: [.init(title: "What to check", paragraphs: paragraphs)])],
            limitations: ["FinalReportMarker", ReportCopy.disclaimer])
        let exporter = AccessibilityReportPDFExporter(directory: folder)
        let url = try await exporter.export(report)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 10)
        XCTAssertLessThan(document.pageCount, 100)
        let text = try XCTUnwrap(document.string)
        for index in 0..<120 { XCTAssertTrue(text.contains("UniqueParagraph\(index) "), "Missing paragraph \(index)") }
        XCTAssertTrue(text.contains("FinalReportMarker"))
        attachPDF(url, name: "Long report pagination")
    }

    func testSingleOversizedParagraphContinuesAcrossPagesIncludingUnicode() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = AccessibilityReport(formatVersion: 1, title: "Unicode report", scanDate: .distantPast,
            scanDateText: "Scan", introduction: String(repeating: "Entrée — café. Check directly. ", count: 1_000) + " EndOfParagraph",
            summary: "Summary", qualitySummary: nil, findings: [], limitations: [ReportCopy.disclaimer])
        let url = try await AccessibilityReportPDFExporter(directory: folder).export(report)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("EndOfParagraph") == true)
        XCTAssertTrue(pdf.string?.contains("Entrée") == true)
    }

    func testManyFinalizedFindingsProduceAllNumberedSections() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = try generator.generate(from: ScanPersistenceFixtures.scan(findingCount: 20))
        let url = try await AccessibilityReportPDFExporter(directory: folder).export(report)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 10)
        let text = try XCTUnwrap(pdf.string)
        for index in 1...20 { XCTAssertTrue(text.contains("\(index). Potential low contrast")) }
        XCTAssertTrue(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains(ReportCopy.disclaimer))
    }

    func testCancelledRendererRemovesPartialFileWithoutReportingFailure() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = AccessibilityReportPDFExporter(renderer: CancelledRenderer(), directory: folder)
        do { _ = try await exporter.export(generator.generate(from: ScanPersistenceFixtures.scan())); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    func testRenderingFailureRemovesPartialExportAndPreservesTypedError() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = AccessibilityReportPDFExporter(renderer: BrokenRenderer(), directory: folder)
        let report = try generator.generate(from: ScanPersistenceFixtures.scan())
        do { _ = try await exporter.export(report); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ReportError, .renderingFailed) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    func testFileWriteFailureIsTyped() async throws {
        let file = temporaryDirectory()
        try Data("not a directory".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let exporter = AccessibilityReportPDFExporter(directory: file)
        do { _ = try await exporter.export(generator.generate(from: ScanPersistenceFixtures.scan())); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ReportError, .fileWriteFailed) }
    }

    func testFilenameIsDeterministicSafeAndCollisionsHaveSeparateDirectories() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = try generator.generate(from: ScanPersistenceFixtures.scan())
        let exporter = AccessibilityReportPDFExporter(directory: folder)
        let first = try await exporter.export(report)
        let second = try await exporter.export(report)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "AccessLens-Report-1970-01-01.pdf")
        XCTAssertEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testStaleCleanupRemovesOnlyExpiredOwnedDirectories() async throws {
        let folder = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = AccessibilityReportPDFExporter(directory: folder)
        let url = try await exporter.export(generator.generate(from: ScanPersistenceFixtures.scan()))
        let unrelated = folder.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let old = Date(timeIntervalSinceNow: -90_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: unrelated.path)
        try await exporter.cleanStaleExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @MainActor
    func testViewModelFailureAndRetryAreExplicitAndPreviewRemainsAvailable() async {
        let exporter = RetryReportExporter()
        let model = AccessibilityReportViewModel(scan: ScanPersistenceFixtures.scan(), exporter: exporter)
        await model.load()
        await model.prepareExport()
        XCTAssertEqual(model.exportState, .failed(.fileWriteFailed))
        guard case .ready = model.preview else { return XCTFail("Preview must survive export failure") }
        await model.prepareExport()
        guard case .ready = model.exportState else { return XCTFail("Retry should prepare export") }
    }

    @MainActor
    func testCancellationDoesNotPublishLateReadyState() async {
        let model = AccessibilityReportViewModel(scan: ScanPersistenceFixtures.scan(), exporter: SuspendingReportExporter())
        await model.load()
        let task = Task { await model.prepareExport() }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertEqual(model.exportState, .idle)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AccessLensReportTests-\(UUID().uuidString)")
    }

    private func attachPDF(_ url: URL, name: String) {
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct BrokenRenderer: ReportPDFRendering {
    func render(_ report: AccessibilityReport, to url: URL) throws {
        try Data("partial".utf8).write(to: url)
        throw ReportError.renderingFailed
    }
}

private struct CancelledRenderer: ReportPDFRendering {
    func render(_ report: AccessibilityReport, to url: URL) throws {
        try Data("partial".utf8).write(to: url)
        throw CancellationError()
    }
}

private actor RetryReportExporter: AccessibilityReportExporting {
    var attempts = 0
    func report(for scan: CompletedScan) throws -> AccessibilityReport { try AccessibilityReportGenerator().generate(from: scan) }
    func export(_ report: AccessibilityReport) throws -> URL {
        attempts += 1
        if attempts == 1 { throw ReportError.fileWriteFailed }
        return URL(fileURLWithPath: "/tmp/report-test.pdf")
    }
}

private actor SuspendingReportExporter: AccessibilityReportExporting {
    func report(for scan: CompletedScan) throws -> AccessibilityReport { try AccessibilityReportGenerator().generate(from: scan) }
    func export(_ report: AccessibilityReport) async throws -> URL {
        try await Task.sleep(for: .seconds(30))
        return URL(fileURLWithPath: "/tmp/report-test.pdf")
    }
}
