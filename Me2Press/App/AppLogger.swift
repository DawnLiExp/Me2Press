//
//  AppLogger.swift
//  Me2Press
//
//  nonisolated Sendable struct — safe to call from any executor. os.Logger writes are
//  synchronous; LogManager UI updates are dispatched via fire-and-forget @MainActor Tasks,
//  so entries may arrive slightly out of order under heavy concurrency.
//

import Foundation
import OSLog

/// Logging facade: mirrors each message to os.Logger (synchronous, caller's executor)
/// and to the UI LogManager (asynchronous, @MainActor). Safe from nonisolated contexts.
struct AppLogger {
    private let osLog: Logger
    private let uiLogger: LogManager

    init(category: String, uiLogger: LogManager) {
        self.osLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Me2Press", category: category)
        self.uiLogger = uiLogger
    }

    nonisolated func info(_ message: String) {
        osLog.info("\(message, privacy: .public)")
        Task { @MainActor [uiLogger] in uiLogger.log(level: .info, message) }
    }

    nonisolated func warn(_ message: String) {
        osLog.warning("\(message, privacy: .public)")
        Task { @MainActor [uiLogger] in uiLogger.log(level: .warn, message) }
    }

    nonisolated func error(_ message: String, error: (any Error)? = nil) {
        if let e = error {
            osLog.error("\(message, privacy: .public): \(e.localizedDescription, privacy: .public)")
        } else {
            osLog.error("\(message, privacy: .public)")
        }
        Task { @MainActor [uiLogger] in uiLogger.log(level: .error, message) }
    }
}
