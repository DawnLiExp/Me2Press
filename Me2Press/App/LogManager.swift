//
//  LogManager.swift
//  Me2Press
//
//  Centralized log state management.
//

import AppKit
import SwiftUI

@MainActor
@Observable
class LogManager {
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
    }
    
    enum LogLevel {
        case info, warn, error
        
        var color: Color {
            switch self {
            case .info: return .primary
            case .warn: return .orange
            case .error: return .red
            }
        }

        var prefix: String {
            switch self {
            case .info: return "[INFO]"
            case .warn: return "[WARN]"
            case .error: return "[ERROR]"
            }
        }
    }
    
    var entries = [LogEntry]()
    private(set) var fullHistory = [LogEntry]()

    // entries: sliding window shown in the UI — capped at maxEntries to bound memory usage.
    // fullHistory: larger buffer retained independently for "Copy Log" export; its cap is
    // intentionally higher so exported logs cover more history than what the UI displays.
    private let maxEntries = 200
    private let maxFullHistory = 1_000
    
    func filtered(by level: LogLevel?) -> [LogEntry] {
        guard let level else { return entries }
        return entries.filter { $0.level == level }
    }
    
    init() {}
    
    func log(level: LogLevel = .info, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        
        entries.append(entry)
        fullHistory.append(entry)
        
        if entries.count > maxEntries { entries.removeFirst() }
        if fullHistory.count > maxFullHistory { fullHistory.removeFirst() }
    }
    
    func clear() {
        entries.removeAll()
        fullHistory.removeAll()
    }
    
    func copyAll() {
        let text = fullHistory.map { entry in
            let time = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "\(time) \(entry.level.prefix) \(entry.message)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
