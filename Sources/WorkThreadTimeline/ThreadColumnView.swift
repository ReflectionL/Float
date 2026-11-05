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
                VStack(alignment: .leading, spacing: AppTheme.Metrics.sectionGap) {
                    if thread.hasParallelNow {
                        parallelNow
                    } else {
                        contextEditor("现在", text: mainNowText, field: .now(thread.id), prominent: true)
                    }
                    contextEditor("备注", text: Binding(
                        get: { store.thread(thread.id)?.next ?? "" }, set: { store.editNext(thread.id, text: $0) }
                    ), field: .next(thread.id), prominent: false)
                    timeline
                }
                .padding(.horizontal, AppTheme.Metrics.columnInset)
                .padding(.top, AppTheme.Spacing.extraSmall)
                .padding(.bottom, AppTheme.Spacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        // The selected thread is a sheet lifted off the canvas: a quiet fill,
        // a hairline edge and a soft shadow. The others stay on the canvas,
        // separated only by space.
        .background {
            let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
            shape
                .fill(selected ? AppTheme.Colors.selectedSurface : AppTheme.Colors.canvas)
                .overlay(shape.strokeBorder(selected ? AppTheme.Colors.stroke : .clear,
                                            lineWidth: AppTheme.Metrics.hairline))
                .shadow(color: .black.opacity(selected ? 0.05 : 0), radius: 4, y: 2)
        }
        .animation(AppTheme.Motion.fast, value: selected)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { select() })
        .onAppear {
            if editor.wrappedValue?.threadID == thread.id { localEditor = editor.wrappedValue }
        }
        .onChange(of: editor.wrappedValue) { _, field in
            // The conditional event field must mount before requesting native
            // focus; focusing a missing field can fall back to the title.
            if case .nowItem(let id, _) = field, id == thread.id {
                // A new parallel row mounts in this update; focus it after.
                DispatchQueue.main.async {
                    if editor.wrappedValue == field { localEditor = field }
                }
            } else if field != .event(thread.id) {
                localEditor = field?.threadID == thread.id ? field : nil
            }
        }
        .onChange(of: localEditor) { old, field in
            if let field {
                if editor.wrappedValue != field { editor.wrappedValue = field }
            } else if case .nowItem? = editor.wrappedValue, old != editor.wrappedValue {
                // Adding a parallel item switches NOW to the list layout, which
                // unmounts the field that had focus. Focus is on its way to the
                // new row, so this is not the end of editing.
            } else if editor.wrappedValue?.threadID == thread.id {
                editor.wrappedValue = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thread \(index + 1): \(thread.title)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraSmall) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.small) {
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
            // A coloured dot, the status, and when the thread was last touched.
            HStack(spacing: AppTheme.Spacing.extraSmall) {
                Menu {
                    ForEach(ThreadStatus.allCases, id: \.self) { status in
                        Button { store.setStatus(thread.id, to: status) } label: {
                            Label(status.displayName, systemImage: status == thread.status ? "checkmark" : status.symbol)
                        }
                    }
                } label: {
                    Label {
                        Text(thread.status.displayName)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .renderingMode(.original)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(thread.status.tint)
                            .font(.system(size: 6))
                    }
                    .font(AppTheme.Typography.caption)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Change thread status")
                Text("· 更新于 \(ShortDate.updated(thread.updatedAt))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppTheme.Metrics.columnInset)
        .padding(.top, AppTheme.Spacing.large)
        .padding(.bottom, AppTheme.Metrics.sectionGap)
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
                if prominent {
                    addNowButton
                    if !(thread.nowDraft ?? thread.now).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { complete(nil) } label: {
                            IconButtonLabel(systemName: "checkmark", color: AppTheme.Colors.secondaryText)
                        }
                        .buttonStyle(HoverFillButtonStyle())
                        .help("Complete NOW and move it to the timeline")
                        .accessibilityLabel("Complete NOW for \(thread.title)")
                    }
                }
            }
            textEditor(text: text, field: field,
                       font: prominent ? AppTheme.Typography.now : AppTheme.Typography.note,
                       color: prominent ? AppTheme.Colors.primaryText : AppTheme.Colors.secondaryText,
                       lineSpacing: prominent ? AppTheme.Typography.nowLineSpacing : AppTheme.Typography.bodyLineSpacing,
                       accessibility: prominent ? "NOW" : "NOTE") {
                if prominent { store.cancelNow(thread.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textEditor(
        text: Binding<String>, field: ThreadEditor, font: Font, color: Color,
        lineSpacing: CGFloat, accessibility: String, cancel: @escaping () -> Void
    ) -> some View {
        // Return submits; Shift-Return starts a new line. While an input
        // method is composing, Return stays with it.
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .lineLimit(1...12)
            .frame(height: text.wrappedValue.isEmpty && localEditor != field ? 8 : nil)
            .padding(.vertical, 3)
            .editingUnderline(localEditor == field)
            .focused($localEditor, equals: field)
            .onKeyPress(keys: [.return], phases: .down) { key in
                guard key.modifiers.intersection([.command, .control, .option]).isEmpty,
                      !EditingBoundary.isComposing else { return .ignored }
                if key.modifiers.contains(.shift) {
                    return EditingBoundary.insertLineBreak(in: NSApp.keyWindow?.firstResponder) ? .handled : .ignored
                }
                submit(field)
                return .handled
            }
            .onExitCommand {
                guard !EditingBoundary.isComposing else { return }
                cancel()
                editor.wrappedValue = nil
            }
            .onAppear {
                // A new parallel row mounts after its editor was requested.
                if case .nowItem = field, editor.wrappedValue == field {
                    DispatchQueue.main.async {
                        if editor.wrappedValue == field { localEditor = field }
                    }
                }
            }
            .accessibilityLabel("\(thread.title), \(accessibility)")
    }

    /// Ends editing and saves the field, like ⌘Return.
    private func submit(_ field: ThreadEditor) {
        guard EditingBoundary.endEditing() else { return }
        editor.wrappedValue = nil
        // Let the native field editor deliver its final text first.
        DispatchQueue.main.async {
            switch field {
            case .now(let id): store.commitNow(id)
            case .nowItem(let id, let itemID): store.commitNowItem(id, itemID: itemID)
            default: store.flush()
            }
        }
    }

    private var mainNowText: Binding<String> {
        Binding(
            get: {
                let current = store.thread(thread.id)
                return current?.nowDraft ?? current?.now ?? ""
            },
            set: { store.editNow(thread.id, text: $0) }
        )
    }

    private func itemText(_ itemID: UUID) -> Binding<String> {
        Binding(
            get: { store.thread(thread.id)?.parallelItems.first { $0.id == itemID }?.displayed ?? "" },
            set: { store.editNowItem(thread.id, itemID: itemID, text: $0) }
        )
    }

    private var addNowButton: some View {
        Button {
            guard !EditingBoundary.isComposing else { return }
            if let itemID = store.addParallelNow(thread.id) {
                editor.wrappedValue = .nowItem(thread.id, itemID)
            } else {
                editor.wrappedValue = .now(thread.id)
            }
        } label: { IconButtonLabel(systemName: "plus") }
            .buttonStyle(HoverFillButtonStyle())
            .help("Add a parallel NOW")
            .accessibilityLabel("Add parallel NOW to \(thread.title)")
    }

    /// Completes the main NOW (nil) or a parallel item and archives it.
    private func complete(_ itemID: UUID?) {
        guard !EditingBoundary.isComposing, EditingBoundary.endEditing() else { return }
        editor.wrappedValue = nil
        // Let the native field editor finish its final binding callbacks
        // before clearing the value it was editing.
        DispatchQueue.main.async {
            if let itemID { store.completeNowItem(thread.id, itemID: itemID) }
            else { store.completeNow(thread.id) }
        }
    }

    /// NOW with parallel items: equal rows, each with a circle that completes
    /// it. A single NOW keeps the larger layout above.
    private var parallelNow: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.extraSmall) {
            HStack(spacing: AppTheme.Spacing.extraSmall) {
                SectionLabel(text: "现在", emphasized: true)
                Text("\(thread.parallelItems.count + 1)")
                    .font(AppTheme.Typography.captionMedium)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Colors.tertiaryText)
                Spacer()
                addNowButton
            }
            .frame(minHeight: AppTheme.ControlHeight.compact)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                nowRow(text: mainNowText, field: .now(thread.id), itemID: nil,
                       waiting: thread.isNowWaiting) { store.cancelNow(thread.id) }
                ForEach(thread.parallelItems) { item in
                    nowRow(text: itemText(item.id), field: .nowItem(thread.id, item.id), itemID: item.id,
                           waiting: item.waiting) { store.cancelNowItem(thread.id, itemID: item.id) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nowRow(
        text: Binding<String>, field: ThreadEditor, itemID: UUID?, waiting: Bool,
        cancel: @escaping () -> Void
    ) -> some View {
        let hasText = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            NowCircle(waiting: waiting, enabled: hasText) { complete(itemID) }
                .padding(.top, 3)
                .accessibilityLabel("Complete \(text.wrappedValue)")
            textEditor(text: text, field: field, font: AppTheme.Typography.nowItem,
                       color: AppTheme.Colors.primaryText, lineSpacing: AppTheme.Typography.bodyLineSpacing,
                       accessibility: "NOW", cancel: cancel)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Complete") { complete(itemID) }.disabled(!hasText)
            Button(waiting ? "Mark Active" : "Mark Waiting") {
                store.setNowWaiting(thread.id, itemID: itemID, waiting: !waiting)
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack(spacing: AppTheme.Spacing.extraSmall) {
                SectionLabel(text: "时间线")
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
            // Newest first, grouped under a day heading (今天 / 昨天 / 11月3日).
            VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                ForEach(timelineDays, id: \.day) { group in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                        Text(group.day)
                            .font(AppTheme.Typography.captionMedium)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            ForEach(group.events) { event in
                                TimelineEventRow(event: event, togglePin: {
                                    store.togglePin(thread.id, eventID: event.id)
                                }, returnToNow: {
                                    guard EditingBoundary.endEditing() else { return }
                                    editor.wrappedValue = nil
                                    DispatchQueue.main.async { store.returnEventToNow(thread.id, eventID: event.id) }
                                }, delete: {
                                    store.deleteEvent(thread.id, eventID: event.id)
                                })
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, AppTheme.Spacing.large)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.Colors.stroke)
                .frame(height: AppTheme.Metrics.hairline)
                .accessibilityHidden(true)
        }
    }

    /// The timeline, newest first, split into consecutive runs of one day.
    private var timelineDays: [(day: String, events: [TimelineEvent])] {
        var groups: [(day: String, events: [TimelineEvent])] = []
        for event in thread.sortedTimeline {
            let day = ShortDate.day(event.createdAt)
            if groups.last?.day == day { groups[groups.count - 1].events.append(event) }
            else { groups.append((day, [event])) }
        }
        return groups
    }
}

private struct TimelineEventRow: View {
    let event: TimelineEvent
    let togglePin: () -> Void
    let returnToNow: () -> Void
    let delete: () -> Void
    @ViewState private var hovering = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.small) {
            Text(ShortDate.time(event.createdAt))
                .font(AppTheme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.Colors.tertiaryText)
                .frame(width: AppTheme.Metrics.timelineTimeWidth, alignment: .leading)
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
        .contextMenu {
            Button("Return to Now", action: returnToNow)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

/// The circle in front of a parallel NOW item. Click completes the item; a
/// dashed outline marks an item that is waiting.
private struct NowCircle: View {
    let waiting: Bool
    let enabled: Bool
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(hovering && enabled ? AppTheme.Colors.success : AppTheme.Colors.tertiaryText,
                              style: StrokeStyle(lineWidth: 1.5, dash: waiting ? [2.5, 2] : []))
                .frame(width: 14, height: 14)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .animation(AppTheme.Motion.fast, value: hovering)
        .help(waiting ? "Waiting · click to complete" : "Complete and move to the timeline")
    }
}
