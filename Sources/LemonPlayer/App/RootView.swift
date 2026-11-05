import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-demoPlayer") {
            // UI 测试 / 截图用：直接进演示播放，不用登录
            NavigationStack {
                DemoPlayerView()
            }
        } else {
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
}

struct LibraryTabRoot: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            LibrarySplitView()
        } else {
            NavigationStack {
                LibraryView()
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

            LibraryTabRoot()
                .tabItem {
                    Label("媒体库", systemImage: "rectangle.stack")
                }

            NavigationStack {
                DownloadsView()
            }
            .tabItem {
                Label("下载", systemImage: "arrow.down.circle")
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