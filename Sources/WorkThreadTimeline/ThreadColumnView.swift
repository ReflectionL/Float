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
                .padding(.horizontal, AppTheme.Metrics.columnInset)
                .padding(.top, AppTheme.Spacing.small)
                .padding(.bottom, AppTheme.Spacing.extraLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        // The selected thread sits on a quiet neutral panel; the others stay on
        // the canvas and are separated by hairlines drawn by the workspace.
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .fill(selected ? AppTheme.Colors.selectedSurface : AppTheme.Colors.canvas)
        )
        .animation(AppTheme.Motion.fast, value: selected)
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
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.primaryText)
                    .editingUnderline(localEditor == .title(thread.id))
                    .focused($localEditor, equals: .title(thread.id))
                    .onSubmit { store.finishTitle(thread.id); editor.wrappedValue = nil }
                    .accessibilityLabel("\(thread.title), title")
                NativeThreadDragHandle(id: thread.id, title: thread.title, select: select,
                                       showsGlyph: hoveringHeader)
                    .frame(width: AppTheme.ControlHeight.compact, height: AppTheme.ControlHeight.compact)
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
                            .tracking(AppTheme.Typography.labelTracking)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                    } icon: {
                        Image(systemName: thread.status.symbol)
                            .renderingMode(.original)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? AppTheme.Colors.accentText : AppTheme.Colors.tertiaryText)
                    }
                    .font(AppTheme.Typography.captionMedium)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Change thread status")
            }
        }
        .padding(.horizontal, AppTheme.Metrics.columnInset)
        .padding(.top, AppTheme.Spacing.small)
        .padding(.bottom, AppTheme.Spacing.medium)
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
        } label: { IconButtonLabel(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Actions for \(thread.title)")
        .menuIndicator(.hidden)
        .frame(width: AppTheme.ControlHeight.compact, height: AppTheme.ControlHeight.compact)
    }

    private func contextEditor(
        _ label: String, text: Binding<String>,
        field: ThreadEditor, prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraSmall) {
            HStack(spacing: AppTheme.Spacing.extraSmall) {
                SectionLabel(text: label, emphasized: prominent)
                    .frame(minHeight: AppTheme.ControlHeight.compact)
                    .contentShape(Rectangle())
                    .onTapGesture { editor.wrappedValue = field }
                Spacer()
                if prominent && !(thread.nowDraft ?? thread.now).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        guard !EditingBoundary.isComposing, EditingBoundary.endEditing() else { return }
                        editor.wrappedValue = nil
                        // Let the native field editor finish its final binding
                        // callbacks before clearing the value it was editing.
                        DispatchQueue.main.async { store.completeNow(thread.id) }
                    } label: {
                        IconButtonLabel(systemName: "checkmark", color: AppTheme.Colors.secondaryText)
                    }
                    .buttonStyle(HoverFillButtonStyle())
                    .help("Complete NOW and move it to the timeline")
                    .accessibilityLabel("Complete NOW for \(thread.title)")
                }
            }
            TextField("", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(prominent ? AppTheme.Typography.now : AppTheme.Typography.note)
                .foregroundStyle(prominent ? AppTheme.Colors.primaryText : AppTheme.Colors.secondaryText)
                .lineSpacing(prominent ? AppTheme.Typography.nowLineSpacing : AppTheme.Typography.bodyLineSpacing)
                .lineLimit(1...12)
                .frame(height: text.wrappedValue.isEmpty && localEditor != field ? 8 : nil)
                .padding(.vertical, 3)
                .editingUnderline(localEditor == field)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.extraSmall) {
                SectionLabel(text: "Timeline")
                Spacer()
                Button {
                    guard !EditingBoundary.isComposing else { return }
                    editor.wrappedValue = .event(thread.id)
                } label: { IconButtonLabel(systemName: "plus") }
                    .buttonStyle(HoverFillButtonStyle())
                    .help("Write a timeline event (⇧⌘Return)")
                    .accessibilityLabel("Add event to \(thread.title)")
            }
            if editor.wrappedValue == .event(thread.id) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                    TextField("", text: $eventText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.primaryText)
                        .lineSpacing(AppTheme.Typography.bodyLineSpacing)
                        .lineLimit(1...5)
                        .padding(.vertical, 3)
                        .editingUnderline(localEditor == .event(thread.id))
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
                        Button(action: submitEvent) {
                            IconButtonLabel(systemName: "checkmark", color: AppTheme.Colors.accentText)
                        }
                            .buttonStyle(HoverFillButtonStyle())
                            .help("Submit event (⌘Return)")
                            .accessibilityLabel("Submit event to \(thread.title)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraSmall) {
            Text(event.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(AppTheme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.tertiaryText)
            Text(event.text)
                .font(event.pinned ? AppTheme.Typography.bodyMedium : AppTheme.Typography.body)
                .foregroundStyle(event.pinned ? AppTheme.Colors.primaryText : AppTheme.Colors.secondaryText)
                .lineSpacing(AppTheme.Typography.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button(action: togglePin) {
                Image(systemName: event.pinned ? "star.fill" : "star")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(event.pinned ? AppTheme.Colors.warning : AppTheme.Colors.tertiaryText)
                    .frame(width: AppTheme.ControlHeight.compact, height: 20)
            }
            .buttonStyle(HoverFillButtonStyle())
            .focused($pinFocused)
            .opacity(event.pinned || hovering || pinFocused ? 1 : 0)
            .animation(AppTheme.Motion.fast, value: hovering)
            .accessibilityHidden(false)
            .help(event.pinned ? "Unpin milestone" : "Pin as milestone")
            .accessibilityLabel(event.pinned ? "Unpin \(event.text)" : "Pin \(event.text)")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
