//
//  Me2PressApp.swift
//  Me2Press
//

import AppKit
import SwiftUI

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Me2PressApp

@main
struct Me2PressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appSettings = AppSettings()
    @State private var logger = LogManager()

    init() {
        // Prevent macOS from merging windows into tabs — Me2Press is a single-window app.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appSettings)
                .environment(logger)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Me2Press") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Me2Press",
                            .version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                            .applicationVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                        ]
                    )
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appSettings)
        }
    }
}
