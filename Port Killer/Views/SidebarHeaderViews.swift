import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Port Killer")
                    .font(.system(size: 22, weight: .black, design: .default))
                    .tracking(-0.4)
                    .foregroundStyle(Color.pkText)
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    SidebarSectionButton(
                        title: section.title,
                        symbol: section.symbolName,
                        isActive: viewModel.selectedSection == section
                    ) {
                        viewModel.setSection(section)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    viewModel.quitApp()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Quit App")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuitButtonStyle())
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pkSidebar)
    }
}

struct SidebarSectionButton: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? Color.pkText : Color.pkMuted)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? Color.pkPrimary.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isActive ? Color.pkPrimary.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceHeaderBar: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedSection.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.pkText)
                Text(viewModel.selectedSection.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pkMuted)
            }

            Spacer(minLength: 12)

            SearchBar(text: $viewModel.searchText, placeholder: searchPlaceholder)
                .frame(maxWidth: 340)

            HeaderIconButton(systemName: viewModel.isAutoRefreshEnabled ? "arrow.triangle.2.circlepath" : "pause.circle") {
                viewModel.toggleAutoRefresh()
            }
            .help(viewModel.isAutoRefreshEnabled ? "Auto refresh enabled" : "Auto refresh paused")

            HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                viewModel.refresh()
            }
            .help("Refresh port list")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.pkSurface.opacity(0.72))
    }

    private var searchPlaceholder: String {
        switch viewModel.selectedSection {
        case .activePorts: return "Search ports, PIDs or processes..."
        case .favorites: return "Search pinned ports..."
        case .settings: return "Search settings..."
        }
    }
}

struct HeaderIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.pkPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.pkElevated.opacity(0.55))
                )
        }
        .buttonStyle(.plain)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pkMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .monospaced))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.pkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pkElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

struct WorkspaceSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                switch viewModel.selectedSection {
                case .activePorts:
                    ActivePortsDashboardView()
                case .favorites:
                    FavoritesSectionView()
                case .settings:
                    SettingsSectionView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 80)
        }
        .overlay(alignment: .bottom) {
            if viewModel.totalSelectedCount > 0 {
                BatchActionBarView()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
    }
}
