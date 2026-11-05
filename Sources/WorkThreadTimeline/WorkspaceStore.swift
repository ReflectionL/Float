import Foundation
import Combine

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var threads: [WorkThread]
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var saveError: String?
    let persistence: WorkspacePersistence
    let backups: WorkspaceBackups
    @Published private(set) var backupError: String?
    @Published var operationError: String?
    private var saveTask: Task<Void, Never>?
    private weak var undoManager: UndoManager?
    @Published private(set) var undoRevision = 0
    private(set) var restoredEventDraftID: UUID?

    func attachUndoManager(_ manager: UndoManager) {
        undoManager = manager
        manager.levelsOfUndo = 100
    }

    var visibleThreads: [WorkThread] { threads.filter { $0.status != .done } }
    var doneThreads: [WorkThread] {
        threads.filter { $0.status == .done }.sorted {
            ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
        }
    }

    init(url: URL = WorkspacePersistence.defaultURL, seedExamples: Bool = true) throws {
        persistence = try WorkspacePersistence(url: url)
        backups = WorkspaceBackups(directory: url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true))
        if let saved = try persistence.load() {
            var migrated = saved
            for index in migrated.indices { migrated[index].migrateLegacyChecklistToNote() }
            if migrated != saved {
                try backups.checkpoint(saved, kind: .beforeChange)
                try persistence.save(migrated)
            }
            threads = migrated
        } else {
            threads = seedExamples ? WorkThread.examples : []
            try persistence.save(threads)
        }
        checkpointAutomatically()
    }

    func thread(_ id: UUID) -> WorkThread? { threads.first { $0.id == id } }

    @discardableResult
    func createThread(title: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let thread = WorkThread(title: title, order: (threads.map(\.order).max() ?? -1) + 1)
        threads.append(thread)
        changed()
        return thread.id
    }

    func rename(_ id: UUID, to title: String) {
        guard let current = thread(id), current.title != title else { return }
        update(id) { $0.title = title }
    }

    func finishTitle(_ id: UUID) {
        guard let thread = thread(id) else { return }
        let title = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title != thread.title || title.isEmpty {
            rename(id, to: title.isEmpty ? "Untitled Thread" : title)
        }
    }

    func editNow(_ id: UUID, text: String) {
        // Native text fields can report their current text again on focus or
        // after commit. Those callbacks are not new edits.
        guard let current = thread(id), text != (current.nowDraft ?? current.now) else { return }
        update(id) { $0.nowDraft = text }
    }

    // One editing session becomes one transition, independent of keystrokes.
    func commitNow(_ id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }),
              let draft = threads[index].nowDraft else { return }
        let newValue = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldValue = threads[index].now.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = threads[index]
        if newValue != oldValue {
            if !oldValue.isEmpty {
                threads[index].timeline.append(TimelineEvent(text: threads[index].now, isPreviousNow: true))
            }
            threads[index].now = newValue
            threads[index].updatedAt = Date()
        }
        threads[index].nowDraft = nil
        Self.promoteParallelNow(&threads[index])
        changed()
        if newValue != oldValue {
            recordNowUndo(before, name: "Update Now", restoreDraft: false)
        }
    }

    func cancelNow(_ id: UUID) {
        guard thread(id)?.nowDraft != nil else { return }
        update(id) { $0.nowDraft = nil }
    }

    @discardableResult
    func completeNow(_ id: UUID) -> Bool {
        guard let current = thread(id) else { return false }
        let value = (current.nowDraft ?? current.now).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        // Finish a pending edit and archive the displayed NOW atomically. Keep
        // its prior committed value too, just as a normal NOW update would.
        update(id) {
            let old = $0.now.trimmingCharacters(in: .whitespacesAndNewlines)
            if $0.nowDraft != nil, old != value, !old.isEmpty {
                $0.timeline.append(TimelineEvent(text: $0.now, isPreviousNow: true))
            }
            $0.timeline.append(TimelineEvent(text: value, isPreviousNow: true))
            $0.now = ""
            $0.nowDraft = nil
            $0.nowWaiting = nil
            Self.promoteParallelNow(&$0)
        }
        recordNowUndo(current, name: "Complete Now", restoreDraft: true)
        return true
    }

    // MARK: Parallel NOW items

    /// Adds an empty parallel item and returns its ID, or nil when the main NOW
    /// is still empty and should be edited instead.
    func addParallelNow(_ id: UUID) -> UUID? {
        guard let current = thread(id) else { return nil }
        if !current.hasParallelNow,
           (current.nowDraft ?? current.now).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        // Reuse an untouched empty item instead of stacking blank rows.
        if let blank = current.parallelItems.first(where: {
            $0.displayed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) { return blank.id }
        let item = NowItem(text: "")
        update(id) { $0.parallelNow = $0.parallelItems + [item] }
        return item.id
    }

    func editNowItem(_ id: UUID, itemID: UUID, text: String) {
        guard let item = thread(id)?.parallelItems.first(where: { $0.id == itemID }),
              text != item.displayed else { return }
        updateItem(id, itemID) { $0.draft = text }
    }

    func commitNowItem(_ id: UUID, itemID: UUID) {
        guard let before = thread(id),
              let item = before.parallelItems.first(where: { $0.id == itemID }) else { return }
        let newValue = item.displayed.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldValue = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.draft != nil || newValue.isEmpty else { return }
        update(id) { thread in
            guard let index = thread.parallelItems.firstIndex(where: { $0.id == itemID }) else { return }
            if newValue != oldValue, !oldValue.isEmpty {
                thread.timeline.append(TimelineEvent(text: item.text, isPreviousNow: true))
            }
            if newValue.isEmpty {
                thread.parallelNow?.remove(at: index)
            } else {
                thread.parallelNow?[index].text = newValue
                thread.parallelNow?[index].draft = nil
            }
            Self.promoteParallelNow(&thread)
        }
        if newValue != oldValue {
            recordNowUndo(before, name: "Update Now", restoreDraft: false)
        }
    }

    func cancelNowItem(_ id: UUID, itemID: UUID) {
        guard let item = thread(id)?.parallelItems.first(where: { $0.id == itemID }) else { return }
        if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            update(id) {
                $0.parallelNow?.removeAll { $0.id == itemID }
                Self.promoteParallelNow(&$0)
            }
        } else if item.draft != nil {
            updateItem(id, itemID) { $0.draft = nil }
        }
    }

    @discardableResult
    func completeNowItem(_ id: UUID, itemID: UUID) -> Bool {
        guard let current = thread(id),
              let item = current.parallelItems.first(where: { $0.id == itemID }) else { return false }
        let value = item.displayed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        update(id) { thread in
            let old = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.draft != nil, old != value, !old.isEmpty {
                thread.timeline.append(TimelineEvent(text: item.text, isPreviousNow: true))
            }
            thread.timeline.append(TimelineEvent(text: value, isPreviousNow: true))
            thread.parallelNow?.removeAll { $0.id == itemID }
            Self.promoteParallelNow(&thread)
        }
        recordNowUndo(current, name: "Complete Now", restoreDraft: true)
        return true
    }

    /// Marks the main NOW (itemID nil) or a parallel item as waiting or active.
    func setNowWaiting(_ id: UUID, itemID: UUID?, waiting: Bool) {
        guard let current = thread(id) else { return }
        if let itemID {
            guard let item = current.parallelItems.first(where: { $0.id == itemID }),
                  item.waiting != waiting else { return }
            updateItem(id, itemID) { $0.waiting = waiting }
        } else {
            guard current.isNowWaiting != waiting else { return }
            update(id) { $0.nowWaiting = waiting ? true : nil }
        }
        recordUndo(waiting ? "Mark Waiting" : "Mark Active") {
            $0.setNowWaiting(id, itemID: itemID, waiting: !waiting)
        }
    }

    // MARK: Timeline corrections

    /// Moves a timeline record back to NOW: into the main NOW when it is
    /// empty, otherwise as a new parallel item.
    func returnEventToNow(_ id: UUID, eventID: UUID) {
        guard let before = thread(id),
              let event = before.timeline.first(where: { $0.id == eventID }) else { return }
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        update(id) { thread in
            thread.timeline.removeAll { $0.id == eventID }
            if (thread.nowDraft ?? thread.now).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                thread.now = text
                thread.nowDraft = nil
            } else {
                thread.parallelNow = thread.parallelItems + [NowItem(text: text)]
            }
            Self.promoteParallelNow(&thread)
        }
        let state = NowState(before)
        recordUndo("Return to Now") {
            $0.restoreNow(id, state: state, events: [event], affected: [eventID], name: "Return to Now")
        }
    }

    func deleteEvent(_ id: UUID, eventID: UUID) {
        guard let current = thread(id),
              let event = current.timeline.first(where: { $0.id == eventID }) else { return }
        update(id) { $0.timeline.removeAll { $0.id == eventID } }
        let state = NowState(current)
        recordUndo("Delete Timeline Event") {
            $0.restoreNow(id, state: state, events: [event], affected: [eventID], name: "Delete Timeline Event")
        }
    }

    /// Commits the main NOW and every parallel item being edited.
    func commitAllNow(_ id: UUID) {
        commitNow(id)
        for item in thread(id)?.parallelItems ?? [] where item.draft != nil {
            commitNowItem(id, itemID: item.id)
        }
    }

    /// Keeps the main NOW filled while parallel items remain, and stores no
    /// empty list.
    static func promoteParallelNow(_ thread: inout WorkThread) {
        if thread.nowDraft == nil, thread.now.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let index = thread.parallelItems.firstIndex(where: {
               !$0.displayed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            let item = thread.parallelItems[index]
            thread.parallelNow?.remove(at: index)
            thread.now = item.text
            thread.nowDraft = item.draft
            thread.nowWaiting = item.waiting ? true : nil
        }
        if thread.parallelNow?.isEmpty == true { thread.parallelNow = nil }
    }

    private func updateItem(_ id: UUID, _ itemID: UUID, change: (inout NowItem) -> Void) {
        update(id) { thread in
            guard let index = thread.parallelItems.firstIndex(where: { $0.id == itemID }) else { return }
            change(&thread.parallelNow![index])
        }
    }

    func editNext(_ id: UUID, text: String) {
        guard let current = thread(id), current.next != text else { return }
        update(id) { $0.next = text }
    }

    func setStatus(_ id: UUID, to status: ThreadStatus) {
        guard let thread = thread(id), thread.status != status else { return }
        commitAllNow(id)
        finishTitle(id)
        update(id) {
            $0.status = status
            $0.completedAt = status == .done ? Date() : nil
        }
    }

    @discardableResult
    func addEvent(_ id: UUID, text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, thread(id) != nil else { return false }
        let event = TimelineEvent(text: text)
        update(id) { $0.timeline.append(event) }
        let draft = thread(id)?.eventDraft
        recordUndo("Add Timeline Event") { $0.restoreEvent(id, eventID: event.id, event: nil, draft: draft) }
        return true
    }

    func editEventDraft(_ id: UUID, text: String) {
        guard let current = thread(id), text != (current.eventDraft ?? "") else { return }
        update(id) { $0.eventDraft = text.isEmpty ? nil : text }
    }

    @discardableResult
    func submitEventDraft(_ id: UUID) -> Bool {
        guard let value = thread(id)?.eventDraft?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return false }
        // Clear the draft and append the event in the same saved snapshot.
        let draft = thread(id)?.eventDraft
        let event = TimelineEvent(text: value)
        update(id) {
            $0.timeline.append(event)
            $0.eventDraft = nil
        }
        recordUndo("Add Timeline Event") { $0.restoreEvent(id, eventID: event.id, event: nil, draft: draft) }
        return true
    }

    func togglePin(_ id: UUID, eventID: UUID) {
        guard let event = thread(id)?.timeline.first(where: { $0.id == eventID }) else { return }
        setPinned(id, eventID: eventID, pinned: !event.pinned)
    }

    private func setPinned(_ id: UUID, eventID: UUID, pinned: Bool) {
        guard let old = thread(id)?.timeline.first(where: { $0.id == eventID })?.pinned,
              old != pinned else { return }
        update(id) { thread in
            if let index = thread.timeline.firstIndex(where: { $0.id == eventID }) {
                thread.timeline[index].pinned = pinned
            }
        }
        recordUndo("Mark Milestone") { $0.setPinned(id, eventID: eventID, pinned: old) }
    }

    // Dropping on the left/right half of a column places the source before/after it.
    func moveThread(_ id: UUID, to targetID: UUID, after: Bool) {
        guard id != targetID, let source = thread(id), let target = thread(targetID),
              source.status != .done, target.status != .done else { return }
        let order = threads.map(\.id)
        threads.removeAll { $0.id == id }
        let targetIndex = threads.firstIndex { $0.id == targetID }!
        threads.insert(source, at: targetIndex + (after ? 1 : 0))
        normalizeOrder()
        guard threads.map(\.id) != order else { return }
        changed()
        recordUndo("Move Thread") { $0.restoreOrder(order) }
    }

    func moveThread(_ id: UUID, offset: Int) {
        let visible = visibleThreads
        guard let index = visible.firstIndex(where: { $0.id == id }),
              visible.indices.contains(index + offset) else { return }
        moveThread(id, to: visible[index + offset].id, after: offset > 0)
    }

    func deleteThread(_ id: UUID) {
        guard thread(id) != nil else { return }
        guard checkpointBeforeChange() else { return }
        threads.removeAll { $0.id == id }
        normalizeOrder()
        changed()
    }

    @discardableResult
    func flush(commitDrafts: Bool = false) -> Bool {
        if commitDrafts {
            for id in threads.map(\.id) {
                commitAllNow(id)
                finishTitle(id)
            }
        }
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return saveError == nil }
        do {
            try persistence.save(threads)
            hasUnsavedChanges = false
            saveError = nil
            checkpointAutomatically()
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    enum ImportMode: String, CaseIterable {
        case addMissing = "Add new threads"
        case replace = "Replace workspace"
    }

    func export(to url: URL) throws {
        guard flush() else { throw OperationError.saveFailed(saveError ?? "Unknown storage error") }
        try WorkspaceArchive.encode(threads).write(to: url, options: .atomic)
    }

    func applyImport(_ archive: WorkspaceArchive, mode: ImportMode) throws {
        // Validate again at the mutation boundary, not only when previewing.
        let verified = try WorkspaceArchive.decode(JSONEncoder().encode(archive))
        let currentIDs = Set(threads.map(\.id))
        var imported = mode == .replace ? verified.orderedThreads
            : threads + verified.orderedThreads.filter { !currentIDs.contains($0.id) }
        if mode == .addMissing && imported.count == threads.count { return }
        for index in imported.indices {
            imported[index].order = index
            imported[index].migrateLegacyChecklistToNote()
        }
        guard checkpointBeforeChange() else {
            throw OperationError.saveFailed(operationError ?? "Could not create a recovery backup.")
        }
        // Persist before publishing, so a failed import leaves the UI intact.
        try persistence.save(imported)
        undoManager?.removeAllActions()
        threads = imported
        hasUnsavedChanges = false
        saveError = nil
        operationError = nil
        checkpointAutomatically()
    }

    @discardableResult
    private func checkpointBeforeChange() -> Bool {
        guard flush() else {
            operationError = saveError
            return false
        }
        do {
            try backups.checkpoint(threads, kind: .beforeChange)
            backupError = nil
            return true
        } catch {
            operationError = "The operation was cancelled because a recovery backup could not be created. " + error.localizedDescription
            backupError = error.localizedDescription
            return false
        }
    }

    func checkpointAutomatically() {
        do {
            try backups.checkpoint(threads, kind: .automatic)
            backupError = nil
        } catch { backupError = error.localizedDescription }
    }

    enum OperationError: LocalizedError {
        case saveFailed(String)
        var errorDescription: String? {
            switch self { case .saveFailed(let message): message }
        }
    }

    private func normalizeOrder() {
        for index in threads.indices { threads[index].order = index }
    }

    // Model actions share the window's standard undo manager with AppKit text
    // editing. Restore only the fields touched by an action, preserving notes,
    // statuses and unrelated history written after it.
    private func recordUndo(_ name: String, action: @escaping @MainActor (WorkspaceStore) -> Void) {
        guard let undoManager else { return }
        // Commit shortcuts finish text editing asynchronously. AppKit's open
        // event group can otherwise merge that commit with the next click.
        // Give each model action its own group, while letting AppKit continue
        // grouping keystrokes normally and managing inverse groups on undo.
        let newGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if newGroup {
            if undoManager.groupsByEvent && undoManager.groupingLevel == 1 {
                undoManager.endUndoGrouping()
            }
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { action(target) }
        }
        undoManager.setActionName(name)
        if newGroup { undoManager.endUndoGrouping() }
    }

    /// Every NOW field an action can touch: the main NOW and parallel items.
    private struct NowState {
        var now: String
        var draft: String?
        var waiting: Bool?
        var parallel: [NowItem]?

        init(_ thread: WorkThread, keepDrafts: Bool = true) {
            now = thread.now
            draft = keepDrafts ? thread.nowDraft : nil
            waiting = thread.nowWaiting
            parallel = thread.parallelNow.map { items in
                keepDrafts ? items : items.map { var item = $0; item.draft = nil; return item }
            }
        }

        func apply(to thread: inout WorkThread) {
            thread.now = now
            thread.nowDraft = draft
            thread.nowWaiting = waiting
            thread.parallelNow = parallel
        }
    }

    private func recordNowUndo(_ before: WorkThread, name: String, restoreDraft: Bool) {
        guard let after = thread(before.id) else { return }
        let oldIDs = Set(before.timeline.map(\.id))
        let affected = Set(after.timeline.map(\.id)).subtracting(oldIDs)
        let state = NowState(before, keepDrafts: restoreDraft)
        recordUndo(name) {
            $0.restoreNow(before.id, state: state, events: [], affected: affected, name: name)
        }
    }

    private func restoreNow(_ id: UUID, state: NowState, events: [TimelineEvent],
                            affected: Set<UUID>, name: String) {
        guard let current = thread(id) else { return }
        let existing = current.timeline.filter { affected.contains($0.id) }
        let currentState = NowState(current)
        recordUndo(name) {
            $0.restoreNow(id, state: currentState, events: existing, affected: affected, name: name)
        }
        update(id) {
            state.apply(to: &$0)
            $0.timeline.removeAll { affected.contains($0.id) }
            $0.timeline.append(contentsOf: events)
        }
        restoredEventDraftID = nil
        undoRevision += 1
    }

    private func restoreEvent(_ id: UUID, eventID: UUID, event: TimelineEvent?, draft: String?) {
        guard let current = thread(id) else { return }
        let existing = current.timeline.first { $0.id == eventID }
        recordUndo("Add Timeline Event") {
            $0.restoreEvent(id, eventID: eventID, event: existing, draft: current.eventDraft)
        }
        update(id) {
            $0.timeline.removeAll { $0.id == eventID }
            if let event { $0.timeline.append(event) }
            $0.eventDraft = draft
        }
        restoredEventDraftID = draft == nil ? nil : id
        undoRevision += 1
    }

    private func restoreOrder(_ order: [UUID]) {
        let current = threads.map(\.id)
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        threads = threads.enumerated().sorted {
            (positions[$0.element.id] ?? (order.count + $0.offset))
                < (positions[$1.element.id] ?? (order.count + $1.offset))
        }.map(\.element)
        normalizeOrder()
        changed()
        recordUndo("Move Thread") { $0.restoreOrder(current) }
        restoredEventDraftID = nil
        undoRevision += 1
    }

    private func update(_ id: UUID, change: (inout WorkThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        change(&threads[index])
        threads[index].updatedAt = Date()
        changed()
    }

    private func changed() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
