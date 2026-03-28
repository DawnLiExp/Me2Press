//
//  LogView.swift
//  Me2Press
//
//  View for displaying application logs with copy/clear controls.
//

import SwiftUI

struct LogView: View {
    @Environment(LogManager.self) private var logger

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header — 标题，不再放按钮

            HStack {
                Label(String(localized: "label.logs"), systemImage: "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            // MARK: Log entries

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logger.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: 10, design: .monospaced))

                                    Text(entry.level.label)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(entry.level.color.opacity(0.1))
                                        .foregroundStyle(entry.level.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                Text(entry.message)
                                    .foregroundStyle(entry.level == .error ? .red : .primary.opacity(0.9))
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                .onChange(of: logger.entries.count) { _, _ in
                    if let last = logger.entries.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // MARK: Footer — 操作按钮移至底部

            HStack {
                Button(action: logger.copyAll) {
                    Label(LocalizedStringResource("button.copy_log"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))

                Spacer()

                Button(action: logger.clear) {
                    Label(LocalizedStringResource("button.clear_log"), systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

extension LogManager.LogLevel {
    var label: String {
        switch self {
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}
