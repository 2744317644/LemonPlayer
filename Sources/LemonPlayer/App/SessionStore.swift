import Foundation
import Observation
import LemonCore
import LemonGuangya
import LemonNetwork
import LemonPersistence

/// Token 直登结果（UI 据此给出具体原因）。
enum TokenLoginResult: Equatable {
    case success(String)
    case invalidFormat
    case unauthorized
    case failed(String)
}

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
    /// Keychain 写入失败时的内存兜底（侧载环境偶发），保证本次会话可用。
    @ObservationIgnored private var volatileCredentials: Credentials?
    @ObservationIgnored private var refreshTask: Task<String, Error>?

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
            let stored = try? await tokens.load()
            guard var credentials = stored ?? volatileCredentials else {
                state = .loggedOut
                return
            }
            volatileCredentials = credentials
            if credentials.isExpired() {
                let refreshed = try await auth.refresh(refreshToken: credentials.refreshToken)
                credentials = Credentials(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn)),
                    subject: refreshed.subject ?? credentials.subject
                )
                try? await tokens.save(credentials)
                volatileCredentials = credentials
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
        volatileCredentials = credentials
        do {
            try await tokens.save(credentials)
        } catch {
            // 侧载/描述文件异常时 Keychain 可能不可写：本次会话先用内存凭据
            Task { await DiagnosticsCenter.shared.log(.warning, "auth", "Keychain 写入失败，使用内存凭据：\(error.localizedDescription)") }
        }
        state = .loggedIn(subject: credentials.subject ?? "已登录")
    }

    func logout() async {
        volatileCredentials = nil
        try? await tokens.clear()
        state = .loggedOut
    }

    /// 兜底登录：直接粘贴 access_token（JWT）。先探测 /user/me，成功才落库。
    func loginWithAccessToken(_ rawToken: String) async -> TokenLoginResult {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.split(separator: ".").count == 3 else { return .invalidFormat }
        do {
            let me = try await auth.me(accessToken: token)
            let credentials = Credentials(
                accessToken: token,
                refreshToken: "",
                expiresAt: Date().addingTimeInterval(3600),
                subject: me.subject
            )
            volatileCredentials = credentials
            try? await tokens.save(credentials)
            state = .loggedIn(subject: me.subject)
            Task { await DiagnosticsCenter.shared.log(.info, "auth", "Token 直登成功") }
            return .success(me.subject)
        } catch {
            Task { await DiagnosticsCenter.shared.log(.error, "auth", "Token 直登失败：\(error.localizedDescription)") }
            if let guangya = error as? GuangyaError {
                switch guangya {
                case .tokenExpired, .unauthorized:
                    return .unauthorized
                default:
                    return .failed(guangya.localizedDescription)
                }
            }
            if let http = error as? HTTPError {
                return .failed(http.localizedDescription)
            }
            return .failed(error.localizedDescription)
        }
    }

    /// 有效的 access_token（未登录/过期返回 nil）。M2 的浏览接口会用到。
    func currentAccessToken() async -> String? {
        guard let credentials = try? await tokens.load(), !credentials.isExpired() else {
            return nil
        }
        return credentials.accessToken
    }

    /// 取一个可用的 access_token；过期时自动刷新（single-flight，避免并发互踢 refresh_token）。
    func validAccessToken() async throws -> String {
        guard let credentials = (try? await tokens.load()) ?? volatileCredentials else {
            throw GuangyaError.unauthorized
        }
        if !credentials.isExpired() {
            return credentials.accessToken
        }
        return try await refreshAccessToken()
    }

    @discardableResult
    func refreshAccessToken() async throws -> String {
        if let existing = refreshTask {
            return try await existing.value
        }

        let task = Task { [self] () throws -> String in
            guard let credentials = (try? await tokens.load()) ?? volatileCredentials else {
                throw GuangyaError.unauthorized
            }
            let refreshed = try await auth.refresh(refreshToken: credentials.refreshToken)
            let newCredentials = Credentials(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn)),
                subject: refreshed.subject ?? credentials.subject
            )
            try? await tokens.save(newCredentials)
            volatileCredentials = newCredentials
            return newCredentials.accessToken
        }
        refreshTask = task

        do {
            let token = try await task.value
            refreshTask = nil
            state = .loggedIn(subject: volatileCredentials?.subject ?? "已登录")
            return token
        } catch {
            refreshTask = nil
            state = .loggedOut
            throw error
        }
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
