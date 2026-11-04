import SwiftUI
import LemonGuangya

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: LoginViewModel?
    @State private var showAccountSheet = false
    @State private var showWebLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    LoginStatusView(
                        model: model,
                        onShowAccountLogin: { showAccountSheet = true },
                        onShowWebLogin: { showWebLogin = true }
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
        .sheet(isPresented: $showAccountSheet) {
            AccountLoginSheet { username, password in
                await session.signin(username: username, password: password)
            }
        }
        .sheet(isPresented: $showWebLogin) {
            WebLoginView { accessToken, refreshToken in
                await session.loginWithTokens(accessToken: accessToken, refreshToken: refreshToken)
            }
        }
    }
}

private struct LoginStatusView: View {
    let model: LoginViewModel
    let onShowAccountLogin: () -> Void
    let onShowWebLogin: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            switch model.phase {
            case .loading:
                ProgressView("正在获取登录二维码…")

            case .waiting, .expired:
                qrSection

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                Button("重试") {
                    Task { await model.start() }
                }
                .buttonStyle(.borderedProminent)

            case .success:
                ProgressView("登录成功，正在进入…")
            }

            Spacer(minLength: 0)

            Button {
                onShowWebLogin()
            } label: {
                Label("网页登录", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                onShowAccountLogin()
            } label: {
                Label("使用账号密码登录", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private var qrSection: some View {
        if let image = model.qrImage {
            Button {
                // 点击二维码刷新
                Task { await model.start() }
            } label: {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新二维码")
        } else {
            ProgressView()
        }

        Text("请用光鸭云盘 App 扫码")
            .font(.headline)
        Text("点击二维码可刷新")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AccountLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    let onSubmit: (String, String) async -> TokenLoginResult

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("账号（手机号 / 邮箱 / 用户名）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("密码", text: $password)
                } header: {
                    Text("账号密码登录")
                } footer: {
                    Text("使用你在光鸭云盘注册的账号。若提示账号或密码错误，请改用网页登录（可过验证码）。")
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
                            let result = await onSubmit(
                                username.trimmingCharacters(in: .whitespacesAndNewlines),
                                password
                            )
                            isSubmitting = false
                            switch result {
                            case .success:
                                dismiss()
                            case .invalidCredentials:
                                errorMessage = "账号或密码错误（若确认无误，请改用网页登录）"
                            case .invalidFormat:
                                errorMessage = "账号格式不正确"
                            case .unauthorized:
                                errorMessage = "登录被拒绝，请稍后重试"
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
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || password.isEmpty
                            || isSubmitting
                    )
                }
            }
            .navigationTitle("账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("取消") { dismiss() }
            }
        }
    }
}
