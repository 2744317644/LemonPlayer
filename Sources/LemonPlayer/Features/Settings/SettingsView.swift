import SwiftUI
import LemonCore
import LemonDownloads
import LemonGuangya
import LemonNetwork
import LemonPersistence
import LemonSubtitle

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var downloadedBytes: Int64 = 0
    @State private var completedCount = 0
    @State private var showClearConfirm = false
    @State private var tmdbKey = UserDefaults.standard.string(forKey: "lemonplayer.tmdb.key") ?? ""
    @State private var tmdbSaved = false
    @State private var probeResult: String?
    @State private var probing = false
    @State private var deviceCodeProbe: String?
    @State private var storageLimitGB = UserDefaults.standard.integer(forKey: "lemonplayer.downloads.limitGB")
    @State private var fontCount = SubtitleFontStore.count

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

                Picker("容量上限", selection: $storageLimitGB) {
                    Text("不限制").tag(0)
                    Text("2 GB").tag(2)
                    Text("5 GB").tag(5)
                    Text("10 GB").tag(10)
                    Text("20 GB").tag(20)
                }
                .onChange(of: storageLimitGB) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "lemonplayer.downloads.limitGB")
                    Task {
                        await DownloadManager.shared.enforceStorageLimit(
                            maxBytes: Int64(newValue) * 1024 * 1024 * 1024
                        )
                        await refreshStorage()
                    }
                }

                Button("清理全部下载", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(completedCount == 0)

                Text("超出上限时自动清理最久未使用的已下载视频（不影响进行中的任务）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("播放与字幕") {
                NavigationLink("字幕样式") {
                    SubtitleStyleSettingsPreview()
                }
                Button("清除已导入字幕字体（\(fontCount)）", role: .destructive) {
                    SubtitleFontStore.removeAll()
                    fontCount = SubtitleFontStore.count
                }
                .disabled(fontCount == 0)
                Text("ASS 特效字幕的自定义字体在播放页「字幕 → 导入 ASS 字体」添加；导入后重播生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("媒体库（可选）") {
                SecureField("TMDB API Key", text: $tmdbKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("保存 Key") {
                        UserDefaults.standard.set(
                            tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            forKey: "lemonplayer.tmdb.key"
                        )
                        tmdbSaved = true
                    }
                    .disabled(tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if tmdbSaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text("可选。Bangumi 匹配不到时用 TMDB 兜底海报（真人影视更适用）。留空则只用 Bangumi。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("诊断") {
                Button {
                    Task { await runNetworkProbe() }
                } label: {
                    HStack {
                        Text("测试光鸭 API 连通性")
                        Spacer()
                        if probing {
                            ProgressView()
                        }
                    }
                }
                .disabled(probing)

                if let probeResult {
                    Text(probeResult)
                        .font(.footnote)
                        .foregroundStyle(probeResult.contains("✅") ? .green : .red)
                }

                Button("测试扫码授权接口") {
                    Task { await probeDeviceCode() }
                }
                if let deviceCodeProbe {
                    Text(deviceCodeProbe)
                        .font(.footnote)
                        .foregroundStyle(deviceCodeProbe.contains("✅") ? .green : .red)
                }

                NavigationLink("诊断日志") {
                    DiagnosticsView()
                }
                Text("登录失败时：先跑连通性测试，再导出诊断日志发给开发者。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: LemonCore.version)
                LabeledContent("构建", value: LemonCore.build)
                NavigationLink("演示播放（无需登录）") {
                    DemoPlayerView()
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

    /// 用一个故意无效的 token 请求 /user/me：
    /// - 401/117 → 网络可达（符合预期）
    /// - 传输错误 → 本机网络无法直连光鸭
    private func runNetworkProbe() async {
        probing = true
        probeResult = nil
        defer { probing = false }

        do {
            _ = try await session.auth.me(accessToken: "invalid-probe-token")
            probeResult = "⚠️ 返回了意外结果，但网络可达"
        } catch {
            if let guangya = error as? GuangyaError, guangya == .tokenExpired {
                probeResult = "✅ 网络可达光鸭 API（401 属预期：探测用 token 无效）"
            } else if let http = error as? HTTPError {
                probeResult = "❌ 网络无法访问光鸭 API：\(http.localizedDescription)"
            } else {
                probeResult = "❌ 网络异常：\(error.localizedDescription)"
            }
        }
    }

    /// 申请一次设备码（不轮询、不展示）：判断扫码登录的入口接口是否正常。
    private func probeDeviceCode() async {
        deviceCodeProbe = nil
        do {
            let code = try await session.auth.requestDeviceCode()
            deviceCodeProbe = "✅ 设备码接口正常（有效期 \(code.expiresIn)s / 轮询间隔 \(code.interval)s）"
        } catch {
            deviceCodeProbe = "❌ 设备码接口失败：\(error.localizedDescription)"
        }
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
