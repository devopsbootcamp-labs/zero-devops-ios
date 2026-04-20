import Foundation
import Security

/// Persists TokenBundle in the iOS Keychain (encrypted at rest).
final class TokenStore {

    static let shared = TokenStore()

    private let service = "com.devopsbootcamp.app.tokens"
    private let account = "token_bundle"

    // MARK: - Public

    func save(_ bundle: TokenBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func load() -> TokenBundle? {
        var query = baseQuery()
        query[kSecReturnData  as String] = true
        query[kSecMatchLimit  as String] = kSecMatchLimitOne
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return nil }
        return try? JSONDecoder().decode(TokenBundle.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Private

    private func baseQuery() -> [String: Any] {
        [
            kSecClass        as String: kSecClassGenericPassword,
            kSecAttrService  as String: service,
            kSecAttrAccount  as String: account,
        ]
    }
}
