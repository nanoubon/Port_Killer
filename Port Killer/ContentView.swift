import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        WorkspaceShellView()
            .killConfirmation(origin: .mainWindow)
            .onAppear { viewModel.screenDidAppear() }
            .onDisappear { viewModel.screenDidDisappear() }
    }
}

struct WorkspaceShellView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        ZStack {
            WorkspaceBackground()

            HStack(spacing: 0) {
                WorkspaceSidebarView()
                    .frame(width: 248)

                Divider()
                    .overlay(Color.pkStroke.opacity(0.25))

                VStack(spacing: 0) {
                    WorkspaceHeaderBar()
                    Divider()
                        .overlay(Color.pkStroke.opacity(0.25))

                    WorkspaceSectionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct WorkspaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.pkBackground,
                    Color.pkBackground.opacity(0.96),
                    Color.pkSurface.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.pkPrimary.opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 680
            )

            RadialGradient(
                colors: [
                    Color.pkSecondary.opacity(0.08),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}
