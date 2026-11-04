import SwiftUI

struct ThreadColumnView: View {
    let thread: WorkThread
    let index: Int
    let selected: Bool
    @ObservedObject var store: WorkspaceStore
    let editor: Binding<ThreadEditor?>
    @FocusState private var localEditor: ThreadEditor?
    @ViewState private var hoveringHeader = false
    @Binding var eventText: String
    let select: () -> Void
    let delete: () -> Void
    let submitEvent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    contextEditor("Now", text: Binding(
                        get: {
                            let current = store.thread(thread.id)
                            return current?.nowDraft ?? current?.now ?? ""
                        },
                        set: { store.editNow(thread.id, text: $0) }
                    ), field: .now(thread.id), prominent: true)
                    contextEditor("Note", text: Binding(
                        get: { store.thread(thread.id)?.next ?? "" }, set: { store.editNext(thread.id, text: $0) }
                    ), field: .next(thread.id), prominent: false)
                    timeline
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { select() })
        .onAppear {
            if editor.wrappedValue?.threadID == thread.id { localEditor = editor.wrappedValue }
        }
        .onChange(of: editor.wrappedValue) { _, field in
            // The conditional event field must mount before requesting native
            // focus; focusing a missing field can fall back to the title.
            if field != .event(thread.id) {
                localEditor = field?.threadID == thread.id ? field : nil
            }
        }
        .onChange(of: localEditor) { _, field in
            if let field {
                if editor.wrappedValue != field { editor.wrappedValue = field }
            } else if editor.wrappedValue?.threadID == thread.id {
                editor.wrappedValue = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread \(index + 1): \(thread.title)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Thread title", text: Binding(get: { thread.title }, set: { store.rename(thread.id, to: $0) }))
                    .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.primary.opacity(localEditor == .title(thread.id) ? 0.12 : 0))
                            .frame(height: 1).allowsHitTesting(false)
                    }
                    .focused($localEditor, equals: .title(thread.id))
                    .onSubmit { store.finishTitle(thread.id); editor.wrappedValue = nil }
                    .accessibilityLabel("\(thread.title), title")
                NativeThreadDragHandle(id: thread.id, title: thread.title, select: select,
                                       showsGlyph: hoveringHeader)
                    .frame(width: 24, height: 24)
                actionsMenu
            }
            HStack {
                Menu {
                    ForEach(ThreadStatus.allCases, id: \.self) { status in
                        Button { store.setStatus(thread.id, to: status) } label: {
                            Label(status.rawValue, systemImage: status == thread.status ? "checkmark" : status.symbol)
                        }
                    }
                } label: {
                    Label {
                        Text(thread.status.rawValue)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: thread.status.symbol)
                            .renderingMode(.original)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.blue : Color.primary)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Change thread status")
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
        .contentShape(Rectangle())
        .onHover { hoveringHeader = $0 }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Rename") { editor.wrappedValue = .title(thread.id) }
            Button("Move Left") { store.moveThread(thread.id, offset: -1) }
                .disabled(index == 0)
            Button("Move Right") { store.moveThread(thread.id, offset: 1) }
                .disabled(index == store.visibleThreads.count - 1)
            Divider()
            Button("Mark Done") { store.setStatus(thread.id, to: .done) }
            Button("Delete Thread…", role: .destructive, action: delete)
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Actions for \(thread.title)")
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
    }

    private func contextEditor(
        _ label: String, text: Binding<String>,
        field: ThreadEditor, prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(prominent ? .primary : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { editor.wrappedValue = field }
                Spacer()
                if prominent && thread.nowDraft != nil {
                    Button("Update") {
                        guard EditingBoundary.endEditing() else { return }
                        store.commitNow(thread.id); editor.wrappedValue = nil
                    }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Commit NOW and keep the previous value in the timeline (⌘Return)")
                }
                if prominent && !(thread.nowDraft ?? thread.now).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        guard !EditingBoundary.isComposing, EditingBoundary.endEditing() else { return }
                        editor.wrappedValue = nil
                        // Let the native field editor finish its final binding
                        // callbacks before clearing the value it was editing.
                        DispatchQueue.main.async { store.completeNow(thread.id) }
                    } label: {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Complete NOW and move it to the timeline")
                    .accessibilityLabel("Complete NOW for \(thread.title)")
                }
            }
            TextField("", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: prominent ? 18 : 15, weight: prominent ? .medium : .regular))
                .foregroundStyle(prominent ? .primary : .secondary)
                .lineSpacing(4).lineLimit(1...12)
                .frame(height: text.wrappedValue.isEmpty && localEditor != field ? 8 : nil)
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.primary.opacity(localEditor == field ? 0.12 : 0))
                        .frame(height: 1).allowsHitTesting(false)
                }
                .focused($localEditor, equals: field)
                .onKeyPress(keys: [.return], phases: .down) { key in
                    guard key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                    return EditingBoundary.insertLineBreak(in: NSApp.keyWindow?.firstResponder) ? .handled : .ignored
                }
                .onExitCommand {
                    guard !EditingBoundary.isComposing else { return }
                    if prominent { store.cancelNow(thread.id) }
                    editor.wrappedValue = nil
                }
                .accessibilityLabel("\(thread.title), \(prominent ? "NOW" : "NOTE")")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    guard !EditingBoundary.isComposing else { return }
                    editor.wrappedValue = .event(thread.id)
                } label: { Image(systemName: "plus").font(.system(size: 12, weight: .medium)) }
                    .buttonStyle(.borderless)
                    .help("Write a timeline event (⇧⌘Return)")
                    .accessibilityLabel("Add event to \(thread.title)")
            }
            .foregroundStyle(.secondary)
            if editor.wrappedValue == .event(thread.id) {
                HStack(alignment: .top, spacing: 8) {
                    TextField("", text: $eventText, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...5)
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.primary.opacity(localEditor == .event(thread.id) ? 0.12 : 0))
                                .frame(height: 1).allowsHitTesting(false)
                        }
                        .focused($localEditor, equals: .event(thread.id))
                        .onAppear {
                            DispatchQueue.main.async {
                                if editor.wrappedValue == .event(thread.id) {
                                    localEditor = .event(thread.id)
                                }
                            }
                        }
                        .onKeyPress(keys: [.return], phases: .down) { key in
                            guard key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
                            return EditingBoundary.insertLineBreak(in: NSApp.keyWindow?.firstResponder) ? .handled : .ignored
                        }
                        .onExitCommand {
                            guard !EditingBoundary.isComposing, EditingBoundary.endEditing() else { return }
                            editor.wrappedValue = nil
                        }
                        .accessibilityLabel("\(thread.title), new timeline event")
                    if !eventText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: submitEvent) { Image(systemName: "checkmark") }
                            .buttonStyle(.borderless)
                            .help("Submit event (⌘Return)")
                            .accessibilityLabel("Submit event to \(thread.title)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(thread.sortedTimeline) { event in
                    TimelineEventRow(event: event) {
                        store.togglePin(thread.id, eventID: event.id)
                    }
                }
            }
        }
    }
}

private struct TimelineEventRow: View {
    let event: TimelineEvent
    let togglePin: () -> Void
    @ViewState private var hovering = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(event.text)
                .font(.system(size: 14, weight: event.pinned ? .medium : .regular))
                .foregroundStyle(event.pinned ? .primary : .secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button(action: togglePin) {
                Image(systemName: event.pinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(event.pinned ? Color.orange : Color.secondary)
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .focused($pinFocused)
            .opacity(event.pinned || hovering || pinFocused ? 1 : 0)
            .accessibilityHidden(false)
            .help(event.pinned ? "Unpin milestone" : "Pin as milestone")
            .accessibilityLabel(event.pinned ? "Unpin \(event.text)" : "Pin \(event.text)")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
