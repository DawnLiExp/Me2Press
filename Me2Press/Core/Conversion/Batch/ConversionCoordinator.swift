//
//  ConversionCoordinator.swift
//  Me2Press
//
//  Batch scheduling and error handling for background conversion jobs.
//

import Foundation

actor ConversionCoordinator {
    private struct ItemResult: Sendable {
        let name: String
        let isCancelled: Bool
    }

    func runBatch(
        jobs: [ConversionJob],
        maxConcurrency: Int,
        eventSink: @escaping ConversionEventSink
    ) async {
        guard !jobs.isEmpty else { return }

        let isConcurrent = maxConcurrency > 1
        await eventSink(.batchStarted(totalFiles: jobs.count, isConcurrent: isConcurrent))
        let batchStart = CFAbsoluteTimeGetCurrent()

        if maxConcurrency <= 1 {
            for (index, job) in jobs.enumerated() {
                if Task.isCancelled { break }
                let result = await Self.run(job: job, index: index, eventSink: eventSink)
                if !result.isCancelled {
                    await eventSink(.itemCompleted(name: result.name))
                }
            }
        } else {
            await withTaskGroup(of: ItemResult.self) { group in
                var inFlight = 0

                for (index, job) in jobs.enumerated() {
                    if Task.isCancelled { break }

                    if inFlight >= maxConcurrency, let result = await group.next() {
                        inFlight -= 1
                        if !result.isCancelled {
                            await eventSink(.itemCompleted(name: result.name))
                        }
                    }

                    if Task.isCancelled { break }

                    group.addTask {
                        await Self.run(job: job, index: index, eventSink: eventSink)
                    }
                    inFlight += 1
                }

                if Task.isCancelled {
                    group.cancelAll()
                }

                while let result = await group.next() {
                    inFlight -= 1
                    if !result.isCancelled {
                        await eventSink(.itemCompleted(name: result.name))
                    }
                }
            }
        }

        if Task.isCancelled {
            await eventSink(.batchCancelled)
        } else {
            await eventSink(.batchCompleted(
                totalFiles: jobs.count,
                elapsed: ConversionWorkerSupport.elapsedString(since: batchStart)
            ))
        }
    }

    private nonisolated static func run(
        job: ConversionJob,
        index: Int,
        eventSink: @escaping ConversionEventSink
    ) async -> ItemResult {
        let name = job.displayName
        await eventSink(.itemStarted(index: index + 1, name: name))
        await eventSink(.log(level: .info, message: String(localized: "log.start \(name)")))

        let fileStart = CFAbsoluteTimeGetCurrent()

        do {
            switch job {
            case .text(let textJob):
                try await TextConversionWorker.run(job: textJob, eventSink: eventSink)
            case .epub(let epubJob):
                try await EPUBConversionWorker.run(job: epubJob, eventSink: eventSink)
            case .comic(let comicJob):
                try await ComicConversionWorker.run(job: comicJob, eventSink: eventSink)
            }

            let totalStr = ConversionWorkerSupport.totalTimeString(since: fileStart)
            await eventSink(.log(level: .info, message: String(localized: "log.done \(name)") + "  \(totalStr)"))
            return ItemResult(name: name, isCancelled: false)

        } catch is CancellationError {
            await eventSink(.log(level: .warn, message: "[\(name)] \(String(localized: "log.cancelled"))"))
            return ItemResult(name: name, isCancelled: true)

        } catch let error as Me2PressError {
            await eventSink(.itemFailed(
                name: name,
                errorDescription: String(localized: "log.error \(error.localizedDescription)"),
                recoverySuggestion: error.recoverySuggestion
            ))
            return ItemResult(name: name, isCancelled: false)

        } catch {
            await eventSink(.itemFailed(
                name: name,
                errorDescription: String(localized: "log.error \(error.localizedDescription)"),
                recoverySuggestion: nil
            ))
            return ItemResult(name: name, isCancelled: false)
        }
    }
}
