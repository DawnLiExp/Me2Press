//
//  ConversionWorkerSupport.swift
//  Me2Press
//
//  Shared helpers for background conversion workers.
//

import Foundation

enum ConversionWorkerSupport {
    nonisolated static func emitProgress(
        local: Double,
        step: String,
        eventSink: ConversionEventSink
    ) async {
        await eventSink(.progress(local: local, step: step))
    }

    nonisolated static func startSimulation(
        from localFrom: Double,
        to localTo: Double,
        step: String,
        rate: Double,
        eventSink: ConversionEventSink
    ) async {
        await eventSink(.simulation(from: localFrom, to: localTo, step: step, rate: rate))
    }

    nonisolated static func emitLog(
        _ level: ConversionLogLevel,
        _ message: String,
        eventSink: ConversionEventSink
    ) async {
        await eventSink(.log(level: level, message: message))
    }

    nonisolated static func emitStepLog(
        name: String,
        step: String,
        since start: CFAbsoluteTime,
        info: String? = nil,
        eventSink: ConversionEventSink
    ) async {
        let elapsed = elapsedString(since: start)
        let message = if let info {
            "[\(name)] \(step): \(elapsed)  \(info)"
        } else {
            "[\(name)] \(step): \(elapsed)"
        }
        await emitLog(.info, message, eventSink: eventSink)
    }

    nonisolated static func elapsedString(since start: CFAbsoluteTime) -> String {
        String(format: "%.2fs", CFAbsoluteTimeGetCurrent() - start)
    }

    nonisolated static func totalTimeString(since start: CFAbsoluteTime) -> String {
        String(localized: "log.total_time \(elapsedString(since: start))")
    }

    nonisolated static func moveReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}
