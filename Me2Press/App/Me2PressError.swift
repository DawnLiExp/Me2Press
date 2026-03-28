//
//  Me2PressError.swift
//  Me2Press
//
//  Unified error types for the entire application.
//

import Foundation

enum Me2PressError: LocalizedError {
    // ── TXT parsing ──────────────────────────────────────
    case decodeFailed(encoding: String)
    case emptyFile(name: String)
    
    // ── EPUB build ───────────────────────────────────────
    case epubBuildFailed(reason: String)
    
    // ── Comic ─────────────────────────────────────────────
    case noImagesFound(folderName: String)
    
    // ── ZIP packaging ─────────────────────────────────────
    case zipFailed(exitCode: Int32)
    case zipRenameFailed(exitCode: Int32)
    
    // ── KindleGen ────────────────────────────────────────
    case epubTooLarge
    case kindlegenFailed(exitCode: Int32, output: String)
    
    // ── MOBI metadata ────────────────────────────────────
    case mobiInvalidFormat(reason: String)
    
    // ── Cover generation ─────────────────────────────────
    case coverContextFailed
    case coverImageFailed
    case coverEncodeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let enc): return String(localized: "error.decode_failed_enc \(enc)")
        case .emptyFile(let name): return String(localized: "error.empty_file_name \(name)")
        case .epubBuildFailed(let r): return String(localized: "error.epub_build \(r)")
        case .noImagesFound(let folder): return String(localized: "error.no_images \(folder)")
        case .zipFailed(let code): return String(localized: "error.zip_failed \(code)")
        case .zipRenameFailed(let code): return String(localized: "error.zip_rename \(code)")
        case .epubTooLarge: return String(localized: "error.epub_too_large")
        case .kindlegenFailed(let code, _): return String(localized: "error.kindlegen_failed \(code)")
        case .mobiInvalidFormat(let r): return String(localized: "error.mobi_format \(r)")
        case .coverContextFailed: return String(localized: "error.cover_context")
        case .coverImageFailed: return String(localized: "error.cover_image")
        case .coverEncodeFailed: return String(localized: "error.cover_encode")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .epubTooLarge: return String(localized: "error.recovery.epub_too_large")
        case .kindlegenFailed: return String(localized: "error.recovery.check_kindlegen")
        default: return nil
        }
    }
}
