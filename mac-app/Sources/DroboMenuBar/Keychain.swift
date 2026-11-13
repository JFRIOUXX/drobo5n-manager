// Enveloppe minimale autour du Trousseau (Security framework) pour stocker le
// mot de passe SSH du Drobo. Jamais écrit en clair sur disque.

import Foundation
import Security

enum KeychainError: Error {
    case unhandled(OSStatus)
}

enum KeychainStore {
    private static let service = "com.jf.drobo5n-manager"
    // Compte fixe : un seul Drobo géré par l'app, on ne veut pas d'entrées
    // orphelines si l'utilisateur change juste le nom d'utilisateur SSH.
    private static let account = "drobo5n2"

    static func savePassword(_ password: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        guard !password.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func loadPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
