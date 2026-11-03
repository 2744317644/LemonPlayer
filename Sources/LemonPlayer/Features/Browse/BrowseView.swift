import SwiftUI

struct BrowseView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section("光鸭云盘") {
                NavigationLink {
                    PlayerView(mediaTitle: "文件占位")
                } label: {
                    Label("我的视频（占位）", systemImage: "film")
                }
                Label("动漫（占位）", systemImage: "sparkles.tv")
            }

            Section {
                Text("已登录：目录 API（M2 后续）将在这里显示真实文件树。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("网盘")
    }
}

#Preview {
    NavigationStack { BrowseView() }
        .environment(SessionStore())
}
