import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .checking:
                ProgressView("检查登录状态…")
                    .task { await session.restore() }
            case .loggedOut, .failed:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                BrowseView()
            }
            .tabItem {
                Label("网盘", systemImage: "externaldrive")
            }

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("媒体库", systemImage: "rectangle.stack")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(.yellow)
    }
}

#Preview {
    RootView()
        .environment(SessionStore())
}
