import Foundation
import Security
import LocalAuthentication

enum RemoteCredentials {
    struct Entry: Codable, Equatable {
        var password: String
        var originalXML: String?
    }
    private static var cachedVault: [String: Entry]?
    private static var cachedError: Error?
    private static let lock = NSRecursiveLock()

    private static var vaultQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.sstrepka.macmd.remote.vault",
         kSecAttrAccount as String: "connections-v1"]
    }

    private static func keychainError(_ status: OSStatus) -> Error {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
        return NSError(domain: "macmd.keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "macOS Keychain: \(detail) (\(status))."])
    }

    private static func readVaultFromKeychain() throws -> [String: Entry] {
        var request = vaultQuery
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else { throw keychainError(status) }
        guard let data = result as? Data else { throw keychainError(errSecDecode) }
        return try JSONDecoder().decode([String: Entry].self, from: data)
    }

    /// One authorization for the whole vault; never prompt again for every site or refresh.
    static func vault() throws -> [String: Entry] {
        lock.lock(); defer { lock.unlock() }
        if let cachedVault { return cachedVault }
        if let cachedError { throw cachedError }
        do {
            let loaded = try readVaultFromKeychain()
            cachedVault = loaded
            return loaded
        } catch {
            cachedError = error
            throw error
        }
    }

    static func saveVault(_ entries: [String: Entry]) throws {
        lock.lock(); defer { lock.unlock() }
        if cachedVault == entries { return }
        let data = try JSONEncoder().encode(entries)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(vaultQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = vaultQuery.merging(attributes) { _, value in value }
            item[kSecAttrLabel as String] = "macmd remote accounts"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
        let verified = try readVaultFromKeychain()
        guard verified == entries else { throw keychainError(errSecDecode) }
        cachedVault = verified
        cachedError = nil
    }

    /// Legacy per-site items are read without opening a cascade of authorization dialogs.
    /// Reimport can replace these credentials directly from XML, without touching old items.
    static func legacyEntry(_ id: UUID) throws -> Entry? {
        func read(_ suffix: String) throws -> String? {
            let context = LAContext()
            context.interactionNotAllowed = true
            let request: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.sstrepka.macmd.remote",
                kSecAttrAccount as String: id.uuidString + suffix,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw keychainError(status) }
            guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else { throw keychainError(errSecDecode) }
            return text
        }
        let password = try read("")
        let xml = try read(".xml")
        guard password != nil || xml != nil else { return nil }
        return Entry(password: password ?? "", originalXML: xml)
    }
}
