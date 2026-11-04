import SwiftUI
import AppKit

@MainActor
final class AppSession: ObservableObject {
    @Published var store: WorkspaceStore?
    @Published var error: String?

    init() { load() }
    func load() {
        do {
            #if UI_TEST
            let path = Bundle.main.object(forInfoDictionaryKey: "XlineQAStorePath") as? String
                ?? NSTemporaryDirectory() + "xline-ui-qa/workspace.store"
            store = try WorkspaceStore(url: URL(fileURLWithPath: path))
            #else
            store = try WorkspaceStore()
            #endif
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: WorkspaceStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard EditingBoundary.endEditing() else { return .terminateCancel }
        guard let store, !store.flush(commitDrafts: true) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Changes could not be saved"
        alert.informativeText = (store.saveError ?? "Unknown storage error") + "\nThe app will stay open so you can retry saving."
        alert.addButton(withTitle: "Keep Open")
        alert.runModal()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WorkThreadTimelineApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var updates = UpdateController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Float", id: "workspace") {
            Group {
                if let store = session.store {
                    WorkspaceView(store: store, updates: updates)
                        .onAppear { delegate.store = store }
                } else {
                    VStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(AppTheme.Colors.warning)
                        Text("Couldn’t open your workspace")
                            .font(AppTheme.Typography.display)
                            .foregroundStyle(AppTheme.Colors.primaryText)
                        Text(session.error ?? "Unknown storage error")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        Text("Your existing data has not been replaced.")
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.tertiaryText)
                        HStack(spacing: AppTheme.Spacing.small) {
                            Button("Open Data Folder") {
                                NSWorkspace.shared.open(WorkspacePersistence.defaultURL.deletingLastPathComponent())
                            }
                            Button("Retry") { session.load() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, AppTheme.Spacing.small)
                    }
                    .padding(AppTheme.Spacing.section)
                    .frame(maxWidth: 520)
                    .frame(
                        minWidth: AppTheme.Metrics.minimumWindowWidth,
                        maxWidth: .infinity,
                        minHeight: AppTheme.Metrics.minimumWindowHeight,
                        maxHeight: .infinity
                    )
                    .background(AppTheme.Colors.canvas)
                }
            }
            // System controls (prominent buttons, focus rings) use the app's
            // accent rather than the system one.
            .tint(AppTheme.Colors.accent)
            .task { await updates.checkAutomatically() }
        }
        .defaultSize(width: 1160, height: 740)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .commands {
            UpdateCommands(updates: updates)
            WorkspaceCommands()
        }

        Settings {
            SettingsView(updates: updates)
        }
    }
}

struct WorkspaceActions {
    let threadCount: Int
    let createThread: () -> Void
    let focusThread: (Int) -> Void
    let moveFocus: (Int) -> Void
    let commitEditing: () -> Void
    let addEvent: () -> Void
    let save: () -> Void
    let export: () -> Void
    let importJSON: () -> Void
    let restoreBackup: () -> Void
}

private struct WorkspaceActionsKey: FocusedValueKey {
    typealias Value = WorkspaceActions
}

extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Thread") { actions?.createThread() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Save Workspace") { actions?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(actions == nil)
            Divider()
            Button("Export JSON…") { actions?.export() }.disabled(actions == nil)
            Button("Import JSON…") { actions?.importJSON() }.disabled(actions == nil)
            Button("Restore from Backup…") { actions?.restoreBackup() }.disabled(actions == nil)
        }
        CommandMenu("Thread") {
            Button("Commit Current Edit") { actions?.commitEditing() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(actions?.threadCount ?? 0 == 0)
            Button("Add / Submit Timeline Event") { actions?.addEvent() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(actions?.threadCount ?? 0 == 0)
            Divider()
            Button("Previous Thread") { actions?.moveFocus(-1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(actions?.threadCount ?? 0 == 0)
            Button("Next Thread") { actions?.moveFocus(1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(actions?.threadCount ?? 0 == 0)
            Divider()
            ForEach(0..<9) { index in
                Button("Focus Thread \(index + 1)") { actions?.focusThread(index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(index >= (actions?.threadCount ?? 0))
            }
        }
    }
}
