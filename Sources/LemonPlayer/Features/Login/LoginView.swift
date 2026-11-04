import SwiftUI
import LemonGuangya

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: LoginViewModel?
    @State private var showTokenSheet = false
    @State private var showDemo = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    LoginStatusView(
                        model: model,
                        onOpenAuthorization: { url in openURL(url) },
                        onShowTokenLogin: { showTokenSheet = true },
                        onShowDemo: { showDemo = true }
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("登录光鸭云盘")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard model == nil else { return }
            let created = LoginViewModel(auth: session.auth) { bundle in
                await session.completeLogin(bundle)
            }
            model = created
            await created.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 去光鸭 App 扫码后切回：若轮询已失败/过期，自动重试而不是让用户重扫
            guard newPhase == .active, let model else { return }
            Task { await model.retryIfNeeded() }
        }
        .sheet(isPresented: $showTokenSheet) {
            TokenLoginSheet { token in
                await session.loginWithAccessToken(token)
            }
        }
        .sheet(isPresented: $showDemo) {
            NavigationStack {
                DemoPlayerView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showDemo = false }
                        }
                    }
            }
        }
    }
}

private struct LoginStatusView: View {
    let model: LoginViewModel
    let onOpenAuthorization: (URL) -> Void
    let onShowTokenLogin: () -> Void
    let onShowDemo: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            switch model.phase {
            case .loading:
                ProgressView("正在获取登录二维码…")

            case .waiting(let code):
                if let image = model.qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("登录二维码")
                }
                Text("请用光鸭云盘 App 扫码")
                    .font(.headline)
                Text("二维码约 \(code.expiresIn) 秒内有效，过期会自动换新")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(code.userCode)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = code.userCode
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                }

                // 浏览器兜底：App 扫码不生效时，手动打开授权页并输入设备码
                if let url = authorizationURL(for: code) {
                    Button {
                        onOpenAuthorization(url)
                    } label: {
                        Label("在浏览器打开授权页", systemImage: "safari")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    // API 域名的 web 页面在部分网络下 404；改用网页域名再试
                    if let webURL = webAuthorizationURL(for: code), webURL != url {
                        Button {
                            onOpenAuthorization(webURL)
                        } label: {
                            Label("改用网页域名打开", systemImage: "globe")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text(pollStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("换一张二维码") {
                    Task { await model.start() }
                }
                .buttonStyle(.bordered)

            case .expired:
                Label("二维码已过期", systemImage: "clock.badge.exclamationmark")
                    .font(.headline)
                Button("重新获取") {
                    Task { await model.start() }
                }
                .buttonStyle(.borderedProminent)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                if let detail = model.lastError, !detail.isEmpty, detail != message {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !model.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动自检结果")
                            .font(.caption.weight(.semibold))
                        ForEach(model.diagnostics, id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button("重试") {
                        Task { await model.start() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("改用 Token 登录") {
                        onShowTokenLogin()
                    }
                    .buttonStyle(.bordered)
                }

                Button("复制诊断信息") {
                    let text = (model.diagnostics + [message]).joined(separator: "\n")
                    UIPasteboard.general.string = text
                }
                .font(.footnote)
                .buttonStyle(.borderless)

            case .success:
                ProgressView("登录成功，正在进入…")
            }

            Spacer(minLength: 0)

            Button {
                onShowTokenLogin()
            } label: {
                Text("无法扫码？使用 Token 登录")
                    .font(.footnote)
            }

            Button {
                onShowDemo()
            } label: {
                Label("无需登录，先体验播放器", systemImage: "play.rectangle")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)

            Text("扫码即表示同意光鸭云盘的服务条款。凭据仅保存在本机 Keychain。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private func authorizationURL(for code: DeviceCode) -> URL? {
        if let complete = code.verificationURIComplete, let url = URL(string: complete) {
            return url
        }
        if let base = code.verificationURL, let url = URL(string: base) {
            return url
        }
        return nil
    }

    /// 同一路径换成网页域名（account 是 API 域，不一定承载授权页）。
    private func webAuthorizationURL(for code: DeviceCode) -> URL? {
        guard let primary = authorizationURL(for: code),
              var components = URLComponents(url: primary, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = "www.guangyupan.com"
        return components.url
    }

    private var pollStatus: String {
        if let error = model.lastError, !error.isEmpty {
            return "网络波动，正在重试…（第 \(model.pollCount) 次）"
        }
        return "等待扫码确认…（已轮询 \(model.pollCount) 次）"
    }
}

private struct TokenLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showHelp = false

    let onSubmit: (String) async -> TokenLoginResult

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴 access_token（JWT）", text: $token, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            token = clipboard
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Token 直登")
                } footer: {
                    Text("Token 有效期约 1 小时；过期后重新获取即可。仅保存在本机 Keychain。")
                }

                Section {
                    DisclosureGroup("如何获取 access_token？", isExpanded: $showHelp) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. 电脑浏览器打开 www.guangyupan.com 并登录")
                            Text("2. 按 F12 / 右键「检查」→ Network 面板")
                            Text("3. 刷新页面，点任意一个 api.guangyapan.com 请求")
                            Text("4. Request Headers 里找 Authorization: Bearer eyJ...")
                            Text("5. 复制 eyJ 开头的三段字符串（JWT），粘贴到这里")
                            Text("提示：域名被墙时先连代理再访问网页。")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task {
                            isSubmitting = true
                            errorMessage = nil
                            let result = await onSubmit(token)
                            isSubmitting = false
                            switch result {
                            case .success:
                                dismiss()
                            case .invalidFormat:
                                errorMessage = "格式不对：需要三段由 . 分隔的 JWT（以 eyJ 开头）"
                            case .unauthorized:
                                errorMessage = "Token 无效或已过期，请重新获取（401/117）"
                            case .failed(let reason):
                                errorMessage = "登录失败：\(reason)"
                            }
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("登录")
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Token 登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("取消") { dismiss() }
            }
        }
    }
}
