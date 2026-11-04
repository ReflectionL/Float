import SwiftUI
import AppKit

enum ThreadEditor: Hashable {
    case title(UUID)
    case now(UUID)
    case next(UUID)
    case event(UUID)

    var threadID: UUID {
        switch self {
        case .title(let id), .now(let id), .next(let id), .event(let id): id
        }
    }
}

struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var updates: UpdateController
    @ViewState private var showingUpdate = false
    @ViewState private var selectedID: UUID?
    @ViewState private var creating = false
    @ViewState private var showingDone = false
    @ViewState private var deleting: UUID?
    @ViewState private var importCandidate: ImportCandidate?
    @ViewState private var editor: ThreadEditor?

    private var visible: [WorkThread] { store.visibleThreads }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if visible.isEmpty {
                    VStack(spacing: AppTheme.Spacing.medium) {
                        Text("A little space to pick things up.")
                            .font(AppTheme.Typography.display)
                            .foregroundStyle(AppTheme.Colors.primaryText)
                        Text("Create a thread for your next work context.")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                        Button("New Thread") { creating = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, AppTheme.Spacing.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: AppTheme.Metrics.columnSpacing) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, thread in
                                NativeThreadColumn(
                                    threadID: thread.id,
                                    canMove: { id in store.visibleThreads.contains { $0.id == id } },
                                    move: { id, after in store.moveThread(id, to: thread.id, after: after) },
                                    content: ThreadColumnView(
                                    thread: thread, index: index, selected: selectedID == thread.id,
                                    store: store, editor: $editor,
                                    eventText: Binding(get: { store.thread(thread.id)?.eventDraft ?? "" },
                                                       set: { store.editEventDraft(thread.id, text: $0) }),
                                    select: { selectedID = thread.id },
                                    delete: { deleting = thread.id },
                                    submitEvent: { submitEvent(thread.id) }
                                ))
                                .frame(width: AppTheme.Metrics.columnWidth)
                                .id(thread.id)
                            }
                        }
                        .padding(AppTheme.Metrics.workspaceInset)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.Colors.canvas)
            .toolbarBackground(AppTheme.Colors.canvas, for: .windowToolbar)
            .background(InitialWorkspaceFocus(configureUndo: store.attachUndoManager).frame(width: 0, height: 0))
            .frame(minWidth: AppTheme.Metrics.minimumWindowWidth, minHeight: AppTheme.Metrics.minimumWindowHeight)
            .toolbar {
                if let release = updates.availableRelease {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingUpdate = true } label: {
                            Label("Update to v" + release.version.description, systemImage: "arrow.down.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(AppTheme.Colors.accentText)
                        .help("Float v" + release.version.description + " is available")
                        .popover(isPresented: $showingUpdate) {
                            UpdatePopover(updates: updates)
                        }
                    }
                }
                if store.saveError != nil || store.backupError != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if let error = store.saveError {
                                Text("Changes could not be saved")
                                Text(error)
                                Button("Retry Save") { store.flush() }
                            }
                            if let error = store.backupError {
                                Text("Automatic backup failed")
                                Text(error)
                                Button("Retry Backup") { store.checkpointAutomatically() }
                            }
                        } label: {
                            Label("Storage needs attention", systemImage: "exclamationmark.triangle")
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(store.saveError != nil ? AppTheme.Colors.destructive : AppTheme.Colors.warning)
                        .help("Storage needs attention")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export JSON…") { exportWorkspace() }
                        Button("Import JSON…") { chooseImport() }
                        Divider()
                        Button("Restore from Backup…") { chooseImport(fromBackups: true) }
                        Button("Open Backups Folder") { NSWorkspace.shared.open(store.backups.directory) }
                    } label: { Label("Workspace Data", systemImage: "ellipsis") }
                    .labelStyle(.iconOnly)
                    .help("Import, export and backups")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingDone = true } label: {
                        Label("Done (\(store.doneThreads.count))", systemImage: "archivebox")
                    }
                    .labelStyle(.iconOnly)
                    .help("Done threads (\(store.doneThreads.count))")
                    .popover(isPresented: $showingDone) {
                        DoneThreadsView(store: store, restore: { id, status in
                            store.setStatus(id, to: status)
                            showingDone = false
                            selectedID = id
                            DispatchQueue.main.async { proxy.scrollTo(id) }
                        }, delete: { deleting = $0 })
                    }
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Label("New Thread", systemImage: "plus") }
                        .labelStyle(.iconOnly)
                        .help("New Thread (⌘N)")
                        .popover(isPresented: $creating) {
                            CreateThreadView { title in
                                guard let id = store.createThread(title: title) else { return }
                                creating = false
                                selectedID = id
                                DispatchQueue.main.async {
                                    proxy.scrollTo(id)
                                    editor = .now(id)
                                }
                            }
                        }
                }
            }
            .focusedSceneValue(\.workspaceActions, WorkspaceActions(
                threadCount: visible.count,
                createThread: { creating = true },
                focusThread: { focusThread(at: $0, proxy: proxy) },
                moveFocus: { offset in
                    guard !visible.isEmpty else { return }
                    let index = visible.firstIndex { $0.id == selectedID } ?? 0
                    focusThread(at: (index + offset + visible.count) % visible.count, proxy: proxy)
                },
                commitEditing: {
                    guard !EditingBoundary.isComposing else { return }
                    switch editor {
                    case .event(let id):
                        submitEvent(id)
                    case .now(let id):
                        guard EditingBoundary.endEditing() else { return }
                        editor = nil
                        DispatchQueue.main.async { store.commitNow(id) }
                    case .next, .title:
                        // NOTE already autosaves. End only the current edit;
                        // never redirect its submit shortcut to another field.
                        guard EditingBoundary.endEditing() else { return }
                        editor = nil
                        DispatchQueue.main.async { store.flush() }
                    case nil:
                        break
                    }
                },
                addEvent: {
                    guard !EditingBoundary.isComposing else { return }
                    guard let id = selectedID ?? visible.first?.id else { return }
                    if editor == .event(id) { submitEvent(id) }
                    else { selectedID = id; proxy.scrollTo(id); editor = .event(id) }
                },
                save: { store.flush(commitDrafts: !EditingBoundary.isComposing) },
                export: { exportWorkspace() },
                importJSON: { chooseImport() },
                restoreBackup: { chooseImport(fromBackups: true) }
            ))
            .onAppear { selectedID = visible.first?.id }
            .onChange(of: store.undoRevision) { _, _ in
                // Restore a submitted event as an editable draft. Other model
                // undo/redo actions finish the current edit without scrolling.
                guard EditingBoundary.endEditing() else { return }
                editor = store.restoredEventDraftID.map(ThreadEditor.event)
            }
            .onChange(of: editor) { old, value in
                if case .now(let id) = old { store.commitNow(id) }
                if case .title(let id) = old { store.finishTitle(id) }
                if let value { selectedID = value.threadID }
            }
            .onChange(of: visible.map(\.id)) { _, ids in
                if let id = selectedID, !ids.contains(id) {
                    editor = nil
                    selectedID = ids.first
                }
            }
            .onChange(of: selectedID) { _, id in
                // Clicking a header also ends editing in the previous column.
                if let editor, editor.threadID != id { self.editor = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                store.flush()
            }
            .sheet(item: $importCandidate) { candidate in
                ImportPreview(candidate: candidate, store: store) { importCandidate = nil }
            }
            .background {
                Color.clear
                    .alert("Workspace operation failed", isPresented: Binding(
                get: { store.operationError != nil }, set: { if !$0 { store.operationError = nil } }
            )) {
                Button("OK") { store.operationError = nil }
            } message: { Text(store.operationError ?? "") }
            }
            .alert("Delete thread permanently?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            )) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete", role: .destructive) {
                    let id = deleting
                    deleting = nil
                    if let id {
                        DispatchQueue.main.async { store.deleteThread(id) }
                    }
                }
            } message: {
                Text("\(deleting.flatMap { store.thread($0)?.title } ?? "This thread") and its timeline will be deleted. This cannot be undone.")
            }
        }
    }

    private func focusThread(at index: Int, proxy: ScrollViewProxy) {
        guard !EditingBoundary.isComposing, visible.indices.contains(index) else { return }
        let id = visible[index].id
        // Only explicit navigation reveals a column. Clicking/editing content
        // updates selection without repositioning the workspace.
        proxy.scrollTo(id)
        // Updating focus first prevents selectedID's observer from clearing it.
        editor = .now(id)
        selectedID = id
    }

    private func exportWorkspace() {
        do { try WorkspaceFilePanels.export(store) }
        catch { store.operationError = error.localizedDescription }
    }

    private func chooseImport(fromBackups: Bool = false) {
        do {
            importCandidate = try WorkspaceFilePanels.chooseImport(startingAt: fromBackups ? store.backups.directory : nil)
        } catch { store.operationError = error.localizedDescription }
    }

    private func submitEvent(_ id: UUID) {
        guard !EditingBoundary.isComposing, EditingBoundary.endEditing() else { return }
        editor = nil
        // Let the native editor's final callbacks finish before clearing the
        // draft, so its previous text cannot reappear after submission.
        DispatchQueue.main.async { store.submitEventDraft(id) }
    }
}

private struct CreateThreadView: View {
    let create: (String) -> Void
    @ViewState private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("New Thread")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.primaryText)
            TextField("Thread title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(AppTheme.Typography.body)
                .focused($focused).onSubmit { submit() }
            HStack {
                Text("Start with one resumable context.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.tertiaryText)
                Spacer()
                Button("Create") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.Spacing.extraLarge).frame(width: 380)
        .onAppear { focused = true }
    }

    private func submit() {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { create(title) }
    }
}

private struct DoneThreadsView: View {
    @ObservedObject var store: WorkspaceStore
    let restore: (UUID, ThreadStatus) -> Void
    let delete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            HStack(alignment: .firstTextBaseline) {
                Text("Done Threads")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.Colors.primaryText)
                Spacer()
                Text("\(store.doneThreads.count)")
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundStyle(AppTheme.Colors.tertiaryText)
            }
            if store.doneThreads.isEmpty {
                Text("Completed threads will appear here.")
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.secondaryText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                        ForEach(store.doneThreads) { thread in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                                HStack {
                                    Text(thread.title)
                                        .font(AppTheme.Typography.bodyMedium)
                                        .foregroundStyle(AppTheme.Colors.primaryText)
                                    Spacer()
                                    Menu {
                                        Button("Restore as ACTIVE") { restore(thread.id, .active) }
                                        Button("Restore as SLEEPING") { restore(thread.id, .sleeping) }
                                        Divider()
                                        Button("Delete Permanently…", role: .destructive) { delete(thread.id) }
                                    } label: { IconButtonLabel(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                }
                                if let date = thread.completedAt {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.tertiaryText)
                                }
                                if !thread.now.isEmpty {
                                    Text(thread.now)
                                        .font(AppTheme.Typography.callout)
                                        .foregroundStyle(AppTheme.Colors.secondaryText)
                                        .lineLimit(3)
                                }
                                if thread.eventDraft != nil {
                                    Text("Unsubmitted event draft saved")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.tertiaryText)
                                }
                                ForEach(thread.sortedTimeline.filter(\.pinned)) { event in
                                    Label {
                                        Text(event.text).foregroundStyle(AppTheme.Colors.secondaryText)
                                    } icon: {
                                        Image(systemName: "star.fill").foregroundStyle(AppTheme.Colors.warning)
                                    }
                                    .font(AppTheme.Typography.caption)
                                }
                                Button("Restore") { restore(thread.id, .active) }
                                    .controlSize(.small)
                                Divider().overlay(AppTheme.Colors.stroke)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(AppTheme.Spacing.extraLarge).frame(width: 400)
    }
}
