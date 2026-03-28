//
//  SidebarView.swift
//  Me2Press
//
//  Custom sidebar: branding, KindleGen status, tab navigation, log toggle.
//

import SwiftUI

// MARK: - AppTab

enum AppTab: String, CaseIterable, Identifiable {
    case comic = "tab.comic"
    case textbook = "tab.textbook"
    case epubbook = "tab.epubbook"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .textbook: return "books.vertical"
        case .comic: return "photo.on.rectangle.angled"
        case .epubbook: return "arrow.trianglehead.2.clockwise.rotate.90.page.on.clipboard"
        }
    }

    var title: String {
        switch self {
        case .textbook: return String(localized: "tab.textbook")
        case .comic: return String(localized: "tab.comic")
        case .epubbook: return String(localized: "tab.epubbook")
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @Binding var showLog: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Traffic-light spacer (hiddenTitleBar)

            // Reserve space for the floating window controls (⬤ ⬤ ⬤).
            Color.clear
                .frame(height: 40)
                .background(WindowDragArea())

            // MARK: App branding

            VStack(spacing: 6) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                Text("Me2Press")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("v\(appVersion)  Build \(appBuild)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(WindowDragArea())

            // MARK: KindleGen status

            Button {
                openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: settings.isKindleGenReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.isKindleGenReady ? .green : .orange)
                        .symbolEffect(.pulse, isActive: !settings.isKindleGenReady)
                        .font(.system(size: 12, weight: .bold))

                    Text(settings.isKindleGenReady ? String(localized: "status.kindlegen.ready") : String(localized: "status.kindlegen.missing"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)

            // MARK: Tab navigation

            VStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    SidebarTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // MARK: Log panel toggle

            VStack(spacing: 0) {
                Divider()
                    .opacity(0.5)

                Toggle(isOn: $showLog.animation(.spring(duration: 0.3))) {
                    Label(String(localized: "label.show_logs"), systemImage: "terminal")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - SidebarTabButton

private struct SidebarTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle()) // Expand hit area to the whole button
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.1), lineWidth: 0.5)
                    }
                }
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}
