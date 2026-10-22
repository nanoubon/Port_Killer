import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "GENERAL", trailing: "PREFERENCES")

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start at Login")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.pkText)
                            Text("Automatically start Port Killer when you log in")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.pkMuted)
                        }

                        Spacer()

                        Button {
                            viewModel.toggleLaunchAtLogin()
                        } label: {
                            Image(systemName: viewModel.isLaunchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(viewModel.isLaunchAtLoginEnabled ? Color.pkPrimary : Color.pkMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    if let message = viewModel.launchAtLoginMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.pkWarning)
                    }
                    if viewModel.launchAtLoginStatus == .requiresApproval {
                        SecondaryActionButton(title: "Open Login Items Settings", symbol: "gearshape") {
                            viewModel.openLoginItemsSettings()
                        }
                    }
                }
            }

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "MONITORING", trailing: "REFRESH")

                    HStack {
                        Text("Auto refresh")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.pkText)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { viewModel.isAutoRefreshEnabled },
                            set: { viewModel.setAutoRefreshEnabled($0) }
                        ))
                        .labelsHidden()
                    }

                    VStack(spacing: 10) {
                        HStack {
                            Text("Refresh interval")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.pkText)
                            Spacer()
                            Text("\(Int(viewModel.refreshIntervalSeconds)) s")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.pkPrimary)
                        }

                        Slider(value: Binding(
                            get: { viewModel.refreshIntervalSeconds },
                            set: { viewModel.setRefreshIntervalSeconds($0) }
                        ), in: 3...60, step: 1)
                    }

                    SecondaryActionButton(title: "Refresh Now", symbol: "arrow.clockwise") {
                        viewModel.refresh()
                    }
                }
            }

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "ABOUT", trailing: "APP INFO")

                    HStack {
                        Text("Port Killer")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color.pkText)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Color.pkText)
            Text("Configure your Port Killer experience")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.pkMuted)
        }
    }
}
