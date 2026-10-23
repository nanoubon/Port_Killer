import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 2
    private static let listPadding: CGFloat = 5
    private static let maxListHeight: CGFloat = 384
    private static let minListHeight: CGFloat = 200

    var body: some View {
        let rows = viewModel.rows(matching: searchText)
        VStack(spacing: 0) {
            header
            if viewModel.hasLoadedLivePorts && viewModel.scanError == nil {
                PortSummaryBar(shown: rows.count, query: searchText, compact: true)
                    .padding(.top, -4)
            }
            Divider()
            list(rows)
            Divider()
            footer
        }
        .frame(width: 340)
        .killConfirmation(origin: .menuBar)
        // Real window state: MenuBarExtra(.window) content does not get onAppear/onDisappear per open.
        .background(WindowVisibilityReader(requireKey: true) { visible in
            viewModel.setSurface(PortViewModel.Surface.popover, visible: visible)
        })
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search port, process, PID", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search ports")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 24, minHeight: 24)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Clear search")
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(searchFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
            )

            Button { viewModel.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Refresh ports")
            .help("Rescan ports")
        }
        .padding(10)
    }

    @ViewBuilder
    private func list(_ rows: [PortRow]) -> some View {
        Group {
            if !viewModel.hasLoadedLivePorts {
                ProgressView("Scanning ports…")
                    .controlSize(.small)
            } else if let error = viewModel.scanError {
                ContentUnavailableView {
                    Label("Couldn't scan ports", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { viewModel.refresh() }
                }
            } else if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("No listening ports", systemImage: "network.slash")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Self.rowSpacing) {
                        ForEach(rows) { row in
                            MenuPortRow(row: row)
                                .frame(height: Self.rowHeight)
                        }
                    }
                    .padding(Self.listPadding)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: listHeight(rows))
    }

    private func listHeight(_ rows: [PortRow]) -> CGFloat {
        guard viewModel.hasLoadedLivePorts, viewModel.scanError == nil, !rows.isEmpty else { return Self.minListHeight }
        let content = CGFloat(rows.count) * (Self.rowHeight + Self.rowSpacing) - Self.rowSpacing + Self.listPadding * 2
        return min(max(content, Self.minListHeight), Self.maxListHeight)
    }

    private var footer: some View {
        HStack {
            Button {
                AppActivation.openMainWindow(openWindow)
            } label: {
                Label("Open Window", systemImage: "macwindow")
            }
            .keyboardShortcut("o")
            .help("Open the main window (⌘O)")

            Spacer()

            Button {
                AppActivation.openSettings(openSettings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .help("Open Settings (⌘,)")

            Button { viewModel.quitApp() } label: {
                Label("Quit", systemImage: "power")
            }
                .keyboardShortcut("q")
                .help("Quit Port Killer (⌘Q)")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct MenuPortRow: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let row: PortRow

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ProcessIconView(
                processName: row.processName,
                path: row.item.flatMap { ProcessIcon.executablePath(pid: $0.pid, processName: $0.processName) },
                size: 26,
                isRunning: row.isRunning
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(row.processName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 4) {
                    if let item = row.item {
                        let scope = AddressScope(item.addresses)
                        Image(systemName: scope.symbol)
                            .foregroundStyle(scope.color)
                            .help(scope.help)
                        Text("PID \(row.pid) · \(row.userText)")
                        if row.isDocker {
                            TagLabel("Docker")
                        }
                    } else {
                        Text("Not running")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)
            PortBadge(port: row.port, isRunning: row.isRunning)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(
            hovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .foregroundStyle(row.isRunning ? HierarchicalShapeStyle.primary : .secondary)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { PortActionsMenu(rows: [row], origin: .menuBar) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilitySummary)
        .portRowAccessibilityActions(row, origin: .menuBar)
    }

    @ViewBuilder
    private var trailing: some View {
        if let item = row.item, row.isReadOnly {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Read-only: owned by \(row.ownerLabel ?? "another user")")
            Button { viewModel.copySudoKillCommand(for: item, origin: .menuBar) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Copy sudo kill \(item.pid)")
            .help("Copy sudo kill \(item.pid)")
        } else if let item = row.item {
            Button {
                viewModel.killProcess(pid: item.pid, port: item, origin: .menuBar)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Kill \(row.processName) on port \(row.port)")
            .help("Kill \(row.processName) (port \(row.port))")
        } else {
            Button { viewModel.unpin(row.bookmark) } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Unpin \(row.processName) port \(row.port)")
            .help("Unpin")
        }
    }
}
