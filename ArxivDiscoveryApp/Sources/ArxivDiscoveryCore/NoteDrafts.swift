import Foundation

/// Unsaved text belongs to a paper, not to the lifetime of its detail view.
public struct NoteDrafts: Sendable {
    private var values: [String: String] = [:]
    public init() {}
    public var editedIDs: [String] { values.keys.sorted() }
    public var isEmpty: Bool { values.isEmpty }

    public func text(for id: String, saved: String) -> String { values[id] ?? saved }

    public mutating func update(_ text: String, for id: String, saved: String) {
        if text == saved { values.removeValue(forKey: id) }
        else { values[id] = text }
    }

    public mutating func discard(_ id: String) { values.removeValue(forKey: id) }
}
