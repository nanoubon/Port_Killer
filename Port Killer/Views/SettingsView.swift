import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    // TODO: confirm the real repository URL before release.
    private static let repositoryURL = URL(string: "https://github.com/nanodev/Port_Killer")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Port Killer")
                    .font(.title2.weight(.semibold))
                Text("Version \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        Form {
            Section {
                appHeader
            }

            Section("General") {
                Toggle(isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                )) {
                    Label { Text("Start at login") } icon: { SettingsIcon("power", color: .green) }
                }
                if let message = viewModel.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items…") { viewModel.openLoginItemsSettings() }
                }
            }

            Section("Refresh") {
                Toggle(isOn: Binding(
                    get: { viewModel.isAutoRefreshEnabled },
                    set: { viewModel.setAutoRefreshEnabled($0) }
                )) {
                    Label { Text("Auto refresh") } icon: { SettingsIcon("arrow.clockwise", color: .blue) }
                }
                Stepper(value: Binding(
                    get: { Int(viewModel.refreshIntervalSeconds) },
                    set: { viewModel.setRefreshIntervalSeconds(Double($0)) }
                ), in: 3...60) {
                    LabeledContent {
                        Text("\(Int(viewModel.refreshIntervalSeconds)) seconds")
                            .monospacedDigit()
                    } label: {
                        Label { Text("Interval") } icon: { SettingsIcon("timer", color: .orange) }
                    }
                }
                .disabled(!viewModel.isAutoRefreshEnabled)
                Text("Refreshes only while the popover or main window is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent {
                    Link(destination: Self.repositoryURL) {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                    }
                } label: {
                    Label { Text("Source code") } icon: { SettingsIcon("chevron.left.forwardslash.chevron.right", color: .gray) }
                }
                LabeledContent {
                    Text("MIT")
                } label: {
                    Label { Text("License") } icon: { SettingsIcon("doc.text", color: .gray) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowAccessor { window in AppActivation.register(window) })
        .onAppear { viewModel.refreshLaunchAtLoginStatus() }
        // Coming back from System Settings › Login Items: re-read the real status.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshLaunchAtLoginStatus()
        }
    }
}
