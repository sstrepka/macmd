import AppKit

// Import through the installed, signed application so Keychain uses its own identity.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--import-filezilla" {
    do {
        let imported = try FileZillaImport.loadConnections(from: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard !imported.isEmpty, FTPConnectionStore.shared.importConnections(imported) else {
            FileHandle.standardError.write(Data(("Import failed: " + (FTPConnectionStore.shared.lastError?.localizedDescription ?? "Credentials could not be saved and verified in Keychain.") + "\n").utf8))
            exit(1)
        }
        print("Imported and verified credentials for \(imported.count) accounts.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("FileZilla import failed.\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
