import Foundation
import Security

enum RemoteCredentials {
    private static func query(_ id: UUID, suffix: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.sstrepka.macmd.remote",
         kSecAttrAccount as String: id.uuidString + suffix]
    }
    static func read(_ id: UUID, suffix: String = "") -> String? {
        var request = query(id, suffix: suffix)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, id: UUID, suffix: String = "") -> Bool {
        let request = query(id, suffix: suffix)
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
    static func remove(_ id: UUID) {
        for suffix in ["", ".xml"] { SecItemDelete(query(id, suffix: suffix) as CFDictionary) }
    }
}
