//
//  ConversionEventPresenter.swift
//  Me2Press
//
//  Centralized @MainActor projection from ConversionEvent into UI progress state
//  and the sidebar log, without introducing a separate logging framework.
//

import Foundation

@MainActor
final class ConversionEventPresenter {
    private let progress: ConversionProgress
    private let logger: LogManager
    private let simulator: ConversionProgressSimulator

    init(
        progress: ConversionProgress,
        logger: LogManager,
        simulator: ConversionProgressSimulator
    ) {
        self.progress = progress
        self.logger = logger
        self.simulator = simulator
    }

    func handle(_ event: ConversionEvent) {
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

        case .itemSucceeded:
            progress.succeededCount += 1

        case .outputCreated(let url):
            progress.outputURLs.append(url)

        case .itemFailed(let sourceURL, let name, let errorDescription, let recoverySuggestion):
            let details = [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: "\n")
            progress.failures.append(.init(sourceURL: sourceURL, message: "[\(name)] \(details)"))
            logger.log(level: .error, errorDescription)
            if let recoverySuggestion {
                logger.log(level: .warn, recoverySuggestion)
            }

        case .log(let level, let message):
            logger.log(level: map(level), message)

        case .batchCompleted(let totalFiles, let elapsed):
            simulator.cancel()
            progress.markBatchCompleted()
            if progress.isCompleted {
                logger.log(level: .info, String(localized: "log.all_items_done \(totalFiles) \(elapsed)"))
            } else {
                logger.log(level: .warn, String(localized: "result.summary \(progress.succeededCount) \(progress.failures.count)"))
            }

        case .batchCancelled:
            simulator.cancel()
            progress.markBatchCancelled()
            logger.log(level: .warn, String(localized: "log.batch_cancelled"))
        }
    }

    func cancelTransientWork() {
        simulator.cancel()
    }

    private func map(_ level: ConversionLogLevel) -> LogManager.LogLevel {
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
