import Foundation

// In-memory backend: these regression tests must never touch real Keychain items.
enum RemoteCredentials {
    struct Entry: Codable, Equatable { var password: String; var originalXML: String? }
    static var entries: [String: Entry] = [:]
    static var legacyReads = 0
    static var vaultWrites = 0
    static var denied = false
    static func vault() throws -> [String: Entry] {
        if denied { throw RemoteTrust.error("Simulated Keychain denial") }
        return entries
    }
    static func saveVault(_ values: [String: Entry]) throws {
        if denied { throw RemoteTrust.error("Simulated Keychain denial") }
        vaultWrites += 1
        entries = values
    }
    static func legacyEntry(_ id: UUID) throws -> Entry? {
        legacyReads += 1
        throw RemoteTrust.error("Legacy access must not be needed during complete XML reimport")
    }
}
