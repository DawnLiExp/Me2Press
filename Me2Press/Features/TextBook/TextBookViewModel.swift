//
//  TextBookViewModel.swift
//  Me2Press
//
//  @MainActor UI state for TXT conversion; heavy work runs through ConversionCoordinator.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class TextBookViewModel {
    var items: [URL] = []
    var isConverting = false
    var isStopping = false
    var isImporting = false
    let progress = ConversionProgress()
    private let progressSimulator = ConversionProgressSimulator()

    var outputFormat: OutputFormat = .azw3
    var indentParagraph: Bool = true
    var keepLineBreaks: Bool = false
    private var conversionTask: Task<Void, Never>?
    private var presenter: ConversionEventPresenter?
    private var covers: [URL: URL] = [:]
    private var lastJobs: [URL: TextConversionJob] = [:]

    func coverURL(for source: URL) -> URL? {
        covers[source.resolvingSymlinksInPath().standardizedFileURL]
    }

    func setCover(_ cover: URL?, for source: URL) {
        covers[source.resolvingSymlinksInPath().standardizedFileURL] = cover
    }

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
        setCover(nil, for: url)
        lastJobs.removeValue(forKey: url.resolvingSymlinksInPath().standardizedFileURL)
    }

    func clearAll() {
        items.removeAll()
        covers.removeAll()
        lastJobs.removeAll()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func retryFailed(appSettings: AppSettings, logger: LogManager) {
        guard !isConverting else { return }
        items = progress.failures.map(\.sourceURL)
        startConversion(appSettings: appSettings, logger: logger, retrying: true)
    }

    func stopConversion() {
        guard isConverting, !isStopping else { return }
        isStopping = true
        presenter?.cancelTransientWork()
        conversionTask?.cancel()
    }

    func startConversion(appSettings: AppSettings, logger: LogManager) {
        startConversion(appSettings: appSettings, logger: logger, retrying: false)
    }

    private func startConversion(appSettings: AppSettings, logger: LogManager, retrying: Bool) {
        guard !items.isEmpty, !isConverting, !isImporting else { return }
        if outputFormat == .azw3, !appSettings.isKindleGenReady {
            logger.log(level: .error, "kindlegen is not configured for AZW3 conversion.")
            return
        }

        let jobs = items.map { source in
            let previous = retrying ? lastJobs[source.resolvingSymlinksInPath().standardizedFileURL] : nil
            let cover = previous != nil ? previous?.coverImageURL : coverURL(for: source)
            return TextConversionJob(
                sourceURL: source,
                outputFormat: outputFormat,
                indentParagraph: indentParagraph,
                keepLineBreaks: keepLineBreaks,
                coverImageURL: cover,
                chapterPatterns: appSettings.chapterPatterns,
                authorName: appSettings.authorName,
                kindlegenURL: appSettings.kindlegenURL
            )
        }
        lastJobs = Dictionary(uniqueKeysWithValues: jobs.map {
            ($0.sourceURL.resolvingSymlinksInPath().standardizedFileURL, $0)
        })
        let maxConcurrency = appSettings.maxConcurrency
        let progress = self.progress
        let presenter = ConversionEventPresenter(
            progress: progress,
            logger: logger,
            simulator: progressSimulator
        )
        let coordinator = ConversionCoordinator()

        progress.beginBatch(totalFiles: jobs.count)
        progress.isConcurrent = maxConcurrency > 1
        isStopping = false
        isConverting = true
        self.presenter = presenter
        conversionTask = Task { [weak self] in
            let sink: ConversionEventSink = { event in
                await MainActor.run {
                    presenter.handle(event)
                }
            }

            defer {
                self?.presenter?.cancelTransientWork()
                self?.presenter = nil
                self?.isConverting = false
                self?.isStopping = false
                self?.conversionTask = nil
            }

            await coordinator.runBatch(
                jobs: jobs.map(ConversionJob.text),
                maxConcurrency: maxConcurrency,
                eventSink: sink
            )
        }
    }
}
