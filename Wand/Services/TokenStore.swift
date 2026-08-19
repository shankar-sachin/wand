import Foundation
import Security

/// Keychain storage for per-TV pairing tokens.
///
/// A token is a durable credential — whoever holds it can control the TV without the
/// on-screen prompt — so it lives in the Keychain rather than alongside the device list
/// in `UserDefaults`. `ThisDeviceOnly` keeps it off backups and other devices, where it
/// would be useless anyway since the TV binds pairings to a client name.
enum TokenStore {

    private static let service = "com.sachi.wand.tv-token"

    static func token(for deviceID: UUID) -> String? {
        var query = baseQuery(deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func save(_ token: String, for deviceID: UUID) {
        let data = Data(token.utf8)
        let query = baseQuery(deviceID)

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecSuccess else { return }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func delete(for deviceID: UUID) {
        SecItemDelete(baseQuery(deviceID) as CFDictionary)
    }

    private static func baseQuery(_ deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
        ]
    }
}
