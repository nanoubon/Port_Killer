import Combine
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    struct MainWindowRoute: Identifiable, Equatable {
        let id = UUID()
        let section: AppSection
        let selectedPortID: String?
    }

    @Published private(set) var pendingMainWindowRoute: MainWindowRoute?

    func showMainWindow(section: AppSection = .activePorts, selectedPortID: String? = nil) {
        pendingMainWindowRoute = MainWindowRoute(section: section, selectedPortID: selectedPortID)
    }

    func consumePendingMainWindowRoute() {
        pendingMainWindowRoute = nil
    }
}
