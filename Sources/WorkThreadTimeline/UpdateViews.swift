import SwiftUI

/// The Updates section of the Settings window.
struct UpdateSettingsSection: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        Section("Updates") {
            LabeledContent("Installed version") {
                Text(verbatim: updates.installedVersion.map { "v" + $0.description } ?? "Development build")
            }
            UpdateStatusRows(updates: updates)
            HStack {
                Button("Check for Updates") {
                    Task { await updates.checkForUpdates() }
                }
                .disabled(updates.isBusy)
                if !updates.canInstall {
                    Text("Updates install only in a released build.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.secondaryText)
                }
            }
        }
    }
}

/// What the updater is doing now, shared by Settings and the toolbar popover.
struct UpdateStatusRows: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            statusRow("Checking for updates…", showsProgress: true)
        case .upToDate:
            statusRow("Float is up to date.")
        case let .available(release):
            availableRows(release, isDownloading: false)
        case let .downloading(release):
            availableRows(release, isDownloading: true)
        case let .failed(message):
            Text(message)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func statusRow(_ text: String, showsProgress: Bool = false) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            if showsProgress { ProgressView().controlSize(.small) }
            Text(text)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.secondaryText)
        }
    }

    @ViewBuilder
    private func availableRows(_ release: AvailableRelease, isDownloading: Bool) -> some View {
        LabeledContent("Latest version", value: "v\(release.version)")
        if isDownloading {
            statusRow("Downloading and verifying v\(release.version)…", showsProgress: true)
        } else {
            HStack(spacing: AppTheme.Spacing.medium) {
                Button("Install and Restart") {
                    Task { await updates.installUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updates.canInstall)
                if let page = release.pageURL {
                    Link("Release Notes", destination: page)
                        .font(AppTheme.Typography.callout)
                }
            }
        }
    }
}

/// Shown in the toolbar once a newer release is found.
struct UpdatePopover: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Update Available")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.primaryText)
            Text("Your workspace is saved before Float restarts. Data, backups and settings stay where they are.")
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            UpdateStatusRows(updates: updates)
        }
        .padding(AppTheme.Spacing.extraLarge)
        .frame(width: 340, alignment: .leading)
    }
}

struct SettingsView: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        Form {
            LabeledContent("Application", value: AppIdentity.displayName)
            LabeledContent("Minimum system", value: "macOS 15")
            UpdateSettingsSection(updates: updates)
        }
        .formStyle(.grouped)
        .tint(AppTheme.Colors.accent)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct UpdateCommands: Commands {
    let updates: UpdateController
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                openSettings()
                Task { await updates.checkForUpdates() }
            }
        }
    }
}
