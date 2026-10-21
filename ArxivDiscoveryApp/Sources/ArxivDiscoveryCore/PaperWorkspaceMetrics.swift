import Foundation

public struct PaperWorkspaceMetrics: Sendable {
    public let sideBySide: Bool
    public let maximumListWidth: Double

    public init(width: Double) {
        let width = width.isFinite ? max(0, width) : 0
        sideBySide = width >= 601
        maximumListWidth = max(280, min(480, width - 301))
    }
}
