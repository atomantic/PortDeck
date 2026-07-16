import SwiftUI
import SwiftData

@Observable
final class Router {
    var selectedTab: AppTab = .sessions
    var sessionsPath = NavigationPath()
    var memoriesPath = NavigationPath()

    enum AppTab: String, CaseIterable {
        case sessions, memories, settings
    }

    func navigate(to route: any Hashable, tab: AppTab? = nil) {
        if let tab { selectedTab = tab }
        switch selectedTab {
        case .sessions: sessionsPath.append(route)
        case .memories: memoriesPath.append(route)
        case .settings: break
        }
    }

    func switchTab(_ tab: AppTab) {
        selectedTab = tab
    }

    func popToRoot(tab: AppTab? = nil) {
        switch tab ?? selectedTab {
        case .sessions: sessionsPath = NavigationPath()
        case .memories: memoriesPath = NavigationPath()
        case .settings: break
        }
    }
}
