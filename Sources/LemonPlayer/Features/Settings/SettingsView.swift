import SwiftUI
import LemonCore
import LemonDownloads
import LemonPersistence
import LemonSubtitle

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var downloadedBytes: Int64 = 0
    @State private var completedCount = 0
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section("账号") {
                switch session.state {
                case .loggedIn(let subject):
                    LabeledContent("光鸭云盘", value: subject)
                default:
                    LabeledContent("光鸭云盘", value: "未登录")
                }
                LabeledContent("Bangumi", value: "公开接口（无需登录）")

                Button("退出登录", role: .destructive) {
                    Task { await session.logout() }
                }
            }

            Section("存储") {
                LabeledContent("已下载", value: "\(completedCount) 个 · \(Formatters.fileSize(downloadedBytes))")
                Button("清理全部下载", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(completedCount == 0)
            }

            Section("播放与字幕") {
                NavigationLink("字幕样式") {
                    SubtitleStyleSettingsPreview()
                }
                Text("字幕样式在播放页的字幕按钮中实时调整；这里查看当前默认值。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: LemonCore.version)
                LabeledContent("构建", value: LemonCore.build)
                NavigationLink("诊断日志") {
                    DiagnosticsView()
                }
                NavigationLink("开源许可与免责声明") {
                    LicenseView()
                }
            }
        }
        .navigationTitle("设置")
        .task { await refreshStorage() }
        .alert("确认清理全部下载？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task {
                    await DownloadManager.shared.removeAll()
                    await refreshStorage()
                }
            }
        } message: {
            Text("已下载的视频文件会被删除，无法恢复。")
        }
    }

    private func refreshStorage() async {
        downloadedBytes = await DownloadManager.shared.totalDownloadedBytes()
        completedCount = await DownloadManager.shared.completedCount()
    }
}

/// 只读展示当前字幕样式默认值（编辑入口在播放页）。
private struct SubtitleStyleSettingsPreview: View {
    @State private var style: SubtitleStyle = .default

    var body: some View {
        Form {
            LabeledContent("字号", value: "\(Int(style.fontSize))")
            LabeledContent("文字颜色", value: style.textColorHex)
            LabeledContent("描边宽度", value: String(format: "%.1f", style.outlineWidth))
            LabeledContent("背景不透明度", value: String(format: "%.2f", style.backgroundOpacity))
            LabeledContent("底部边距", value: "\(Int(style.bottomInset))")
        }
        .navigationTitle("字幕样式")
        .task {
            style = await SubtitleStyleStore().load()
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(SessionStore())
}
