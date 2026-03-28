//
//  ConversionViewModel.swift
//  Me2Press
//
//  Base class for batch conversion. Supports sequential (maxConcurrency = 1) with
//  fine-grained progress mapping, and concurrent (maxConcurrency 2–6) via TaskGroup
//  with true kindlegen sub-process parallelism; progress advances per completed file.
//

import AppKit
import SwiftUI

@MainActor
@Observable
class ConversionViewModel {
    var items: [URL] = []
    var isConverting = false

    let progress = ConversionProgress()

    private var conversionTask: Task<Void, Never>?

    private struct ConcurrentResult {
        let name: String
        let isCancelled: Bool
    }

    init() {}

    // MARK: - Queue management

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where accepts(url) {
            if !items.contains(url) {
                items.append(url)
                added += 1
            }
        }
        return added
    }

    final func remove(_ url: URL) {
        items.removeAll(where: { $0 == url })
    }

    final func clearAll() {
        items.removeAll()
    }

    final func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    final func stopConversion() {
        progress.cancelSimulation()
        conversionTask?.cancel()
    }

    // MARK: - Start

    final func startConversion(appSettings: AppSettings, logger: LogManager) {
        guard !items.isEmpty, !isConverting else { return }
        guard validateBeforeStart(appSettings: appSettings, logger: logger) else { return }

        let snapshot = items
        let concurrency = appSettings.maxConcurrency
        isConverting = true
        progress.beginBatch(totalFiles: snapshot.count)
        progress.isConcurrent = concurrency > 1

        let appLog = AppLogger(category: "Batch", uiLogger: logger)

        conversionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                progress.cancelSimulation()
                isConverting = false
                conversionTask = nil
            }

            let batchStart = CFAbsoluteTimeGetCurrent()

            if concurrency <= 1 {
                // ── Sequential path — behavior identical to the original single-file flow ──
                for (i, url) in snapshot.enumerated() {
                    guard !Task.isCancelled else { break }

                    let name = url.deletingPathExtension().lastPathComponent
                    progress.beginFile(index: i + 1, name: name)
                    let fileStart = CFAbsoluteTimeGetCurrent()
                    appLog.info(String(localized: "log.start \(name)"))

                    do {
                        try await convertItem(url, index: i, appSettings: appSettings, logger: logger)
                        let totalStr = String(localized: "log.total_time \(ms(fileStart))")
                        appLog.info(String(localized: "log.done \(name)") + "  \(totalStr)")
                    } catch is CancellationError {
                        appLog.warn("[\(name)] \(String(localized: "log.cancelled"))")
                        break
                    } catch let e as Me2PressError {
                        appLog.error(String(localized: "log.error \(e.localizedDescription)"), error: e)
                        if let hint = e.recoverySuggestion { appLog.warn(hint) }
                    } catch {
                        appLog.error(String(localized: "log.error \(error.localizedDescription)"), error: error)
                    }
                }

            } else {
                // ── Concurrent path — Swift 6 actor isolation notes ───────────────────────
                //
                // • group.addTask closures are nonisolated; they cannot call @MainActor methods
                //   directly. Progress writes are therefore funnelled through the @MainActor
                //   convergence point (group.next()) to avoid concurrent overwrite races.
                // • ms() is @MainActor — child tasks capture CFAbsoluteTimeGetCurrent() instead
                //   and compute elapsed time themselves without crossing the actor boundary.
                // • AppLogger is a nonisolated struct whose methods internally spawn @MainActor
                //   Tasks, making them safe to call from nonisolated closures.
                // • convertItem is @MainActor async — awaiting it across the actor boundary is
                //   legal; Swift will hop to MainActor for the call and return afterwards.

                await withTaskGroup(of: ConcurrentResult.self) { group in
                    var inFlight = 0

                    func handleResult(_ result: ConcurrentResult) async {
                        guard !result.isCancelled, !Task.isCancelled else { return }
                        await progress.markFileCompleted(name: result.name)
                    }

                    for (i, url) in snapshot.enumerated() {
                        if Task.isCancelled { break }

                        if inFlight >= concurrency {
                            if let result = await group.next() {
                                inFlight -= 1
                                await handleResult(result)
                            }
                        }

                        if Task.isCancelled { break }

                        let name = url.deletingPathExtension().lastPathComponent
                        progress.beginFile(index: i + 1, name: name)
                        appLog.info(String(localized: "log.start \(name)"))

                        // Capture timestamp before entering nonisolated closure (ms() is @MainActor).
                        let fileStart = CFAbsoluteTimeGetCurrent()

                        group.addTask {
                            do {
                                try await self.convertItem(
                                    url, index: i,
                                    appSettings: appSettings,
                                    logger: logger
                                )
                                let elapsed = String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - fileStart)
                                let totalStr = String(localized: "log.total_time \(elapsed)")
                                appLog.info(String(localized: "log.done \(name)") + "  \(totalStr)")
                                return ConcurrentResult(name: name, isCancelled: false)
                            } catch is CancellationError {
                                appLog.warn("[\(name)] \(String(localized: "log.cancelled"))")
                                return ConcurrentResult(name: name, isCancelled: true)
                            } catch let e as Me2PressError {
                                appLog.error(
                                    String(localized: "log.error \(e.localizedDescription)"),
                                    error: e
                                )
                                if let hint = e.recoverySuggestion { appLog.warn(hint) }
                                return ConcurrentResult(name: name, isCancelled: false)
                            } catch {
                                appLog.error(
                                    String(localized: "log.error \(error.localizedDescription)"),
                                    error: error
                                )
                                return ConcurrentResult(name: name, isCancelled: false)
                            }
                        }
                        inFlight += 1
                    }

                    if Task.isCancelled {
                        group.cancelAll()
                    }

                    while let result = await group.next() {
                        inFlight -= 1
                        await handleResult(result)
                    }
                }
            }

            // ── Batch completion / cancellation teardown ──────────────────
            if !Task.isCancelled {
                progress.value = 1.0
                progress.isCompleted = true
                appLog.info(String(localized: "log.all_items_done \(snapshot.count) \(ms(batchStart))"))
                try? await Task.sleep(for: .seconds(1))
            } else {
                appLog.warn(String(localized: "log.batch_cancelled"))
            }
        }
    }

    // MARK: - Overridable Points

    func accepts(_ url: URL) -> Bool {
        return false
    }

    func validateBeforeStart(appSettings: AppSettings, logger: LogManager) -> Bool {
        return true
    }

    func convertItem(_ url: URL, index: Int, appSettings: AppSettings, logger: LogManager) async throws {
        // Subclasses must override.
    }

    // MARK: - Utility

    final func ms(_ from: CFAbsoluteTime) -> String {
        String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - from)
    }
}

// MARK: - Logging helpers

extension ConversionViewModel {
    func logStep(_ name: String, step: String, since: CFAbsoluteTime, log: AppLogger) {
        log.info("[\(name)] \(step): \(ms(since))")
    }

    func logStep(_ name: String, step: String, since: CFAbsoluteTime, info: String, log: AppLogger) {
        log.info("[\(name)] \(step): \(ms(since))  \(info)")
    }
}
