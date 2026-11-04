import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportCandidate: Identifiable {
    let id = UUID()
    let filename: String
    let archive: WorkspaceArchive
}

@MainActor
enum WorkspaceFilePanels {
    static func chooseImport(startingAt directory: URL? = nil) throws -> ImportCandidate? {
        guard EditingBoundary.endEditing() else { return nil }
        let panel = NSOpenPanel()
        panel.title = "Import Workspace JSON"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return ImportCandidate(filename: url.lastPathComponent, archive: try WorkspaceArchive.read(from: url))
    }

    static func export(_ store: WorkspaceStore) throws {
        guard EditingBoundary.endEditing() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Workspace JSON"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Work-Thread-Timeline-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try store.export(to: url)
    }
}

struct ImportPreview: View {
    let candidate: ImportCandidate
    @ObservedObject var store: WorkspaceStore
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var mode = WorkspaceStore.ImportMode.addMissing
    @ViewState private var error: String?

    private var missingCount: Int {
        let ids = Set(store.threads.map(\.id))
        return candidate.archive.threads.filter { !ids.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Workspace").font(.headline)
            Text(candidate.filename).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text("\(candidate.archive.threads.count) threads · \(candidate.archive.threads.reduce(0) { $0 + $1.timeline.count }) events")
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(candidate.archive.orderedThreads) { thread in
                        HStack { Text(thread.title.isEmpty ? "Untitled Thread" : thread.title); Spacer(); Text(thread.status.rawValue).foregroundStyle(.secondary) }
                            .font(.caption)
                    }
                }
            }.frame(maxHeight: 130)
            Picker("Import mode", selection: $mode) {
                ForEach(WorkspaceStore.ImportMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if mode == .addMissing {
                Text("Add \(missingCount) new threads. Keep your current version of the \(candidate.archive.threads.count - missingCount) existing threads.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Replace all \(store.threads.count) current threads with this file. A recovery backup will be saved first.")
                    .font(.subheadline).foregroundStyle(.primary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .replace ? "Back Up & Replace" : "Import") {
                    do { try store.applyImport(candidate.archive, mode: mode); completed() }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(mode == .addMissing && missingCount == 0)
            }
        }
        .padding(24).frame(width: 480)
    }
}
