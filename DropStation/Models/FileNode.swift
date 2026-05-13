import Foundation

/// A folder (or file) returned by SYNO.FileStation.List.
/// Shared folders and ordinary subfolders share this shape — the API just calls one
/// `shares` and the other `files` in the response wrapper.
struct FileNode: Decodable, Hashable, Identifiable {
    let name: String
    /// FileStation path: leading "/" plus shared-folder name plus subpath,
    /// e.g. "/Downloads", "/Downloads/Movies".
    let path: String
    let isdir: Bool

    var id: String { path }
}

extension FileNode {
    /// Convert a FileStation path ("/Downloads/Movies") to the Download Station
    /// `destination` parameter format ("Downloads/Movies" — no leading slash).
    var destinationPath: String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}
