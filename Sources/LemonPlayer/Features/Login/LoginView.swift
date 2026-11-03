import SwiftUI
import LemonGuangya

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: LoginViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    LoginStatusView(model: model)
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
    }
}

private struct LoginStatusView: View {
    let model: LoginViewModel

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
                Text(code.userCode)
                    .font(.system(.footnote, design: .monospaced))
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
                Button("重试") {
                    Task { await model.start() }
                }
                .buttonStyle(.borderedProminent)

            case .success:
                ProgressView("登录成功，正在进入…")
            }

            Spacer(minLength: 0)

            Text("扫码即表示同意光鸭云盘的服务条款。凭据仅保存在本机 Keychain。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}
