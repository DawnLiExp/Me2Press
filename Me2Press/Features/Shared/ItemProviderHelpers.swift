//
//  ItemProviderHelpers.swift
//  Me2Press
//
//  Shared helper for resolving NSItemProvider into file URLs.
//  Used by all three Tab drop zones.
//

import Foundation
import UniformTypeIdentifiers

/// Resolves a single `NSItemProvider` into a `URL`, or `nil` if the item is not a file URL.
///
/// `NSItemProvider.loadItem` returns the URL in different forms depending on the drag source:
/// some providers vend it as a raw `URL` object, others serialize it as `Data`.
/// Both branches are handled to cover system file drags and third-party app sources.
func loadFileURL(from provider: NSItemProvider) async throws -> URL? {
    try await withCheckedThrowingContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                continuation.resume(returning: url)
            } else if let url = item as? URL {
                continuation.resume(returning: url)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Returns a stable identity string for drag-and-drop deduplication.
///
/// The queue keeps the first dropped URL for display, but duplicate detection
/// must collapse symlink and path-normalization variations that point to the same
/// filesystem location.
func normalizedDropIdentity(for url: URL) -> String {
    url.standardizedFileURL
        .resolvingSymlinksInPath()
        .path
}
