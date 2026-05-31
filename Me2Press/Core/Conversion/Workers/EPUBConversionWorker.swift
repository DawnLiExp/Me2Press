//
//  EPUBConversionWorker.swift
//  Me2Press
//
//  Background EPUB to AZW3 conversion pipeline.
//

import Foundation

enum EPUBConversionWorker {
    nonisolated static func run(
        job: EPUBConversionJob,
        eventSink: @escaping ConversionEventSink
    ) async throws {
        let runner = KindleGenRunner(kindlegenPath: job.kindlegenURL)
        let name = job.sourceURL.deletingPathExtension().lastPathComponent
        let epubURL = job.sourceURL
        let uuid = UUID().uuidString
        let outputFolder = epubURL.deletingLastPathComponent()
        let workspace = try TemporaryWorkspace.create(nextTo: outputFolder)
        defer { workspace.cleanup() }

        let kindleReadyEPUBURL = try await EPUBKindleNormalizer.normalizeIfNeeded(
            epubURL: epubURL,
            workspace: workspace
        )

        await ConversionWorkerSupport.startSimulation(
            from: 0.0,
            to: 0.95,
            step: String(localized: "progress.kindlegen"),
            rate: 0.08,
            eventSink: eventSink
        )
        var t = CFAbsoluteTimeGetCurrent()
        let mobiPath = try await runner.convert(epubPath: kindleReadyEPUBURL)
        await ConversionWorkerSupport.emitProgress(
            local: 0.95,
            step: String(localized: "progress.kindlegen"),
            eventSink: eventSink
        )
        await ConversionWorkerSupport.emitStepLog(
            name: name,
            step: "kindlegen",
            since: t,
            eventSink: eventSink
        )

        let azw3Path = outputFolder.appendingPathComponent("\(name).azw3")
        try ConversionWorkerSupport.moveReplacingExisting(from: mobiPath, to: azw3Path)

        try Task.checkCancellation()
        await ConversionWorkerSupport.emitProgress(
            local: 0.95,
            step: String(localized: "progress.fixing_meta"),
            eventSink: eventSink
        )
        t = CFAbsoluteTimeGetCurrent()
        try await DualMetaFix.fixAsync(mobiPath: azw3Path, uuid: uuid)
        await ConversionWorkerSupport.emitProgress(
            local: 1.0,
            step: String(localized: "progress.fixing_meta"),
            eventSink: eventSink
        )
        await ConversionWorkerSupport.emitStepLog(
            name: name,
            step: "DualMetaFix",
            since: t,
            eventSink: eventSink
        )
    }
}
