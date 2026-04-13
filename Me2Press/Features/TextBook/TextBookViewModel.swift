//
//  TextBookViewModel.swift
//  Me2Press
//
//  @MainActor UI state for TXT conversion; heavy work runs through ConversionCoordinator.
//

import Foundation
import SwiftUI

enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case epub = "EPUB"
    case azw3 = "AZW3"

    var id: String {
        rawValue
    }
}

@MainActor
@Observable
class TextBookViewModel {
    var items: [URL] = []
    var isConverting = false
    let progress = ConversionProgress()
    private let progressSimulator = ConversionProgressSimulator()

    var outputFormat: OutputFormat = .azw3
    var indentParagraph: Bool = true
    var keepLineBreaks: Bool = false
    var coverImageURL: URL?

    private var conversionTask: Task<Void, Never>?

    @discardableResult
    func add(_ urls: [URL]) async -> FileQueueView.FileQueueDropSummary {
        var added = 0
        var duplicateCount = 0
        var seenIdentities = Set(items.map(normalizedDropIdentity(for:)))

        for url in urls where url.pathExtension.lowercased() == "txt" {
            let identity = normalizedDropIdentity(for: url)
            if seenIdentities.insert(identity).inserted {
                items.append(url)
                added += 1
            } else {
                duplicateCount += 1
            }
        }

        return .init(
            addedCount: added,
            duplicateCount: duplicateCount,
            contentRejectedCount: 0
        )
    }

    func remove(_ url: URL) {
        items.removeAll(where: { $0 == url })
    }

    func clearAll() {
        items.removeAll()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func stopConversion() {
        progressSimulator.cancel()
        conversionTask?.cancel()
    }

    func startConversion(appSettings: AppSettings, logger: LogManager) {
        guard !items.isEmpty, !isConverting else { return }
        if outputFormat == .azw3, !appSettings.isKindleGenReady {
            logger.log(level: .error, "kindlegen is not configured for AZW3 conversion.")
            return
        }

        let jobs = items.map {
            TextConversionJob(
                sourceURL: $0,
                outputFormat: outputFormat,
                indentParagraph: indentParagraph,
                keepLineBreaks: keepLineBreaks,
                coverImageURL: coverImageURL,
                chapterPatterns: appSettings.chapterPatterns,
                authorName: appSettings.authorName,
                kindlegenURL: appSettings.kindlegenURL
            )
        }
        let maxConcurrency = appSettings.maxConcurrency
        let progress = self.progress
        let progressSimulator = self.progressSimulator
        let coordinator = ConversionCoordinator()

        progress.beginBatch(totalFiles: jobs.count)
        progress.isConcurrent = maxConcurrency > 1
        isConverting = true
        conversionTask = Task { [weak self] in
            let sink: ConversionEventSink = { event in
                await MainActor.run {
                    Self.apply(
                        event: event,
                        progress: progress,
                        logger: logger,
                        simulator: progressSimulator
                    )
                }
            }

            defer {
                self?.progressSimulator.cancel()
                self?.isConverting = false
                self?.conversionTask = nil
            }

            await coordinator.runBatch(
                jobs: jobs.map(ConversionJob.text),
                maxConcurrency: maxConcurrency,
                eventSink: sink
            )

            if !Task.isCancelled, progress.isCompleted {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func apply(
        event: ConversionEvent,
        progress: ConversionProgress,
        logger: LogManager,
        simulator: ConversionProgressSimulator
    ) {
        switch event {
        case .batchStarted(let totalFiles, let isConcurrent):
            simulator.cancel()
            progress.beginBatch(totalFiles: totalFiles)
            progress.isConcurrent = isConcurrent

        case .itemStarted(let index, let name):
            simulator.cancel()
            progress.beginFile(index: index, name: name)

        case .progress(let local, let step):
            simulator.cancel()
            progress.set(local: local, step: step)

        case .simulation(let localFrom, let localTo, let step, let rate):
            simulator.start(
                on: progress,
                from: localFrom,
                to: localTo,
                step: step,
                rate: rate
            )

        case .volumeLabel(let label):
            progress.setVolumeLabel(label)

        case .itemCompleted(let name):
            simulator.cancel()
            progress.markFileCompleted(name: name)

        case .itemFailed(_, let errorDescription, let recoverySuggestion):
            logger.log(level: .error, errorDescription)
            if let recoverySuggestion {
                logger.log(level: .warn, recoverySuggestion)
            }

        case .log(let level, let message):
            logger.log(level: map(level), message)

        case .batchCompleted(let totalFiles, let elapsed):
            simulator.cancel()
            progress.markBatchCompleted()
            logger.log(level: .info, String(localized: "log.all_items_done \(totalFiles) \(elapsed)"))

        case .batchCancelled:
            simulator.cancel()
            progress.markBatchCancelled()
            logger.log(level: .warn, String(localized: "log.batch_cancelled"))
        }
    }

    private static func map(_ level: ConversionLogLevel) -> LogManager.LogLevel {
        switch level {
        case .info:
            .info
        case .warn:
            .warn
        case .error:
            .error
        }
    }
}
