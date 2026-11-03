import Foundation
import Observation
import LemonGuangya
import LemonNetwork
import LemonPersistence

/// 登录态与依赖装配。App 内唯一持有 `GuangyaAuthClient` / `TokenStore` 的地方。
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case checking
        case loggedOut
        case loggedIn(subject: String)
        case failed(String)
    }

    private(set) var state: State = .checking

    let auth: GuangyaAuthClient
    let identity: DeviceIdentity
    private let tokens: TokenStore

    init(
        auth: GuangyaAuthClient? = nil,
        tokens: TokenStore = TokenStore(),
        identity: DeviceIdentity = SessionStore.loadOrCreateIdentity()
    ) {
        self.identity = identity
        self.tokens = tokens
        self.auth = auth ?? GuangyaAuthClient(identity: identity)
    }

    /// 冷启动：恢复登录态，token 过期则静默刷新。
    func restore() async {
        state = .checking
        do {
            guard var credentials = try await tokens.load() else {
                state = .loggedOut
                return
            }
            if credentials.isExpired() {
                let refreshed = try await auth.refresh(refreshToken: credentials.refreshToken)
                credentials = Credentials(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn)),
                    subject: refreshed.subject ?? credentials.subject
                )
                try await tokens.save(credentials)
            }
            state = .loggedIn(subject: credentials.subject ?? "已登录")
        } catch {
            // 刷新失败（refresh_token 失效）→ 回到登录页
            state = .loggedOut
        }
    }

    func completeLogin(_ bundle: TokenBundle) async {
        let credentials = Credentials(
            accessToken: bundle.accessToken,
            refreshToken: bundle.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(bundle.expiresIn)),
            subject: bundle.subject
        )
        do {
            try await tokens.save(credentials)
        } catch {
            state = .failed("凭据保存失败：\(error.localizedDescription)")
            return
        }
        state = .loggedIn(subject: credentials.subject ?? "已登录")
    }

    func logout() async {
        try? await tokens.clear()
        state = .loggedOut
    }

    /// 有效的 access_token（未登录/过期返回 nil）。M2 的浏览接口会用到。
    func currentAccessToken() async -> String? {
        guard let credentials = try? await tokens.load(), !credentials.isExpired() else {
            return nil
        }
        return credentials.accessToken
    }

    private nonisolated static func loadOrCreateIdentity() -> DeviceIdentity {
        let key = "guangya.device.identity"
        if let data = UserDefaults.standard.data(forKey: key),
           let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) {
            return identity
        }
        let identity = DeviceIdentity.random()
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return identity
    }
}
