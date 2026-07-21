import ArxivDiscoveryCore
import Foundation

enum ShowcaseMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--showcase")
    }

    static var papers: [Paper] {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 9))!
        return [
            Paper(
                entryID: "https://arxiv.org/abs/demo.00001",
                shortID: "demo.00001",
                title: "Structured Memory for Long-Horizon Vision-Language-Action Policies",
                authors: ["Min Seo", "Alex Kim", "Rina Park"],
                subjects: ["cs.RO", "cs.CV"],
                abstract: "We study a structured memory interface for long-horizon embodied policies. The example metadata is deterministic and does not represent a real paper or personal reading activity.",
                pdfURL: "https://arxiv.org/pdf/demo.00001.pdf",
                publishedAt: reference,
                crawledAt: reference
            ),
            Paper(
                entryID: "https://arxiv.org/abs/demo.00002",
                shortID: "demo.00002",
                title: "Compositional Action Tokens for Generalist Robot Control",
                authors: ["J. Lee", "M. Chen"],
                subjects: ["cs.AI", "cs.LG"],
                abstract: "This deterministic example summary demonstrates how a second candidate wraps inside the native list without contacting arXiv.",
                pdfURL: "https://arxiv.org/pdf/demo.00002.pdf",
                publishedAt: reference.addingTimeInterval(-3_600),
                crawledAt: reference
            ),
            Paper(
                entryID: "https://arxiv.org/abs/demo.00003",
                shortID: "demo.00003",
                title: "Evaluating Spatial Grounding Under Distribution Shift",
                authors: ["A. Choi", "S. Morgan", "L. Han"],
                subjects: ["cs.CV", "cs.AI"],
                abstract: "This example candidate exists only for visual verification of filtering, selection, and detail layout.",
                pdfURL: "https://arxiv.org/pdf/demo.00003.pdf",
                publishedAt: reference.addingTimeInterval(-7_200),
                crawledAt: reference
            )
        ]
    }
}
