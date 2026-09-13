import CoreGraphics
import CoreText
import Foundation
import OSLog

nonisolated protocol AccessibilityReportExporting: Sendable {
    func report(for scan: CompletedScan) async throws -> AccessibilityReport
    func export(_ report: AccessibilityReport) async throws -> URL
}

nonisolated protocol ReportPDFRendering: Sendable {
    func render(_ report: AccessibilityReport, to url: URL) throws
}

/// Core Text glyphs are written directly to a PDF consumer, never page images.
/// Every paragraph continues from its actual visible UTF-16 range on the next
/// page. No SwiftUI/UIKit layout or full-document raster buffer is involved.
nonisolated struct CoreTextReportPDFRenderer: ReportPDFRendering {
    static let maximumCharacters = 4_000_000
    static let maximumPages = 1_000

    func render(_ report: AccessibilityReport, to url: URL) throws {
        try Task.checkCancellation()
        let blocks = report.blocks
        guard report.formatVersion == 1, !report.title.isEmpty, report.scanDate.timeIntervalSince1970.isFinite,
              blocks.reduce(0, { $0 + $1.text.utf16.count }) <= Self.maximumCharacters else {
            throw ReportError.invalidReportData
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4 points
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                  [kCGPDFContextTitle as String: report.title,
                   kCGPDFContextCreator as String: "AccessLens",
                   kCGPDFContextSubject as String: "Assistive observations for direct review"] as CFDictionary) else {
            throw ReportError.renderingFailed
        }
        var page = 0
        var y: CGFloat = 0
        let margin: CGFloat = 48
        let width = mediaBox.width - 2 * margin
        let bottom: CGFloat = 52
        var pageIsOpen = false
        defer {
            if pageIsOpen { context.endPDFPage() }
            context.closePDF()
        }

        func newPage() throws {
            try Task.checkCancellation()
            guard page < Self.maximumPages else { throw ReportError.invalidReportData }
            if pageIsOpen { context.endPDFPage() }
            context.beginPDFPage(nil)
            pageIsOpen = true
            page += 1
            y = mediaBox.height - margin
            context.textMatrix = .identity
            let footer = attributed(String(localized: "AccessLens · Page \(page)"), size: 9, bold: false)
            context.textPosition = CGPoint(x: margin, y: 26)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
        }

        try newPage()
        for block in blocks where !block.text.isEmpty {
            try Task.checkCancellation()
            let size: CGFloat
            switch block.style {
            case .title: size = 23
            case .findingHeading: size = 17
            case .heading: size = 12
            case .body: size = 11
            }
            let text = attributed(block.text, size: size, bold: block.style != .body)
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            var offset = 0
            // Keep a heading with at least two body lines whenever feasible.
            let required = block.style == .body ? size * 2 : size * 2 + 38
            if y - bottom < required { try newPage() }
            while offset < text.length {
                try Task.checkCancellation()
                let available = y - bottom
                let path = CGPath(rect: CGRect(x: margin, y: bottom, width: width, height: available), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { throw ReportError.renderingFailed }
                CTFrameDraw(frame, context)
                guard let lines = CTFrameGetLines(frame) as? [CTLine] else { throw ReportError.renderingFailed }
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                guard let lastLine = lines.last, let lastOrigin = origins.last else { throw ReportError.renderingFailed }
                var descent: CGFloat = 0
                CTLineGetTypographicBounds(lastLine, nil, &descent, nil)
                y = bottom + lastOrigin.y - descent - (block.style == .body ? 10 : 8)
                offset += visible.length
                if offset < text.length { try newPage() }
            }
        }
        try Task.checkCancellation()
    }

    private func attributed(_ text: String, size: CGFloat, bold: Bool) -> NSAttributedString {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
    }
}

/// One worker actor serializes report preparation, native rendering and file
/// housekeeping. Completed files survive screen dismissal so a share extension
/// can finish reading them; only abandoned/failed work is removed immediately.
actor AccessibilityReportPDFExporter: AccessibilityReportExporting {
    static let retentionInterval: TimeInterval = 24 * 60 * 60
    private let generator: AccessibilityReportGenerator
    private let renderer: any ReportPDFRendering
    private let directory: URL

    init(generator: AccessibilityReportGenerator = AccessibilityReportGenerator(),
         renderer: any ReportPDFRendering = CoreTextReportPDFRenderer(), directory: URL? = nil) {
        self.generator = generator
        self.renderer = renderer
        self.directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessLensReportExports", isDirectory: true)
    }

    func report(for scan: CompletedScan) throws -> AccessibilityReport {
        AppLog.report.info("Report preparation started")
        let report = try generator.generate(from: scan)
        AppLog.report.info("Report preparation completed")
        return report
    }

    func export(_ report: AccessibilityReport) throws -> URL {
        try Task.checkCancellation()
        try cleanStaleExports()
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(Self.filename(for: report.scanDate))
        var succeeded = false
        defer {
            if !succeeded { try? FileManager.default.removeItem(at: folder) }
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            try renderer.render(report, to: url)
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue > 0,
                  let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else {
                throw ReportError.renderingFailed
            }
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            succeeded = true
            AppLog.report.info("PDF preparation completed")
            return url
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.report.error("PDF preparation failed")
            throw (error as? ReportError) ?? .fileWriteFailed
        }
    }

    /// Only UUID directories immediately inside this export-owned directory
    /// are eligible. Symlinks and unrelated files are never traversed/deleted.
    func cleanStaleExports(now: Date = .now) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        do {
            let children = try manager.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            for child in children {
                try Task.checkCancellation()
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard UUID(uuidString: child.lastPathComponent) != nil,
                      values.isDirectory == true, values.isSymbolicLink != true,
                      let date = values.contentModificationDate,
                      now.timeIntervalSince(date) > Self.retentionInterval else { continue }
                try manager.removeItem(at: child)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw ReportError.fileWriteFailed }
    }

    nonisolated static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "AccessLens-Report-\(formatter.string(from: date)).pdf"
    }
}

#if DEBUG
/// Explicit UI-test injection only; production launch never selects it.
actor FailingReportExporter: AccessibilityReportExporting {
    func report(for scan: CompletedScan) throws -> AccessibilityReport {
        try AccessibilityReportGenerator().generate(from: scan)
    }
    func export(_ report: AccessibilityReport) throws -> URL { throw ReportError.fileWriteFailed }
}
#endif
