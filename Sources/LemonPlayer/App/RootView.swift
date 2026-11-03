import SwiftUI

struct RootView: View {
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
}
