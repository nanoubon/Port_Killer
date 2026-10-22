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

    var body: some View {
        Form {
            Section("ทั่วไป") {
                Toggle("Start at login", isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLogin($0) }
                ))
                if let message = viewModel.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.launchAtLoginStatus == .requiresApproval {
                    Button("เปิด Login Items") { viewModel.openLoginItemsSettings() }
                }
            }

            Section("การรีเฟรช") {
                Toggle("รีเฟรชอัตโนมัติ", isOn: Binding(
                    get: { viewModel.isAutoRefreshEnabled },
                    set: { viewModel.setAutoRefreshEnabled($0) }
                ))
                Stepper(value: Binding(
                    get: { Int(viewModel.refreshIntervalSeconds) },
                    set: { viewModel.setRefreshIntervalSeconds(Double($0)) }
                ), in: 3...60) {
                    LabeledContent("ทุก", value: "\(Int(viewModel.refreshIntervalSeconds)) วินาที")
                        .monospacedDigit()
                }
                .disabled(!viewModel.isAutoRefreshEnabled)
                Text("รีเฟรชเฉพาะตอนที่ popover หรือหน้าต่างหลักเปิดอยู่")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("เกี่ยวกับ") {
                LabeledContent("Port Killer", value: "เวอร์ชัน \(version)")
                Link("GitHub", destination: Self.repositoryURL)
                Text("เผยแพร่ภายใต้ MIT License")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
