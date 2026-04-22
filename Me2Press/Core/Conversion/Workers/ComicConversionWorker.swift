//
//  ComicConversionWorker.swift
//  Me2Press
//
//  Background comic conversion pipeline.
//

import Foundation

enum ComicConversionWorker {
    nonisolated static func run(
        job: ComicConversionJob,
        eventSink: @escaping ConversionEventSink
    ) async throws {
        let runner = KindleGenRunner(kindlegenPath: job.kindlegenURL)
        let folderURL = job.sourceFolderURL
        let baseName = folderURL.lastPathComponent
        let outputFolder = folderURL.deletingLastPathComponent()

        await ConversionWorkerSupport.emitProgress(
            local: 0.0,
            step: String(localized: "progress.scanning"),
            eventSink: eventSink
        )

        let allImages = ComicEPUBBuilder.collectImageURLs(
            in: folderURL,
            fileManager: FileManager.default
        )
        guard !allImages.isEmpty else {
            throw Me2PressError.noImagesFound(folderName: baseName)
        }

        let volumes = ComicVolumeSplitter.split(imageURLs: allImages)
        let totalVolumes = volumes.count

        if totalVolumes > 1 {
            await ConversionWorkerSupport.emitLog(
                .info,
                String(localized: "log.split_volumes \(totalVolumes)"),
                eventSink: eventSink
            )
        }

        for (volIdx, volumeImages) in volumes.enumerated() {
            try Task.checkCancellation()

            let volNumber = volIdx + 1
            let volName = outputName(base: baseName, volumeIndex: volNumber, totalVolumes: totalVolumes)
            let volSpan = 1.0 / Double(totalVolumes)
            let volBase = Double(volIdx) * volSpan

            func emitVolumeProgress(_ local: Double, step: String) async {
                await ConversionWorkerSupport.emitProgress(
                    local: volBase + volSpan * local,
                    step: step,
                    eventSink: eventSink
                )
            }

            func emitVolumeSimulation(_ from: Double, _ to: Double, step: String, rate: Double) async {
                await ConversionWorkerSupport.startSimulation(
                    from: volBase + volSpan * from,
                    to: volBase + volSpan * to,
                    step: step,
                    rate: rate,
                    eventSink: eventSink
                )
            }

            await eventSink(.volumeLabel(
                totalVolumes > 1
                    ? String(localized: "progress.volume \(volNumber) \(totalVolumes)")
                    : ""
            ))

            let workspace = try TemporaryWorkspace.create(nextTo: outputFolder)
            defer { workspace.cleanup() }

            do {
                await emitVolumeProgress(0.0, step: String(localized: "progress.building_epub"))
                let t1 = CFAbsoluteTimeGetCurrent()
                try await ComicEPUBBuilder.buildAsync(
                    images: volumeImages,
                    title: volName,
                    uuid: workspace.uuid,
                    author: job.authorName,
                    tempDir: workspace.contentURL
                )
                await emitVolumeProgress(0.20, step: String(localized: "progress.building_epub"))
                await ConversionWorkerSupport.emitStepLog(
                    name: volName,
                    step: String(localized: "log.step.build_epub"),
                    since: t1,
                    eventSink: eventSink
                )

                let tempEpubURL = workspace.epubURL(named: volName)
                await emitVolumeSimulation(
                    0.20,
                    0.45,
                    step: String(localized: "progress.packing"),
                    rate: 0.10
                )
                let t2 = CFAbsoluteTimeGetCurrent()
                try await ZIPWriter.pack(directoryURL: workspace.contentURL, to: tempEpubURL)
                await emitVolumeProgress(0.45, step: String(localized: "progress.packing"))
                await ConversionWorkerSupport.emitStepLog(
                    name: volName,
                    step: String(localized: "log.step.pack_zip"),
                    since: t2,
                    eventSink: eventSink
                )

                await emitVolumeSimulation(
                    0.45,
                    0.95,
                    step: String(localized: "progress.kindlegen"),
                    rate: 0.06
                )
                let t3 = CFAbsoluteTimeGetCurrent()
                let mobiPath = try await runner.convert(epubPath: tempEpubURL)
                await emitVolumeProgress(0.95, step: String(localized: "progress.kindlegen"))
                await ConversionWorkerSupport.emitStepLog(
                    name: volName,
                    step: String(localized: "log.step.kindlegen"),
                    since: t3,
                    eventSink: eventSink
                )

                await emitVolumeProgress(0.95, step: String(localized: "progress.fixing_meta"))
                let t4 = CFAbsoluteTimeGetCurrent()
                try await DualMetaFix.fixAsync(mobiPath: mobiPath, uuid: workspace.uuid)
                await emitVolumeProgress(1.0, step: String(localized: "progress.fixing_meta"))
                await ConversionWorkerSupport.emitStepLog(
                    name: volName,
                    step: String(localized: "log.step.dualmetafix"),
                    since: t4,
                    eventSink: eventSink
                )

                let outputURL = outputFolder.appendingPathComponent("\(volName).mobi")
                try ConversionWorkerSupport.moveReplacingExisting(from: mobiPath, to: outputURL)
                await ConversionWorkerSupport.emitLog(
                    .info,
                    "[\(volName)] → \(outputURL.lastPathComponent)",
                    eventSink: eventSink
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if totalVolumes > 1 {
                    await ConversionWorkerSupport.emitLog(
                        .error,
                        "[\(volName)] ❌ \(error.localizedDescription)",
                        eventSink: eventSink
                    )
                } else {
                    throw error
                }
            }
        }

        await eventSink(.volumeLabel(""))
    }

    private nonisolated static func outputName(base: String, volumeIndex: Int, totalVolumes: Int) -> String {
        guard totalVolumes > 1 else { return base }
        let pad = totalVolumes >= 10 ? 2 : 1
        return "\(base) [Vol.\(String(format: "%0\(pad)d", volumeIndex))]"
    }
}
