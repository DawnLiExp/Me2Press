//
//  TextConversionWorker.swift
//  Me2Press
//
//  Background TXT conversion pipeline.
//

import Foundation

enum TextConversionWorker {
    nonisolated static func run(
        job: TextConversionJob,
        eventSink: @escaping ConversionEventSink
    ) async throws {
        let name = job.sourceURL.deletingPathExtension().lastPathComponent
        let fileURL = job.sourceURL
        let isAZW3 = (job.outputFormat == .azw3)

        await ConversionWorkerSupport.emitProgress(
            local: 0.0,
            step: String(localized: "progress.parsing"),
            eventSink: eventSink
        )
        var t = CFAbsoluteTimeGetCurrent()

        let parser = TXTParser()
        let parsedBook = try await parser.parse(
            url: fileURL,
            indentParagraph: job.indentParagraph,
            keepLineBreaks: job.keepLineBreaks,
            chapterPatterns: job.chapterPatterns
        )

        await ConversionWorkerSupport.emitProgress(
            local: isAZW3 ? 0.07 : 0.12,
            step: String(localized: "progress.parsing"),
            eventSink: eventSink
        )
        await ConversionWorkerSupport.emitStepLog(
            name: name,
            step: String(localized: "log.step.parse_txt"),
            since: t,
            info: "chapters=\(parsedBook.chapters.count)",
            eventSink: eventSink
        )

        try Task.checkCancellation()

        let outputFolder = fileURL.deletingLastPathComponent()
        let workspace = try TemporaryWorkspace.create(nextTo: outputFolder)
        defer { workspace.cleanup() }

        var actualCover = job.coverImageURL
        if actualCover == nil {
            let generatedCoverURL = workspace.generatedCoverURL()
            try await CoverGenerator.generateAsync(
                title: name,
                author: job.authorName,
                to: generatedCoverURL
            )
            actualCover = generatedCoverURL
        }

        try Task.checkCancellation()
        await ConversionWorkerSupport.emitProgress(
            local: isAZW3 ? 0.07 : 0.12,
            step: String(localized: "progress.building_epub"),
            eventSink: eventSink
        )
        t = CFAbsoluteTimeGetCurrent()
        try await EPUBBuilder.buildAsync(
            book: parsedBook,
            uuid: workspace.uuid,
            coverImage: actualCover,
            indentParagraph: job.indentParagraph,
            author: job.authorName,
            tempDir: workspace.contentURL
        )
        await ConversionWorkerSupport.emitProgress(
            local: isAZW3 ? 0.17 : 0.28,
            step: String(localized: "progress.building_epub"),
            eventSink: eventSink
        )
        await ConversionWorkerSupport.emitStepLog(
            name: name,
            step: String(localized: "log.step.build_epub"),
            since: t,
            eventSink: eventSink
        )

        let tempEpubURL = workspace.epubURL(named: name)
        let zipFrom: Double = isAZW3 ? 0.17 : 0.28
        let zipTo: Double = isAZW3 ? 0.35 : 1.0

        await ConversionWorkerSupport.startSimulation(
            from: zipFrom,
            to: zipTo,
            step: String(localized: "progress.packing"),
            rate: 0.15,
            eventSink: eventSink
        )
        t = CFAbsoluteTimeGetCurrent()
        try await ZIPWriter.pack(directoryURL: workspace.contentURL, to: tempEpubURL)
        await ConversionWorkerSupport.emitProgress(
            local: zipTo,
            step: String(localized: "progress.packing"),
            eventSink: eventSink
        )
        await ConversionWorkerSupport.emitStepLog(
            name: name,
            step: String(localized: "log.step.pack_zip"),
            since: t,
            eventSink: eventSink
        )

        if job.outputFormat == .azw3, let kindlegenURL = job.kindlegenURL {
            let runner = KindleGenRunner(kindlegenPath: kindlegenURL)

            await ConversionWorkerSupport.startSimulation(
                from: 0.35,
                to: 0.95,
                step: String(localized: "progress.kindlegen"),
                rate: 0.08,
                eventSink: eventSink
            )
            t = CFAbsoluteTimeGetCurrent()
            let mobiPath = try await runner.convert(epubPath: tempEpubURL)
            await ConversionWorkerSupport.emitProgress(
                local: 0.95,
                step: String(localized: "progress.kindlegen"),
                eventSink: eventSink
            )
            await ConversionWorkerSupport.emitStepLog(
                name: name,
                step: String(localized: "log.step.kindlegen"),
                since: t,
                eventSink: eventSink
            )

            let azw3Path = outputFolder.appendingPathComponent("\(name).azw3")
            try ConversionWorkerSupport.moveReplacingExisting(from: mobiPath, to: azw3Path)
            try? FileManager.default.removeItem(at: tempEpubURL)

            await ConversionWorkerSupport.emitProgress(
                local: 0.95,
                step: String(localized: "progress.fixing_meta"),
                eventSink: eventSink
            )
            t = CFAbsoluteTimeGetCurrent()
            try await DualMetaFix.fixAsync(mobiPath: azw3Path, uuid: workspace.uuid)
            await ConversionWorkerSupport.emitProgress(
                local: 1.0,
                step: String(localized: "progress.fixing_meta"),
                eventSink: eventSink
            )
            await ConversionWorkerSupport.emitStepLog(
                name: name,
                step: String(localized: "log.step.dualmetafix"),
                since: t,
                eventSink: eventSink
            )
        } else {
            let targetEpubURL = outputFolder.appendingPathComponent("\(name).epub")
            try ConversionWorkerSupport.moveReplacingExisting(from: tempEpubURL, to: targetEpubURL)
        }
    }
}
