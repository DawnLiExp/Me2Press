//
//  TextBookViewModel.swift
//  Me2Press
//
//  Outputs EPUB directly, or routes through kindlegen → DualMetaFix for AZW3.
//

import AppKit
import SwiftUI

enum OutputFormat: String, CaseIterable, Identifiable {
    case epub = "EPUB"
    case azw3 = "AZW3"
    var id: String {
        rawValue
    }
}

@MainActor
@Observable
class TextBookViewModel: ConversionViewModel {
    var outputFormat: OutputFormat = .azw3
    var indentParagraph: Bool = true
    var keepLineBreaks: Bool = false
    var coverImageURL: URL?

    override func accepts(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "txt"
    }

    override func validateBeforeStart(appSettings: AppSettings, logger: LogManager) -> Bool {
        if outputFormat == .azw3, !appSettings.isKindleGenReady {
            logger.log(level: .error, "kindlegen is not configured for AZW3 conversion.")
            return false
        }
        return true
    }

    override func convertItem(_ url: URL, index: Int, appSettings: AppSettings, logger: LogManager) async throws {
        let log = AppLogger(category: "TextBook", uiLogger: logger)
        let name = url.deletingPathExtension().lastPathComponent
        let fileURL = url
        let format = outputFormat
        let indent = indentParagraph
        let keepBreaks = keepLineBreaks
        let cover = coverImageURL
        let chapterPatterns = appSettings.chapterPatterns
        let author = appSettings.authorName
        // Optional because kindlegenURL may be nil when outputting EPUB;
        // the AZW3 path is guarded by validateBeforeStart so `if let runner` always succeeds there.
        let runner: KindleGenRunner? = appSettings.kindlegenURL.map { KindleGenRunner(kindlegenPath: $0) }

        // ── Step 1: Parse TXT ─────────────────────────────────
        let isAZW3 = (format == .azw3)
        progress.set(local: 0.0, step: String(localized: "progress.parsing"))
        var t = CFAbsoluteTimeGetCurrent()
        let parser = TXTParser()
        let parsedBook = try await parser.parse(
            url: fileURL,
            indentParagraph: indent,
            keepLineBreaks: keepBreaks,
            chapterPatterns: chapterPatterns
        )
        progress.set(local: isAZW3 ? 0.07 : 0.12,
                     step: String(localized: "progress.parsing"))
        logStep(name, step: String(localized: "log.step.parse_txt"), since: t, info: "chapters=\(parsedBook.chapters.count)", log: log)

        // ── Prepare temp dirs ─────────────────────────────────
        try Task.checkCancellation()

        let outputFolder = fileURL.deletingLastPathComponent()
        let tempDir = outputFolder.appendingPathComponent(".me2press_tmp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let epubContentDir = tempDir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: epubContentDir, withIntermediateDirectories: true)
        let uuid = UUID().uuidString

        var actualCover = cover
        if actualCover == nil {
            // Auto-generate a cover when no custom cover is provided so the EPUB always has one.
            let genCoverURL = tempDir.appendingPathComponent("generated_cover.jpg")
            try await CoverGenerator.generateAsync(title: name, author: author, to: genCoverURL)
            actualCover = genCoverURL
        }

        // ── Step 2: Build EPUB ────────────────────────────────
        try Task.checkCancellation()
        progress.set(local: isAZW3 ? 0.07 : 0.12,
                     step: String(localized: "progress.building_epub"))
        t = CFAbsoluteTimeGetCurrent()
        try await EPUBBuilder.buildAsync(
            book: parsedBook,
            uuid: uuid,
            coverImage: actualCover,
            indentParagraph: indent,
            author: author,
            tempDir: epubContentDir
        )
        progress.set(local: isAZW3 ? 0.17 : 0.28,
                     step: String(localized: "progress.building_epub"))
        logStep(name, step: String(localized: "log.step.build_epub"), since: t, log: log)

        let tempEpubURL = tempDir.appendingPathComponent("\(name).epub")

        // ── Step 3: Pack ZIP (simulate) ───────────────────────
        let zipFrom: Double = isAZW3 ? 0.17 : 0.28
        let zipTo: Double = isAZW3 ? 0.35 : 1.0
        let zipSim = progress.startSimulation(
            from: zipFrom, to: zipTo,
            step: String(localized: "progress.packing"), rate: 0.15
        )
        t = CFAbsoluteTimeGetCurrent()
        try await ZIPWriter.pack(directoryURL: epubContentDir, to: tempEpubURL)
        zipSim.cancel()
        progress.set(local: zipTo, step: String(localized: "progress.packing"))
        logStep(name, step: String(localized: "log.step.pack_zip"), since: t, log: log)

        if format == .azw3 {
            if let runner {
                // ── Step 4: kindlegen (simulate) ──────────────
                let kgSim = progress.startSimulation(
                    from: 0.35, to: 0.95,
                    step: String(localized: "progress.kindlegen"), rate: 0.08
                )
                t = CFAbsoluteTimeGetCurrent()
                let mobiPath = try await runner.convert(epubPath: tempEpubURL)
                kgSim.cancel()
                progress.set(local: 0.95, step: String(localized: "progress.kindlegen"))
                logStep(name, step: String(localized: "log.step.kindlegen"), since: t, log: log)

                let azw3Path = outputFolder.appendingPathComponent("\(name).azw3")
                try? FileManager.default.removeItem(at: azw3Path)
                try FileManager.default.moveItem(at: mobiPath, to: azw3Path)
                try? FileManager.default.removeItem(at: tempEpubURL)

                // ── Step 5: DualMetaFix ───────────────────────
                progress.set(local: 0.95, step: String(localized: "progress.fixing_meta"))
                t = CFAbsoluteTimeGetCurrent()
                try await DualMetaFix.fixAsync(mobiPath: azw3Path, uuid: uuid)
                progress.set(local: 1.0, step: String(localized: "progress.fixing_meta"))
                logStep(name, step: String(localized: "log.step.dualmetafix"), since: t, log: log)
            }
        } else {
            let targetEpubURL = outputFolder.appendingPathComponent("\(name).epub")
            try? FileManager.default.removeItem(at: targetEpubURL)
            try FileManager.default.moveItem(at: tempEpubURL, to: targetEpubURL)
        }
    }
}
