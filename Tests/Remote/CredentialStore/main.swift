import Foundation

let suite = "macmd.credential-test.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = FTPConnectionStore(defaults: defaults)
let imported = (0..<10).map { index -> FTPConnection in
    var connection = FTPConnection(name: "Site \(index)", host: "example.invalid", username: "user\(index)", password: "test password \(index)", logonType: 1)
    connection.fileZillaXML = "<Server><Pass>synthetic-only</Pass></Server>"
    return connection
}
// Simulate the previous version's metadata; the legacy Keychain denies every read.
let oldMetadata = imported.map { source -> FTPConnection in
    var copy = source; copy.password = ""; copy.fileZillaXML = nil; return copy
}
defaults.set(try JSONEncoder().encode(oldMetadata), forKey: "macmd.ftp.connections")
precondition(store.importConnections(imported))
precondition(RemoteCredentials.legacyReads == 0, "Reimport opened legacy Keychain entries")
precondition(RemoteCredentials.vaultWrites == 1, "Import must write a single vault")
for _ in 0..<5 {
    let loaded = store.connections()
    precondition(loaded.count == imported.count)
    for expected in imported {
        precondition(loaded.contains { $0.id == expected.id && $0.password == expected.password && !$0.needsPasswordPrompt })
    }
}
let metadata = defaults.data(forKey: "macmd.ftp.connections")!
let stripped = try JSONDecoder().decode([FTPConnection].self, from: metadata)
precondition(stripped.allSatisfy { $0.password.isEmpty && $0.fileZillaXML == nil }, "Credential material leaked to defaults")
RemoteCredentials.denied = true
let blocked = store.connections()
precondition(blocked.allSatisfy { $0.credentialAccessError != nil })
precondition(!store.save(blocked), "Denied credential reads must never overwrite saved credentials")
precondition(store.lastError != nil)
precondition(defaults.data(forKey: "macmd.ftp.connections") == metadata)
precondition(RemoteCredentials.vaultWrites == 1)
print("PASS: one vault write for 10 accounts; zero legacy credential reads; repeated reload preserves passwords; no secrets in defaults; denied access cannot overwrite credentials")
