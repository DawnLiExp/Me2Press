//
//  ConversionEvent.swift
//  Me2Press
//
//  Event bridge between background conversion workers and @MainActor UI state.
//

import Foundation

enum ConversionLogLevel: Sendable {
    case info
    case warn
    case error
}

typealias ConversionEventSink = @Sendable (ConversionEvent) async -> Void

enum ConversionEvent: Sendable {
    case batchStarted(totalFiles: Int, isConcurrent: Bool)
    case itemStarted(index: Int, name: String)
    case progress(local: Double, step: String)
    case simulation(from: Double, to: Double, step: String, rate: Double)
    case volumeLabel(String)
    case itemCompleted(name: String)
    case itemFailed(name: String, errorDescription: String, recoverySuggestion: String?)
    case log(level: ConversionLogLevel, message: String)
    case batchCompleted(totalFiles: Int, elapsed: String)
    case batchCancelled
}
