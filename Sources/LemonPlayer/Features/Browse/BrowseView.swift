import SwiftUI
import LemonCore

struct BrowseView: View {
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
                Text("M1 骨架：登录与目录 API 将在 M2 接入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("网盘")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("登录") {}
                    .disabled(true)
            }
        }
    }
}

#Preview {
    NavigationStack { BrowseView() }
}
