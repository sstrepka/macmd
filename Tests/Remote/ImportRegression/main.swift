import AppKit
import Foundation

_ = NSApplication.shared
// Read the attached export without printing or persisting its credentials.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let imported = try FileZillaImport.loadConnections(from: source)
let xml = try XMLDocument(contentsOf: source)
let servers = try xml.nodes(forXPath: "//Servers//Server") as! [XMLElement]
precondition(imported.count == servers.count)
for (connection, server) in zip(imported, servers) {
    let pass = server.elements(forName: "Pass").first!
    let original = String(data: Data(base64Encoded: pass.stringValue!)!, encoding: .utf8)!
    precondition(!original.isEmpty && connection.password == original, "Password decode mismatch")
    precondition(connection.logonType == 1, "Expected normal login")
    precondition(!connection.needsPasswordPrompt, "Imported account must connect without a password dialog")
}
print("PASS: all \(imported.count) supplied passwords decode exactly; all accounts use normal login")
FTPConnectionManagerWindowController.verifyImportedCredentials(imported)
print("PASS: loading, saving form, switching sites, toolbar refresh and new-site creation preserve every supplied account and password")
