import ArxivDiscoveryCore
import Foundation

func exportUIFixture(to root: URL) throws {
    guard root.standardizedFileURL.path.hasPrefix(VerificationLibrary.baseURL.standardizedFileURL.path + "/"),
          !FileManager.default.fileExists(atPath: root.path) else { throw CheckFailure.failed("Use a new folder under the verification cache.") }
    let repository = PaperRepository(rootURL: root)
    let source = PaperRepository()
    var values = try source.loadPapers()
    guard let representative = values.first else { throw CheckFailure.failed("A representative public paper is required.") }
    for index in values.count..<7000 {
        var value = representative
        value.shortID = String(format: "qa-%05d", index)
        value.entryID = "https://arxiv.org/abs/" + value.shortID
        value.title = index.isMultiple(of: 2) ? "Verification \(index): Vision-Language-Action for Robot Manipulation" : "Verification \(index): Latent World Models for Long-Horizon Simulation"
        value.abstract = index.isMultiple(of: 2) ? "A vision-language-action model learns robot manipulation. " + representative.abstract : "A world model predicts environment dynamics. " + representative.abstract
        values.append(value)
    }
    var library = try source.loadLibraryState()
    for index in 1...3 {
        var value = representative
        value.shortID = "qa-unrelated-\(index)"
        value.title = "Verification unrelated \(index): Graph Colouring and Number Theory"
        value.abstract = "A combinatorial proof about prime numbers and graph colouring."
        value.abstractKO = nil
        values.insert(value, at: 0)
        if index == 3 { library.setNote("Protected verification reading note. Do not remove.", paperID: value.shortID) }
    }
    try repository.savePapers(values)
    try repository.saveLibraryState(library)
    for name in ["cleanup-state.json", "trash.json", "discovery-history.json"] {
        let file = source.rootURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: file, to: root.appendingPathComponent(name)) }
    }
    try Data("{\"schemaVersion\":1,\"offline\":true}".utf8).write(to: root.appendingPathComponent("verification.json"), options: .atomic)
    print("Created isolated UI verification library: \(root.path)")
    print("7,003 active papers; two removable fixtures; one protected note fixture. No credentials or PDFs copied.")
}
