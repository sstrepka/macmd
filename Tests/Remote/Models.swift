import Foundation
// Standalone transport harness: no application startup or real accounts.
struct FileItem {
    var name: String
    var url: URL
    var isDirectory: Bool
    var typeDescription: String
    var size: Int64
    var modDate: Date
    var isParent: Bool
    var isVirtual: Bool
}
