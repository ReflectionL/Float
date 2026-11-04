import Foundation
import SwiftData

@main
struct Phase2Tests {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("usage: phase2-tests MODE STORE_URL") }
        let url = URL(fileURLWithPath: args[2])
        switch args[1] {
        case "unit": try unitTests(url)
        case "write": try writeFixture(url)
        case "read": try readFixture(url)
        case "verify": try verifyFixture(url)
        case "corrupt": try corruptStore(url)
        case "safety": try safetyTests(url)
        case "migration": try migrationTests(url)
        case "undo": try undoTests(url)
        default: fatalError("Unknown test mode")
        }
        print("PASS: \(args[1])")
    }

    @MainActor
    static func undoTests(_ url: URL) throws {
        let store = try WorkspaceStore(url: url, seedExamples: false)
        let manager = UndoManager()
        manager.groupsByEvent = false
        store.attachUndoManager(manager)
        func action(_ body: () -> Void) {
            manager.beginUndoGrouping()
            body()
            manager.endUndoGrouping()
        }
        let id = store.createThread(title: "Undo")!
        let other = store.createThread(title: "Other")!
        action { store.editNow(id, text: "Original"); store.commitNow(id) }
        manager.removeAllActions()
        action { store.editNow(id, text: "Pending\nsecond line"); precondition(store.completeNow(id)) }
        let archived = store.thread(id)!.timeline
        precondition(archived.map(\.text) == ["Original", "Pending\nsecond line"])
        store.editNext(id, text: "A note written after completion")
        manager.undo()
        precondition(store.thread(id)!.now == "Original")
        precondition(store.thread(id)!.nowDraft == "Pending\nsecond line")
        precondition(store.thread(id)!.timeline.isEmpty)
        precondition(store.thread(id)!.next == "A note written after completion")
        manager.redo()
        precondition(store.thread(id)!.now.isEmpty && store.thread(id)!.nowDraft == nil)
        precondition(store.thread(id)!.timeline == archived, "Redo retains event IDs, dates and order")

        let draft = " Event draft\nsecond line  "
        store.editEventDraft(id, text: draft)
        action { precondition(store.submitEventDraft(id)) }
        let submitted = store.thread(id)!.timeline.last!
        manager.undo()
        precondition(store.thread(id)!.eventDraft == draft)
        precondition(store.thread(id)!.timeline == archived)
        precondition(store.restoredEventDraftID == id)
        manager.redo()
        precondition(store.thread(id)!.eventDraft == nil)
        precondition(store.thread(id)!.timeline.last == submitted)
        precondition(store.restoredEventDraftID == nil)
        action { store.togglePin(id, eventID: submitted.id) }
        manager.undo()
        precondition(!store.thread(id)!.timeline.last!.pinned)
        manager.redo()
        precondition(store.thread(id)!.timeline.last!.pinned)

        action { store.moveThread(other, to: id, after: false) }
        store.editNext(other, text: "Keep this note through reorder undo")
        manager.undo()
        precondition(store.visibleThreads.map(\.id) == [id, other])
        precondition(store.thread(other)!.next == "Keep this note through reorder undo")
        manager.redo()
        precondition(store.visibleThreads.map(\.id) == [other, id])
        precondition(store.flush())
        let reopened = try WorkspaceStore(url: url)
        precondition(reopened.threads == store.threads)
        let snapshot = WorkspaceArchive(threads: store.threads)
        try store.applyImport(snapshot, mode: .replace)
        precondition(!manager.canUndo && !manager.canRedo, "Import invalidates actions from the prior workspace")

        manager.removeAllActions()
        action { store.editNow(id, text: "New Now"); store.commitNow(id) }
        manager.undo()
        precondition(store.thread(id)!.now.isEmpty && store.thread(id)!.nowDraft == nil)
        manager.redo()
        precondition(store.thread(id)!.now == "New Now")

        // Match AppKit's default event grouping: two actions in one run-loop
        // pass still need two separate undo steps.
        let automatic = UndoManager()
        store.attachUndoManager(automatic)
        store.editNow(id, text: "Updated Now")
        store.commitNow(id)
        precondition(store.completeNow(id))
        automatic.undo()
        precondition(store.thread(id)!.now == "Updated Now", "Completion must not undo the preceding update")
        automatic.undo()
        precondition(store.thread(id)!.now == "New Now")
        automatic.redo()
        precondition(store.thread(id)!.now == "Updated Now")
        automatic.redo()
        precondition(store.thread(id)!.now.isEmpty)
    }

    @MainActor
    static func migrationTests(_ url: URL) throws {
        let pending = ChecklistItem(text: "检查数据\n第二行")
        let completed = ChecklistItem(text: "已跑完实验", isCompleted: true)
        let original = [
            WorkThread(title: "Migration", next: "原备注\n保留换行  ",
                       checklist: [pending, completed, ChecklistItem(text: " \n ")]),
            WorkThread(title: "Archived", status: .done, now: "Finished", nowDraft: "draft",
                       eventDraft: "event draft", checklist: [completed],
                       timeline: [TimelineEvent(text: "Earlier NOW", isPreviousNow: true)], order: 1),
            WorkThread(title: "Empty legacy list", checklist: [], order: 2)
        ]
        let persistence = try WorkspacePersistence(url: url)
        try persistence.save(original)
        let store = try WorkspaceStore(url: url, seedExamples: false)
        let id = original[0].id
        precondition(store.thread(id)!.next == "原备注\n保留换行  \n\n○ 检查数据\n第二行\n✓ 已跑完实验")
        var expected = original
        expected[0].next = store.thread(id)!.next
        expected[1].next = "✓ 已跑完实验"
        for index in expected.indices { expected[index].checklist = nil }
        precondition(store.threads == expected, "Only NOTE and the consumed legacy field may change")
        let recovery = try WorkspaceArchive.read(from: store.backups.files(kind: .beforeChange)[0].url)
        precondition(recovery.threads == original, "Keep an exact pre-migration backup")
        let migratedReopen = try WorkspaceStore(url: url)
        precondition(migratedReopen.threads == expected, "Restart must not append items twice")

        // Old JSON is unchanged during preview; both import modes migrate it.
        let archive = try WorkspaceArchive.decode(WorkspaceArchive.encode(original))
        precondition(archive.threads == original)
        let target = try WorkspaceStore(url: url.deletingLastPathComponent().appendingPathComponent("migration-import.store"), seedExamples: false)
        try target.applyImport(archive, mode: .addMissing)
        precondition(target.threads == expected)
        try target.applyImport(archive, mode: .addMissing)
        precondition(target.threads == expected)
        target.editNext(id, text: "Edited note")
        try target.applyImport(archive, mode: .replace)
        precondition(target.threads == expected)
        let importReopen = try WorkspaceStore(url: target.persistence.url)
        precondition(importReopen.threads == expected)
        var duplicateThread = original[0]
        duplicateThread.checklist = [pending, pending]
        do {
            try target.applyImport(WorkspaceArchive(threads: [duplicateThread]), mode: .replace)
            fatalError("Duplicate checklist IDs accepted")
        } catch { }
        precondition(target.threads == expected)

        // A blocked recovery backup must leave the original legacy store intact.
        let blockedRoot = url.deletingLastPathComponent().appendingPathComponent("blocked-migration")
        let blockedURL = blockedRoot.appendingPathComponent("workspace.store")
        let blockedPersistence = try WorkspacePersistence(url: blockedURL)
        try blockedPersistence.save(original)
        try Data("not a directory".utf8).write(to: blockedRoot.appendingPathComponent("Backups"))
        do {
            _ = try WorkspaceStore(url: blockedURL)
            fatalError("Migration continued without its recovery backup")
        } catch { }
        let unchanged = try WorkspacePersistence(url: blockedURL).load()
        precondition(unchanged == original)

        precondition(!store.completeNow(id), "Empty NOW is a no-op")
        store.editNow(id, text: "任务一\n完成")
        store.commitNow(id)
        precondition(store.completeNow(id))
        precondition(!store.completeNow(id), "Repeated click cannot duplicate history")
        store.commitNow(id)
        precondition(store.thread(id)!.timeline.map(\.text) == ["任务一\n完成"])
        precondition(store.thread(id)!.now.isEmpty && store.thread(id)!.nowDraft == nil)
        store.editNow(id, text: "旧任务")
        store.commitNow(id)
        store.editNow(id, text: "当前草稿")
        precondition(store.completeNow(id))
        precondition(store.thread(id)!.timeline.map(\.text) == ["任务一\n完成", "旧任务", "当前草稿"])
        store.editNow(id, text: "首次直接完成")
        precondition(store.completeNow(id))
        precondition(store.thread(id)!.timeline.count == 4)
        precondition(store.thread(id)!.timeline.allSatisfy(\.isPreviousNow))
        store.editNow(id, text: " \n ")
        precondition(!store.completeNow(id))
        store.cancelNow(id)
        precondition(store.flush())
        let reopened = try WorkspaceStore(url: url)
        precondition(reopened.threads == store.threads)
        let exported = try WorkspaceArchive.decode(WorkspaceArchive.encode(store.threads))
        precondition(exported.version == 2 && exported.threads == store.threads)
    }

    @MainActor
    static func unitTests(_ url: URL) throws {
        let store = try WorkspaceStore(url: url, seedExamples: false)
        let scrolledViewport = CGRect(x: 800, y: 0, width: 368, height: 600)
        precondition(ThreadDragGeometry.scrollDelta(x: 820, visible: scrolledViewport) < 0)
        precondition(ThreadDragGeometry.scrollDelta(x: 984, visible: scrolledViewport) == 0)
        precondition(ThreadDragGeometry.scrollDelta(x: 1150, visible: scrolledViewport) > 0)
        precondition(!ThreadDragGeometry.insertAfter(x: 100, width: 368))
        precondition(ThreadDragGeometry.insertAfter(x: 268, width: 368))
        precondition(store.threads.isEmpty)
        precondition(store.createThread(title: " \n ") == nil)
        let a = store.createThread(title: "  AVSR  ")!
        let b = store.createThread(title: "DLLM")!
        let c = store.createThread(title: "Omni")!
        precondition(store.thread(a)!.title == "AVSR")
        precondition(store.thread(a)!.status == .active)
        store.editNow(a, text: "")
        precondition(store.thread(a)!.nowDraft == nil, "Focus alone must not create an empty draft")
        store.editNow(a, text: "Baseline ready")
        store.commitNow(a)
        store.editNow(a, text: "Baseline ready")
        precondition(store.thread(a)!.nowDraft == nil, "Replayed text-field callbacks must not reopen a committed edit")
        precondition(store.thread(a)!.timeline.isEmpty, "An empty previous NOW is not an event")
        store.editNow(a, text: "R")
        store.editNow(a, text: "Running")
        store.editNow(a, text: "Running calibration\n检查 +5 dB")
        precondition(store.thread(a)!.timeline.isEmpty, "Keystrokes must not become timeline events")
        precondition(store.flush())
        let restoredDraft = try WorkspaceStore(url: url)
        precondition(restoredDraft.thread(a)!.now == "Baseline ready")
        precondition(restoredDraft.thread(a)!.nowDraft == "Running calibration\n检查 +5 dB")
        store.commitNow(a)
        store.commitNow(a)
        precondition(store.thread(a)!.timeline.count == 1, "Commit must be idempotent")
        precondition(store.thread(a)!.timeline[0].text == "Baseline ready")
        precondition(store.thread(a)!.timeline[0].isPreviousNow)
        store.editNow(a, text: "  Running calibration\n检查 +5 dB  ")
        store.commitNow(a)
        precondition(store.thread(a)!.timeline.count == 1, "Whitespace-only changes must not add events")
        store.editNow(a, text: "discard this edit")
        store.cancelNow(a)
        precondition(store.thread(a)!.nowDraft == nil)
        precondition(store.thread(a)!.now.contains("Running calibration"))
        store.editNext(a, text: "Compute bootstrap CI")
        precondition(!store.addEvent(a, text: " \n "))
        precondition(store.addEvent(a, text: " +11.5 pAUC "))
        let note = store.thread(a)!.sortedTimeline[0]
        precondition(note.text == "+11.5 pAUC")
        store.togglePin(a, eventID: note.id)
        precondition(store.thread(a)!.sortedTimeline[0].pinned)
        store.togglePin(a, eventID: note.id)
        precondition(!store.thread(a)!.sortedTimeline[0].pinned)
        store.moveThread(c, to: a, after: false)
        precondition(store.visibleThreads.map(\.id) == [c, a, b])
        store.moveThread(c, to: b, after: true)
        precondition(store.visibleThreads.map(\.id) == [a, b, c])
        store.moveThread(c, offset: -1)
        precondition(store.visibleThreads.map(\.id) == [a, c, b])
        store.moveThread(a, offset: -1)
        precondition(store.visibleThreads.map(\.id) == [a, c, b], "Boundary moves must be no-ops")
        store.editNow(c, text: "Benchmark finished")
        store.setStatus(c, to: .done)
        precondition(store.visibleThreads.map(\.id) == [a, b])
        precondition(store.doneThreads.map(\.id) == [c])
        precondition(store.thread(c)!.now == "Benchmark finished")
        precondition(store.thread(c)!.completedAt != nil)
        store.setStatus(c, to: .sleeping)
        precondition(store.thread(c)!.completedAt == nil)
        precondition(store.visibleThreads.map(\.id) == [a, c, b])
        store.setStatus(b, to: .waiting)
        store.rename(a, to: " \n ")
        store.finishTitle(a)
        precondition(store.thread(a)!.title == "Untitled Thread")
        store.editNow(a, text: "Saved on quit")
        precondition(store.flush(commitDrafts: true))
        precondition(!store.hasUnsavedChanges && store.saveError == nil)
        let reopened = try WorkspaceStore(url: url)
        precondition(reopened.threads == store.threads, "All state must survive a new container")
        precondition(reopened.thread(a)!.nowDraft == nil)
        precondition(reopened.thread(a)!.now == "Saved on quit")
        for id in reopened.threads.map(\.id) { reopened.deleteThread(id) }
        precondition(reopened.flush())
        let empty = try WorkspaceStore(url: url, seedExamples: true)
        precondition(empty.threads.isEmpty, "An intentionally empty workspace must not be reseeded")
    }

    @MainActor
    static func writeFixture(_ url: URL) throws {
        let store = try WorkspaceStore(url: url)
        precondition(store.threads.count == 3)
        let id = store.createThread(title: "Cross-process test")!
        store.editNow(id, text: "Initial NOW")
        store.commitNow(id)
        store.editNow(id, text: "Uncommitted draft survives restart")
        store.editNext(id, text: "验证中文 + multiline\nNext action")
        store.editEventDraft(id, text: "尚未提交的事件\n跨进程恢复")
        store.addEvent(id, text: "Important discovery")
        store.togglePin(id, eventID: store.thread(id)!.timeline[0].id)
        store.moveThread(id, to: store.threads[0].id, after: false)
        store.setStatus(store.threads.last!.id, to: .done)
        precondition(store.flush())
        var legacy = store.threads
        legacy[0].checklist = [ChecklistItem(text: "跨进程已完成项", isCompleted: true),
                               ChecklistItem(text: "未完成的清单草稿")]
        try store.persistence.save(legacy)
    }

    @MainActor
    static func readFixture(_ url: URL) throws {
        let store = try WorkspaceStore(url: url)
        precondition(store.threads.count == 4, "Seed examples must only be added once")
        let first = store.threads[0]
        precondition(first.title == "Cross-process test")
        precondition(first.now == "Initial NOW")
        precondition(first.nowDraft == "Uncommitted draft survives restart")
        precondition(first.next == "验证中文 + multiline\nNext action\n\n✓ 跨进程已完成项\n○ 未完成的清单草稿")
        precondition(first.timeline[0].pinned)
        precondition(first.eventDraft == "尚未提交的事件\n跨进程恢复")
        precondition(first.checklist == nil)
        precondition(store.doneThreads.count == 1)
        store.commitNow(first.id)
        store.setStatus(store.doneThreads[0].id, to: .sleeping)
        precondition(store.flush())
    }

    @MainActor
    static func verifyFixture(_ url: URL) throws {
        let store = try WorkspaceStore(url: url)
        let first = store.threads[0]
        precondition(first.next == "验证中文 + multiline\nNext action\n\n✓ 跨进程已完成项\n○ 未完成的清单草稿")
        precondition(first.checklist == nil)
        precondition(first.now == "Uncommitted draft survives restart")
        precondition(first.nowDraft == nil)
        precondition(first.eventDraft == "尚未提交的事件\n跨进程恢复")
        precondition(store.submitEventDraft(first.id))
        precondition(!store.submitEventDraft(first.id), "Repeated submission cannot duplicate an event")
        precondition(store.thread(first.id)!.eventDraft == nil)
        precondition(store.thread(first.id)!.timeline.count == 3)
        precondition(store.flush())
        precondition(first.timeline.count == 2)
        precondition(first.sortedTimeline[0].text == "Initial NOW")
        precondition(first.timeline.first { $0.text == "Important discovery" }!.pinned)
        precondition(store.doneThreads.isEmpty)
        precondition(store.threads.last!.status == .sleeping)
    }

    @MainActor
    static func safetyTests(_ url: URL) throws {
        let store = try WorkspaceStore(url: url, seedExamples: false)
        let a = store.createThread(title: "原有线程")!
        store.editNow(a, text: "committed")
        store.commitNow(a)
        store.editNow(a, text: "NOW draft")
        store.editEventDraft(a, text: "event draft\n第二行")
        precondition(store.flush())
        let jsonURL = url.deletingLastPathComponent().appendingPathComponent("export.json")
        try store.export(to: jsonURL)
        let original = store.threads
        let archive = try WorkspaceArchive.read(from: jsonURL)
        precondition(archive.threads == original, "Export must preserve drafts, dates, IDs and order exactly")

        // Old v1 database snapshots have no eventDraft field.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceSnapshot(version: 1, threads: original))) as! [String: Any]
        var legacyThreads = legacy["threads"] as! [[String: Any]]
        legacyThreads[0].removeValue(forKey: "eventDraft")
        legacyThreads[0].removeValue(forKey: "checklist")
        legacy["threads"] = legacyThreads
        let decodedLegacy = try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decodedLegacy.threads[0].eventDraft == nil)
        precondition(decodedLegacy.threads[0].nowDraft == "NOW draft")
        precondition(decodedLegacy.threads[0].checklistItems.isEmpty)
        var legacyArchive = WorkspaceArchive(version: 1, threads: decodedLegacy.threads)
        let decodedOldArchive = try WorkspaceArchive.decode(JSONEncoder().encode(legacyArchive))
        precondition(decodedOldArchive.threads == decodedLegacy.threads)
        legacyArchive.version = 999
        do { _ = try WorkspaceArchive.decode(JSONEncoder().encode(legacyArchive)); fatalError("Unknown archive accepted") } catch { }

        let new = WorkThread(title: "导入线程", eventDraft: "Imported unfinished event", order: 42)
        var conflicting = original[0]
        conflicting.title = "Do not overwrite the current title during merge"
        let incoming = WorkspaceArchive(threads: [conflicting, new])
        // Decoding/previewing is read-only.
        _ = try WorkspaceArchive.decode(JSONEncoder().encode(incoming))
        precondition(store.threads == original)
        try store.applyImport(incoming, mode: .addMissing)
        precondition(store.threads.count == 2)
        precondition(store.thread(a)!.title == "原有线程")
        precondition(store.thread(new.id)!.eventDraft == "Imported unfinished event")
        try store.applyImport(incoming, mode: .addMissing)
        precondition(store.threads.count == 2, "Repeated merge must not create duplicates")
        let beforeReplace = store.threads
        try store.applyImport(archive, mode: .replace)
        precondition(store.threads == original)
        let checkpoints = try store.backups.files(kind: .beforeChange)
        let savedBeforeReplace = try WorkspaceArchive.read(from: checkpoints[0].url)
        precondition(savedBeforeReplace.threads == beforeReplace)
        let reopened = try WorkspaceStore(url: url)
        precondition(reopened.threads == original)

        // Corrupt and conflicting import payloads are rejected before mutation.
        let duplicates = WorkspaceArchive(threads: [original[0], original[0]])
        do { try store.applyImport(duplicates, mode: .replace); fatalError("duplicate import accepted") } catch { }
        var unsupported = archive
        unsupported.version = 999
        do { try store.applyImport(unsupported, mode: .replace); fatalError("unknown import accepted") } catch { }
        precondition(store.threads == original)
        store.deleteThread(a)
        precondition(store.threads.isEmpty)
        let deletionBackup = try store.backups.files(kind: .beforeChange).first!
        let recoverable = try WorkspaceArchive.read(from: deletionBackup.url)
        precondition(recoverable.threads == original)
        try store.applyImport(recoverable, mode: .replace)
        precondition(store.threads == original)

        // Retention is bounded, throttled, and never removes unrelated files.
        let backupDirectory = url.deletingLastPathComponent().appendingPathComponent("retention")
        let backups = WorkspaceBackups(directory: backupDirectory)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        try backups.checkpoint(original, kind: .automatic, at: base)
        let skipped = try backups.checkpoint(original, kind: .automatic, at: base.addingTimeInterval(1))
        precondition(skipped == nil)
        let unrelated = backupDirectory.appendingPathComponent("auto-user-note.json")
        try Data("keep me".utf8).write(to: unrelated)
        for index in 1...10 {
            try backups.checkpoint(original, kind: .automatic, at: base.addingTimeInterval(Double(index) * 901))
            try backups.checkpoint(original, kind: .beforeChange, at: base.addingTimeInterval(Double(index) * 901))
        }
        let autoFiles = try backups.files(kind: .automatic)
        let beforeFiles = try backups.files(kind: .beforeChange)
        precondition(autoFiles.count == WorkspaceBackups.automaticLimit)
        precondition(beforeFiles.count == WorkspaceBackups.beforeChangeLimit)
        precondition(FileManager.default.fileExists(atPath: unrelated.path))
        for file in autoFiles + beforeFiles {
            let decoded = try WorkspaceArchive.read(from: file.url)
            precondition(decoded.threads == original)
        }

        // A failed backup must not silently permit destructive replacement/deletion.
        let blockedRoot = url.deletingLastPathComponent().appendingPathComponent("blocked-backups")
        try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: blockedRoot.appendingPathComponent("Backups"))
        let blocked = try WorkspaceStore(url: blockedRoot.appendingPathComponent("workspace.store"), seedExamples: false)
        precondition(blocked.backupError != nil)
        let keep = blocked.createThread(title: "Must survive")!
        precondition(blocked.flush(), "Primary saves remain available even if automatic backups fail")
        do { try blocked.applyImport(archive, mode: .replace); fatalError("destructive import without backup") } catch { }
        blocked.deleteThread(keep)
        precondition(blocked.thread(keep) != nil)
        let diskAfterFailure = try WorkspaceStore(url: blockedRoot.appendingPathComponent("workspace.store"))
        precondition(diskAfterFailure.thread(keep) != nil)
    }

    @MainActor
    static func corruptStore(_ url: URL) throws {
        let persistence = try WorkspacePersistence(url: url)
        try persistence.save([])
        let context = ModelContext(persistence.container)
        let record = try context.fetch(FetchDescriptor<WorkspaceRecord>()).first!
        let invalid = Data("not valid workspace data".utf8)
        record.payload = invalid
        try context.save()
        do {
            _ = try WorkspaceStore(url: url)
            fatalError("Corrupted data must fail visibly instead of silently creating examples")
        } catch { }
        let verification = try WorkspacePersistence(url: url)
        let verificationContext = ModelContext(verification.container)
        let stillInvalid = try verificationContext.fetch(FetchDescriptor<WorkspaceRecord>()).first!
        precondition(stillInvalid.payload == invalid, "Corrupted data must not be overwritten")
        record.payload = try JSONEncoder().encode(WorkspaceSnapshot(version: 999, threads: []))
        try context.save()
        do {
            _ = try WorkspaceStore(url: url)
            fatalError("Unknown schema versions must fail without overwriting the store")
        } catch { }
    }
}
