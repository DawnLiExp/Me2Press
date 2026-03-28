//
//  SettingsView.swift
//  Me2Press
//
//  Preferences window: kindlegen path, concurrency, author name, chapter regex patterns.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            kindleGenSection
            authorSection
            chapterPatternsSection
            performanceSection
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 10)
    }

    // MARK: - KindleGen Section

    private var kindleGenSection: some View {
        Section {
            HStack {
                TextField(String(localized: "kindlegen Path"), text: .constant(settings.kindlegenURL?.path ?? ""))
                    .disabled(true)
                    .labelsHidden()

                Button(String(localized: "Select...")) {
                    selectKindleGen()
                }
            }

            LabeledContent {
                if settings.isKindleGenReady {
                    Text(settings.kindlegenVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "status.kindlegen.missing"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: settings.isKindleGenReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.isKindleGenReady ? .green : .red)
                    Text(String(localized: "status.kindlegen.ready"))
                }
            }
        } header: {
            Text(String(localized: "KindleGen Configuration"))
        }
    }

    // MARK: - Author Section

    private var authorSection: some View {
        Section {
            LabeledContent {
                TextField(
                    String(localized: "setting.author.placeholder"),
                    text: Binding(
                        get: { settings.authorName },
                        set: { settings.authorName = $0 }
                    )
                )
                .multilineTextAlignment(.trailing)
            } label: {
                Text(String(localized: "setting.author.label"))
            }

            Text(String(localized: "setting.author.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "setting.author.header"))
        }
    }

    // MARK: - Chapter Patterns Section

    private var chapterPatternsSection: some View {
        Section {
            // UUID-based identity prevents stale index crashes when items are deleted mid-iteration.
            ForEach(settings.chapterPatterns) { pattern in
                PatternRow(
                    pattern: Binding(
                        get: {
                            settings.chapterPatterns.first { $0.id == pattern.id } ?? pattern
                        },
                        set: { newValue in
                            if let idx = settings.chapterPatterns.firstIndex(where: { $0.id == pattern.id }) {
                                settings.chapterPatterns[idx] = newValue
                            }
                        }
                    ),
                    onDelete: {
                        settings.chapterPatterns.removeAll { $0.id == pattern.id }
                    }
                )
            }

            HStack {
                Button {
                    settings.chapterPatterns.append(ChapterPattern(value: "", level: 1))
                } label: {
                    Label(String(localized: "setting.chapter_regex.add"), systemImage: "plus.circle")
                        .font(.system(size: 13))
                }

                Spacer()

                Button {
                    settings.chapterPatterns = AppSettings.defaultChapterPatterns
                } label: {
                    Text(String(localized: "setting.chapter_regex.restore"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            // IMPORTANT: The regex hint lives in the section header tooltip rather than as inline
            // body Text, keeping the Section visually clean while remaining discoverable.
            HStack(spacing: 4) {
                Text(String(localized: "setting.chapter_regex.header"))
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .help(String(localized: "setting.chapter_regex.hint"))
            }
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "setting.concurrency.label"))
                    Spacer()
                    Text("\(settings.maxConcurrency)")
                        .monospacedDigit()
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }

                Slider(value: Binding(
                    get: { Double(settings.maxConcurrency) },
                    set: { settings.maxConcurrency = Int($0.rounded()) }
                ), in: Double(AppSettings.concurrencyRange.lowerBound) ... Double(AppSettings.concurrencyRange.upperBound), step: 1)
                    .labelsHidden()

                Text(String(localized: "setting.concurrency.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text(String(localized: "setting.performance"))
        }
    }

    // MARK: - Actions

    @MainActor
    private func selectKindleGen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "Select kindlegen executable")

        if panel.runModal() == .OK, let url = panel.url {
            settings.kindlegenURL = url
        }
    }
}

// MARK: - PatternRow

/// Single regex rule row: validity dot + monospaced text field + level picker + delete button.
private struct PatternRow: View {
    @Binding var pattern: ChapterPattern
    let onDelete: () -> Void

    // IMPORTANT: Explicit @FocusState binding ensures the cursor appears immediately on first tap
    // when a TextField shares a Form row with other interactive controls.
    @FocusState private var fieldFocused: Bool

    private var validityColor: Color {
        if pattern.value.isEmpty { return .secondary.opacity(0.35) }
        let valid = (try? NSRegularExpression(pattern: pattern.value)) != nil
        return valid ? .green : .red
    }

    var body: some View {
        // IMPORTANT: Explicit alignment: .center prevents NSSegmentedControl from drifting
        // below the row midline when sharing an HStack with a TextField.
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(validityColor)
                .frame(width: 6, height: 6)

            // IMPORTANT: Empty first-argument + prompt: prevents Form (grouped style) from
            // rendering the label as fixed left-side text instead of placeholder text.
            TextField(
                "",
                text: $pattern.value,
                prompt: Text(String(localized: "setting.chapter_regex.placeholder"))
            )
            .font(.system(size: 12, design: .monospaced))
            .focused($fieldFocused)
            .frame(maxWidth: .infinity)

            // IMPORTANT: .labelsHidden() suppresses implicit label space that would push
            // the segmented control out of vertical alignment; .frame(width:) caps its width
            // without fixedSize() to avoid the control expanding the row unexpectedly.
            Picker(selection: $pattern.level) {
                Text("L1").tag(1)
                Text("L2").tag(2)
                Text("L3").tag(3)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            .help(String(localized: "setting.chapter_regex.level_help"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
