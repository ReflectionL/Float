import Foundation
import SwiftData
import Observation

// One atomic workspace snapshot is sufficient for a small personal workspace.
// This uses SwiftData's public PersistentModel API, without @Model: the local
// Command Line Tools do not ship the SwiftDataMacros compiler plugin.
// Views observe WorkspaceStore, not this storage-only record.
final class WorkspaceRecord: PersistentModel {
    var persistentBackingData: any BackingData<WorkspaceRecord> = WorkspaceRecord.createBackingData()

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [.init(name: "payload", keypath: \WorkspaceRecord.payload, defaultValue: Data())]
    }

    var payload: Data {
        get { getValue(forKey: \.payload) }
        set { setValue(forKey: \.payload, to: newValue) }
    }

    init(payload: Data) { self.payload = payload }
    init(backingData: any BackingData<WorkspaceRecord>) { persistentBackingData = backingData }
}

struct WorkspaceSnapshot: Codable {
    var version = 2
    var threads: [WorkThread]
}

@MainActor
final class WorkspacePersistence {
    let container: ModelContainer
    private let context: ModelContext
    private var record: WorkspaceRecord?
    let url: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkThreadTimeline", isDirectory: true)
            .appendingPathComponent("workspace.store")
    }

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        container = try ModelContainer(for: WorkspaceRecord.self,
                                       configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        guard records.count <= 1 else { throw StorageError.multipleWorkspaces }
        record = records.first
    }

    func load() throws -> [WorkThread]? {
        guard let record else { return nil }
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: record.payload)
        guard (1...2).contains(snapshot.version) else { throw StorageError.unsupportedVersion(snapshot.version) }
        guard Set(snapshot.threads.map(\.id)).count == snapshot.threads.count,
              snapshot.threads.allSatisfy({
                  Set($0.timeline.map(\.id)).count == $0.timeline.count
                    && Set($0.checklistItems.map(\.id)).count == $0.checklistItems.count
              }) else {
            throw StorageError.duplicateIDs
        }
        return snapshot.threads.sorted { $0.order < $1.order }
    }

    func save(_ threads: [WorkThread]) throws {
        let data = try JSONEncoder().encode(WorkspaceSnapshot(threads: threads))
        if let record {
            record.payload = data
        } else {
            let newRecord = WorkspaceRecord(payload: data)
            context.insert(newRecord)
            record = newRecord
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            record = try? context.fetch(FetchDescriptor<WorkspaceRecord>()).first
            throw error
        }
    }

    enum StorageError: LocalizedError {
        case multipleWorkspaces, duplicateIDs, unsupportedVersion(Int)
        var errorDescription: String? {
            switch self {
            case .multipleWorkspaces: "The store contains multiple workspace records. No data was overwritten."
            case .duplicateIDs: "The workspace contains duplicate identifiers. No data was overwritten."
            case .unsupportedVersion(let version): "Workspace version \(version) is not supported by this app."
            }
        }
    }
}
