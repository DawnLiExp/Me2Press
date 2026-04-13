//
//  EPUBBookViewModel.swift
//  Me2Press
//
//  @MainActor UI state for EPUB conversion; heavy work runs through ConversionCoordinator.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class EPUBBookViewModel {
    var items: [URL] = []
    var isConverting = false
    let progress = ConversionProgress()
    private let progressSimulator = ConversionProgressSimulator()

    private var conversionTask: Task<Void, Never>?
    private var presenter: ConversionEventPresenter?

    @discardableResult
    func add(_ urls: [URL]) async -> FileQueueView.FileQueueDropSummary {
        var added = 0
        var duplicateCount = 0
        var seenIdentities = Set(items.map(normalizedDropIdentity(for:)))

        for url in urls where url.pathExtension.lowercased() == "epub" {
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
        presenter?.cancelTransientWork()
        conversionTask?.cancel()
    }

    func startConversion(appSettings: AppSettings, logger: LogManager) {
        guard !items.isEmpty, !isConverting else { return }
        guard appSettings.isKindleGenReady, let kindlegenURL = appSettings.kindlegenURL else {
            logger.log(level: .error, "kindlegen is not configured for AZW3 conversion.")
            return
        }

        let jobs = items.map { EPUBConversionJob(sourceURL: $0, kindlegenURL: kindlegenURL) }
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
                self?.conversionTask = nil
            }

            await coordinator.runBatch(
                jobs: jobs.map(ConversionJob.epub),
                maxConcurrency: maxConcurrency,
                eventSink: sink
            )

            if !Task.isCancelled, progress.isCompleted {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
