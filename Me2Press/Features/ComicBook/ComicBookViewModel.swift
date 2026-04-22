//
//  ComicBookViewModel.swift
//  Me2Press
//
//  @MainActor UI state for comic conversion; heavy work runs through ConversionCoordinator.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class ComicBookViewModel {
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
        var contentRejectedCount = 0
        var seenSourceIdentities = Set<String>()
        var seenItemIdentities = Set(items.map(normalizedDropIdentity(for:)))

        for sourceURL in urls {
            let sourceIdentity = normalizedDropIdentity(for: sourceURL)
            if !seenSourceIdentities.insert(sourceIdentity).inserted {
                duplicateCount += 1
                continue
            }

            let resolvedFolders = await ComicFolderResolver.resolveDroppedFolders([sourceURL])
            if resolvedFolders.isEmpty {
                contentRejectedCount += 1
                continue
            }

            for folder in resolvedFolders {
                let folderIdentity = normalizedDropIdentity(for: folder)
                if seenItemIdentities.insert(folderIdentity).inserted {
                    items.append(folder)
                    added += 1
                } else {
                    duplicateCount += 1
                }
            }
        }

        return .init(
            addedCount: added,
            duplicateCount: duplicateCount,
            contentRejectedCount: contentRejectedCount
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
            logger.log(level: .error, "kindlegen is not configured.")
            return
        }

        let jobs = items.map {
            ComicConversionJob(
                sourceFolderURL: $0,
                authorName: appSettings.authorName,
                kindlegenURL: kindlegenURL
            )
        }
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
                jobs: jobs.map(ConversionJob.comic),
                maxConcurrency: maxConcurrency,
                eventSink: sink
            )

            if !Task.isCancelled, progress.isCompleted {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
