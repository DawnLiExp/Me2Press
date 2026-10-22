//
//  LogView.swift
//  Me2Press
//
//  View for displaying application logs with copy/clear controls.
//

import SwiftUI

struct LogView: View {
    @Environment(LogManager.self) private var logger

    @State private var followsLatest = true
    @State private var userIsScrolling = false

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
                .onScrollPhaseChange { _, phase in
                    userIsScrolling = phase == .interacting || phase == .decelerating
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 40
                } action: { _, nearBottom in
                    if userIsScrolling || nearBottom { followsLatest = nearBottom }
                }
                .onChange(of: logger.entries.last?.id) { _, _ in
                    if followsLatest, !userIsScrolling, let last = logger.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = logger.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button(String(localized: "log.latest")) {
                            followsLatest = true
                            if let last = logger.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        .padding(12)
                    }
                }
            }

            // MARK: Footer — 操作按钮移至底部

            HStack {
                Button(action: logger.copyAll) {
                    Label(LocalizedStringResource("button.copy_log"), systemImage: "doc.on.doc")
                }
                .disabled(logger.entries.isEmpty)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))

                Spacer()

                Button(action: logger.clear) {
                    Label(LocalizedStringResource("button.clear_log"), systemImage: "trash")
                }
                .disabled(logger.entries.isEmpty)
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
