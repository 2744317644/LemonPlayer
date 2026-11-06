import SwiftUI
import WebKit

/// App 内网页登录：加载光鸭官网登录页，用户在网页里完成登录（可过验证码），
/// 登录成功后官网 SDK 会把 credentials 写入 localStorage（key 以 `credentials_` 开头），
/// 这里轮询读取并自动完成 App 登录。
struct WebLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = "在网页中登录（手机验证码 / 密码），成功后自动返回 App"
    @State private var isFinishing = false
    /// 变了就重建 WKWebView，用于「重新加载」。
    @State private var reloadID = UUID()

    let onTokens: @MainActor (String, String) async -> TokenLoginResult

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if isFinishing { ProgressView() }
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

                WebLoginWebView(onCredentials: { accessToken, refreshToken in
                    guard !isFinishing else { return }
                    isFinishing = true
                    message = "已获取登录凭据，正在验证…"
                    Task {
                        let result = await onTokens(accessToken, refreshToken)
                        isFinishing = false
                        switch result {
                        case .success:
                            dismiss()
                        case .failed(let reason):
                            message = "登录失败：\(reason)"
                        case .unauthorized:
                            message = "凭据无效，请重新登录"
                        case .invalidCredentials:
                            message = "账号或密码错误"
                        case .invalidFormat:
                            message = "凭据格式异常，请重试"
                        }
                    }
                })
                .id(reloadID)
            }
            .navigationTitle("网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        message = "正在重新加载网页…"
                        reloadID = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新加载")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct WebLoginWebView: UIViewRepresentable {
    let onCredentials: (String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCredentials: onCredentials)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // 官网登录页（路由是 /oauth/login；/login 会落到营销首页）
        if let url = URL(string: "https://www.guangyapan.com/oauth/login") {
            webView.load(URLRequest(url: url))
        }
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCredentials: (String, String) -> Void
        // Swift 6 的 deinit 是 nonisolated，Timer 非 Sendable，需要显式标注
        nonisolated(unsafe) private var timer: Timer?
        private var finished = false

        init(onCredentials: @escaping (String, String) -> Void) {
            self.onCredentials = onCredentials
        }

        deinit {
            timer?.invalidate()
        }

        func startPolling(_ webView: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.scanLocalStorage(webView)
            }
        }

        /// 读取 localStorage 里 `credentials_*` 的 JSON，找 access_token / refresh_token。
        private func scanLocalStorage(_ webView: WKWebView) {
            guard !finished else { return }
            let script = """
            (function(){
              var out = {};
              for (var i = 0; i < localStorage.length; i++) {
                var k = localStorage.key(i);
                if (k && k.indexOf('credentials_') === 0) {
                  out[k] = localStorage.getItem(k);
                }
              }
              return JSON.stringify(out);
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self, !self.finished else { return }
                guard let string = result as? String,
                      let data = string.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                    return
                }
                for (_, value) in dict {
                    guard let valueData = value.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] else {
                        continue
                    }
                    guard let access = object["access_token"] as? String, !access.isEmpty else {
                        continue
                    }
                    let refresh = object["refresh_token"] as? String ?? ""
                    self.finished = true
                    self.timer?.invalidate()
                    self.onCredentials(access, refresh)
                    return
                }
            }
        }
    }
}
