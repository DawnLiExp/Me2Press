import SwiftUI
import UniformTypeIdentifiers

struct CoverDropZone: View {
    @Binding var coverURL: URL?
    @State private var image: NSImage?
    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var showError = false
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        Button { showImporter = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 100, height: 140).clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.title2)
                        Text(String(localized: "label.custom_cover")).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "cover.choose"))
        .help(coverURL?.path ?? String(localized: "cover.choose"))
        .overlay(alignment: .topTrailing) {
            if coverURL != nil {
                Button { coverURL = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "cover.remove"))
                .accessibilityLabel(String(localized: "cover.remove"))
                .padding(4)
            }
        }
        .task(id: coverURL) { image = coverURL.flatMap { NSImage(contentsOf: $0) } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.jpeg, .png]) { result in
            switch result {
            case .success(let url): select(url)
            case .failure: showError = true
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            importTask?.cancel()
            importTask = Task { @MainActor in
                for provider in providers {
                    let url = try? await loadFileURL(from: provider)
                    guard !Task.isCancelled else { return }
                    if let url, isValid(url) { coverURL = url; return }
                }
                showError = true
            }
            return true
        }
        .onDisappear { importTask?.cancel() }
        .alert(String(localized: "cover.invalid"), isPresented: $showError) {
            Button(String(localized: "button.ok"), role: .cancel) {}
        }
    }

    private func isValid(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) && NSImage(contentsOf: url)?.isValid == true
    }

    private func select(_ url: URL) {
        if isValid(url) { coverURL = url }
        else { showError = true }
    }
}
