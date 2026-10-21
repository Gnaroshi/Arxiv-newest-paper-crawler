import Foundation

public enum VerificationLibrary {
    public static var baseURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.gnaroshi.ArxivDiscovery/UIVerification", isDirectory: true)
    }

    public static func isValid(_ root: URL) -> Bool {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard root.path.hasPrefix(baseURL.resolvingSymlinksInPath().path + "/"),
              let data = try? Data(contentsOf: root.appendingPathComponent("verification.json")),
              let marker = try? JSONDecoder().decode(Marker.self, from: data),
              marker.schemaVersion == 1, marker.offline else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        return files.allSatisfy { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
    }

    private struct Marker: Decodable { var schemaVersion: Int; var offline: Bool }
}
