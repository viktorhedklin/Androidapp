import Foundation
import Security

/// Hand-rolled wrapper over the Security framework's generic-password
/// item -- no third-party dependency, no Keychain-access-group
/// entitlement needed (those only matter for sandboxed/multi-app sharing,
/// irrelevant for this single unsandboxed app). Stores exactly one secret:
/// the currently configured provider's API key.
enum Keychain {
    private static let service = "com.gameautopilot.mac"

    static func set(_ value: String, account: String = "apiKey") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary) // sidesteps errSecDuplicateItem on re-save

        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        // Available to a foreground utility without requiring the user to
        // have unlocked this app's own UI first; ThisDeviceOnly opts out
        // of iCloud Keychain sync, appropriate for a per-machine key.
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(account: String = "apiKey") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String = "apiKey") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasValue(account: String = "apiKey") -> Bool {
        get(account: account) != nil
    }
}
