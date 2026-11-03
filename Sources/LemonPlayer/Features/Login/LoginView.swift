import SwiftUI
import LemonGuangya

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: LoginViewModel?
    @State private var showTokenSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    LoginStatusView(model: model) { url in
                        openURL(url)
                    } onShowTokenLogin: {
                        showTokenSheet = true
                    }
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
    }
}

private struct LoginStatusView: View {
    let model: LoginViewModel
    let onOpenAuthorization: (URL) -> Void
    let onShowTokenLogin: () -> Void

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
                Button("重试") {
                    Task { await model.start() }
                }
                .buttonStyle(.borderedProminent)

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

    let onSubmit: (String) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴 access_token（JWT）", text: $token, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Token 直登（临时方案）")
                } footer: {
                    Text("获取方式：浏览器登录 www.guangyupan.com → F12 → Network → 任一请求的 Authorization: Bearer 后面的 JWT。Token 会过期，仅用于临时联调。")
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
                            let success = await onSubmit(token)
                            isSubmitting = false
                            if success {
                                dismiss()
                            } else {
                                errorMessage = "Token 无效或已过期，请重新获取"
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
