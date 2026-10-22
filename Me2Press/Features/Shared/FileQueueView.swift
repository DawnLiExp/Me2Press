import SwiftUI
import UniformTypeIdentifiers

struct FileQueueView: View {
    struct FileQueueDropSummary: Sendable {
        let addedCount: Int
        let duplicateCount: Int
        let contentRejectedCount: Int
        static let empty = FileQueueDropSummary(addedCount: 0, duplicateCount: 0, contentRejectedCount: 0)
    }

    let items: [URL]
    @Binding var isTargeted: Bool
    @Binding var isImporting: Bool
    let inputTypes: [UTType]
    let headerLabel: LocalizedStringResource
    let countLabel: LocalizedStringResource
    var headerTooltip: LocalizedStringResource?
    let rowIcon: String
    let rowTint: Color
    let emptyIcon: String
    let emptyTitle: LocalizedStringResource
    let emptySubtitle: LocalizedStringResource
    var contentRejectedMessage: LocalizedStringResource?
    let onClearAll: () -> Void
    let onRemove: (URL) -> Void
    let onReveal: (URL) -> Void
    let accepts: (URL) -> Bool
    let onDropped: ([URL]) async -> FileQueueDropSummary
    var onMove: ((IndexSet, Int) -> Void)?

    @State private var selection: Set<URL> = []
    @State private var showImporter = false
    @State private var feedback: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let headerTooltip {
                    Image(systemName: "questionmark.circle")
                        .help(Text(headerTooltip))
                        .accessibilityLabel(Text(headerTooltip))
                }
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label(String(localized: "queue.add"), systemImage: "plus")
                }
                .keyboardShortcut("o")
                .disabled(isImporting)
                if !items.isEmpty {
                    Button(String(localized: "button.clear_all"), action: onClearAll)
                        .disabled(isImporting)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if !items.isEmpty {
                (Text(verbatim: "\(items.count) ") + Text(countLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            ZStack {
                if items.isEmpty {
                    VStack {
                        DropHintView(icon: emptyIcon, title: emptyTitle, subtitle: emptySubtitle, isTargeted: isTargeted)
                        Button(String(localized: "queue.choose")) { showImporter = true }
                            .disabled(isImporting)
                            .padding(.bottom, 24)
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(items, id: \.self) { item in
                            FileRowView(url: item, icon: rowIcon, tint: rowTint,
                                        onRemove: { onRemove(item) }, onReveal: { onReveal(item) })
                                .tag(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        }
                        .onMove(perform: onMove)
                    }
                    .onDeleteCommand {
                        guard !isImporting else { return }
                        for item in selection { onRemove(item) }
                        selection.removeAll()
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .disabled(isImporting)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.02),
                        in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                                  style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [6, 4]))
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 24)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !isImporting else { return false }
                isImporting = true
                feedback = nil
                importTask = Task { @MainActor in
                    var urls: [URL] = []
                    var unreadable = 0
                    for provider in providers {
                        guard !Task.isCancelled else { return }
                        if let url = try? await loadFileURL(from: provider) { urls.append(url) }
                        else { unreadable += 1 }
                    }
                    await add(urls, unreadable: unreadable)
                }
                return true
            }

            if isImporting {
                ProgressView(String(localized: "queue.importing"))
                    .controlSize(.small)
                    .padding(.horizontal, 24)
            }
            if let feedback {
                HStack(alignment: .top) {
                    Text(feedback).font(.caption).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button { self.feedback = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .help(String(localized: "queue.dismiss"))
                    .accessibilityLabel(String(localized: "queue.dismiss"))
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: inputTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !isImporting else { return }
                isImporting = true
                feedback = nil
                importTask = Task { await add(urls) }
            case .failure(let error):
                feedback = error.localizedDescription
            }
        }
        .onChange(of: items) { _, current in selection.formIntersection(current) }
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            isImporting = false
        }
    }

    private func add(_ urls: [URL], unreadable: Int = 0) async {
        guard !Task.isCancelled else { return }
        let valid = urls.filter(accepts)
        let unsupported = urls.count - valid.count
        let summary = valid.isEmpty ? .empty : await onDropped(valid)
        guard !Task.isCancelled else { return }
        isImporting = false
        let rejected = unsupported + unreadable + summary.contentRejectedCount
        feedback = String(localized: "queue.summary \(summary.addedCount) \(summary.duplicateCount) \(rejected)")
        if unsupported > 0 { feedback? += "\n" + String(localized: "label.unsupported_drop") }
        if unreadable > 0 { feedback? += "\n" + String(localized: "queue.unreadable") }
        if summary.contentRejectedCount > 0, let contentRejectedMessage {
            feedback? += "\n" + String(localized: contentRejectedMessage)
        }
    }
}
