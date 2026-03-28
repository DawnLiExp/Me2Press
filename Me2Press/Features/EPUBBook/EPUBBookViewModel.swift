//
//  EPUBBookViewModel.swift
//  Me2Press
//
//  Supports cooperative Task cancellation with process termination.
//

import AppKit
import SwiftUI

@MainActor
@Observable
class EPUBBookViewModel: ConversionViewModel {
    override func accepts(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "epub"
    }

    override func validateBeforeStart(appSettings: AppSettings, logger: LogManager) -> Bool {
        guard appSettings.isKindleGenReady, appSettings.kindlegenURL != nil else {
            logger.log(level: .error, "kindlegen is not configured for AZW3 conversion.")
            return false
        }
        return true
    }

    override func convertItem(_ url: URL, index: Int, appSettings: AppSettings, logger: LogManager) async throws {
        let log = AppLogger(category: "EPUBBook", uiLogger: logger)
        guard let kindlegenURL = appSettings.kindlegenURL else { return }
        let runner = KindleGenRunner(kindlegenPath: kindlegenURL)
        let name = url.deletingPathExtension().lastPathComponent
        let epubURL = url
        // IMPORTANT: uuid is written as the ASIN (EXTH 113) by DualMetaFix.
        // A unique per-conversion value ensures the Kindle library treats each output as a distinct item.
        let uuid = UUID().uuidString

        // ── Step 1: kindlegen (simulate) ──────────────────────
        let kgSim = progress.startSimulation(
            from: 0.0, to: 0.95,
            step: String(localized: "progress.kindlegen"), rate: 0.08
        )
        var t = CFAbsoluteTimeGetCurrent()
        let mobiPath = try await runner.convert(epubPath: epubURL)
        kgSim.cancel()
        progress.set(local: 0.95, step: String(localized: "progress.kindlegen"))

        logStep(name, step: "kindlegen", since: t, log: log)

        let outputFolder = epubURL.deletingLastPathComponent()
        let azw3Path = outputFolder.appendingPathComponent("\(name).azw3")
        try? FileManager.default.removeItem(at: azw3Path)
        try FileManager.default.moveItem(at: mobiPath, to: azw3Path)

        // ── Step 2: DualMetaFix ───────────────────────────────
        try Task.checkCancellation()
        progress.set(local: 0.95, step: String(localized: "progress.fixing_meta"))
        t = CFAbsoluteTimeGetCurrent()
        try await DualMetaFix.fixAsync(mobiPath: azw3Path, uuid: uuid)
        progress.set(local: 1.0, step: String(localized: "progress.fixing_meta"))
        logStep(name, step: "DualMetaFix", since: t, log: log)
    }
}
