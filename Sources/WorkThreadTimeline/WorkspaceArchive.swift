import Foundation

/// A self-describing JSON format. The explicit epoch preserves Date values
/// exactly, including sub-second ordering, across export/import.
struct WorkspaceArchive: Codable {
    var format = "work-thread-timeline"
    var version = 2
    var dateEncoding = "seconds-since-2001-01-01T00:00:00Z"
    var exportedAt = Date()
    var threads: [WorkThread]

    static let maximumFileSize = 20 * 1024 * 1024

    static func encode(_ threads: [WorkThread], at date: Date = Date()) throws -> Data {
        try validate(threads)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(WorkspaceArchive(exportedAt: date, threads: threads))
        guard data.count <= maximumFileSize else { throw ArchiveError.tooLarge }
        return data
    }

    static func read(from url: URL) throws -> WorkspaceArchive {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileSize else { throw ArchiveError.tooLarge }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func decode(_ data: Data) throws -> WorkspaceArchive {
        guard data.count <= maximumFileSize else { throw ArchiveError.tooLarge }
        let archive = try JSONDecoder().decode(WorkspaceArchive.self, from: data)
        guard archive.format == "work-thread-timeline", (1...2).contains(archive.version),
              archive.dateEncoding == "seconds-since-2001-01-01T00:00:00Z" else {
            throw ArchiveError.unsupportedFormat
        }
        try validate(archive.threads)
        return archive
    }

    static func validate(_ threads: [WorkThread]) throws {
        guard Set(threads.map(\.id)).count == threads.count,
              threads.allSatisfy({
                  Set($0.timeline.map(\.id)).count == $0.timeline.count
                    && Set($0.checklistItems.map(\.id)).count == $0.checklistItems.count
              }) else {
            throw ArchiveError.duplicateIDs
        }
        for thread in threads {
            let dates = [thread.createdAt, thread.updatedAt] + [thread.completedAt].compactMap { $0 }
                + thread.timeline.map(\.createdAt)
            guard dates.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else { throw ArchiveError.invalidDate }
        }
    }

    var orderedThreads: [WorkThread] {
        // Preserve file order for equal positions and normalize when importing.
        threads.enumerated().sorted {
            $0.element.order == $1.element.order ? $0.offset < $1.offset : $0.element.order < $1.element.order
        }.map(\.element)
    }

    enum ArchiveError: LocalizedError {
        case tooLarge, unsupportedFormat, duplicateIDs, invalidDate
        var errorDescription: String? {
            switch self {
            case .tooLarge: "This workspace exceeds the 20 MB import/export limit."
            case .unsupportedFormat: "This is not a supported Float JSON file."
            case .duplicateIDs: "The file contains duplicate thread, event or checklist identifiers. Nothing was imported."
            case .invalidDate: "The file contains an invalid timestamp. Nothing was imported."
            }
        }
    }
}

@MainActor
final class WorkspaceBackups {
    enum Kind: String { case automatic = "auto", beforeChange = "before" }
    let directory: URL
    static let automaticLimit = 7
    static let beforeChangeLimit = 3
    static let automaticInterval: TimeInterval = 15 * 60

    init(directory: URL) { self.directory = directory }

    @discardableResult
    func checkpoint(_ threads: [WorkThread], kind: Kind, at date: Date = Date()) throws -> URL? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let existing = try files(kind: kind)
        if kind == .automatic, let last = existing.first,
           date.timeIntervalSince(last.date) < Self.automaticInterval { return nil }
        let data = try WorkspaceArchive.encode(threads, at: date)
        let filename = "\(kind.rawValue)-\(Int(date.timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600, .modificationDate: date], ofItemAtPath: url.path)
        // Verify the new file before removing any older checkpoint.
        _ = try WorkspaceArchive.read(from: url)
        let limit = kind == .automatic ? Self.automaticLimit : Self.beforeChangeLimit
        for old in try files(kind: kind).dropFirst(limit) {
            try FileManager.default.removeItem(at: old.url)
        }
        return url
    }

    func files(kind: Kind) throws -> [(url: URL, date: Date)] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            .filter {
                let parts = $0.deletingPathExtension().lastPathComponent.split(separator: "-", maxSplits: 2)
                return $0.pathExtension == "json" && parts.count == 3 && parts[0] == kind.rawValue
                    && Int64(parts[1]) != nil && UUID(uuidString: String(parts[2])) != nil
            }
            .compactMap { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.date > $1.date }
    }
}
