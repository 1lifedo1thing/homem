import Foundation
import UniformTypeIdentifiers

struct SharedFile: Identifiable {
    let url: URL
    let size: Int64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum SharedFiles {
    static let maxBytes: Int64 = 50 * 1_024 * 1_024
    static func safeName(_ proposed: String) -> String {
        let name = (proposed as NSString).lastPathComponent
            .components(separatedBy: .controlCharacters).joined(separator: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." || name == "/" ? "Shared file" : name
    }
    static func copy(_ source: URL, into directory: URL, suggestedName: String? = nil) throws -> SharedFile {
        guard source.isFileURL else { throw ClientError.message("This item is not a file.".localized) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ClientError.message("Share individual files instead of folders.".localized) }
        let size = Int64(values.fileSize ?? 0)
        guard size <= maxBytes else { throw ClientError.message("Choose a file smaller than 50 MB.".localized) }
        var name = safeName(suggestedName?.nonEmpty ?? source.lastPathComponent)
        if (name as NSString).pathExtension.isEmpty, !source.pathExtension.isEmpty { name += "." + source.pathExtension }
        var destination = directory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let ext = (name as NSString).pathExtension
            let stem = (name as NSString).deletingPathExtension
            destination = directory.appendingPathComponent("\(stem) (\(suffix))" + (ext.isEmpty ? "" : "." + ext))
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        return SharedFile(url: destination, size: size)
    }
    static func load(_ provider: NSItemProvider, into directory: URL) async throws -> SharedFile {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    do {
                        if let error { throw error }
                        guard let url = item as? URL else { throw ClientError.message("This item is not a file.".localized) }
                        continuation.resume(returning: try copy(url, into: directory))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) else {
            throw ClientError.message("This item is not a file.".localized)
        }
        let name = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw ClientError.message("This item is not a file.".localized) }
                    // Provider URLs cease to be valid once this callback returns.
                    continuation.resume(returning: try copy(url, into: directory, suggestedName: name))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Stream the multipart body to disk to stay within a share extension's memory budget.
    static func multipart(file: SharedFile, destination: String, boundary: String, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".multipart")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let output = try FileHandle(forWritingTo: url)
        let input = try FileHandle(forReadingFrom: file.url)
        defer { try? output.close(); try? input.close() }
        do {
            let name = safeName(file.name)
            try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"path\"\r\n\r\n\(destination)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            while let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty { try output.write(contentsOf: chunk) }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}
