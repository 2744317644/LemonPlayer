import Foundation

/// token 持久化。用 actor 串行化读写，配合上层 single-flight 刷新。
public actor TokenStore {
    private let keychain: KeychainStore
    private let account = "guangya.access"

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func load() throws -> Credentials? {
        guard let data = try keychain.load(account: account) else { return nil }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.save(data, account: account)
    }

    public func clear() throws {
        try keychain.delete(account: account)
    }
}
