import Foundation
import Security

// MARK: - AtlasKeychainStore
//
// Reads and writes the Atlas auth token from the iOS Keychain.
// No third-party dependencies — uses Security framework directly.

enum AtlasKeychainStore {

    private static let service = "uk.atlas-phm.AtlasScan"
    private static let authTokenAccount = "atlasAuthToken"

    // MARK: - Save

    /// Saves (or updates) the auth token in the Keychain.
    static func saveAuthToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: authTokenAccount
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    // MARK: - Load

    /// Returns the stored auth token, or nil if not present.
    static func loadAuthToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: authTokenAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    // MARK: - Delete

    /// Removes the stored auth token.
    static func deleteAuthToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: authTokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
