import XCTest
import SwiftUI
@testable import MDEdit

/// Bug: "in the preview there is no spacing between the headings". A heading in the middle of a note, H1 above all,
/// must have clearly more room above it than below it, whatever block comes before.
@MainActor
final class ViewerSpacingTests: XCTestCase {
    private let templates: [ViewerStyle.Template] = [.serif, .sans]
    private func heading(_ n: Int) -> VBlock { .heading(n, AttributedString("Title")) }
    private func para() -> VBlock { .paragraph(AttributedString("Text")) }

    private func others() -> [(String, VBlock)] {
        [("paragraph", para()),
         ("list", .list(ordered: false, start: 1, items: [VItem(checkbox: false, blocks: [para()])])),
         ("table", .table(header: [AttributedString("a")], aligns: [nil], rows: [[AttributedString("b")]])),
         ("code", .code("x", language: nil)),
         ("quote", .quote([para()])),
         ("rule", .rule),
         ("image", .image(src: "a.png", alt: "")),
         ("properties", .properties([VProperty(key: "k", value: .text(AttributedString("v")))])),
         ("heading1", heading(1)), ("heading2", heading(2)), ("heading3", heading(3))]
    }

    func testHeadingHasRoomAboveItAfterEveryBlockType() {
        for t in templates {
            let s = ViewerStyle(template: t, serifBody: 20)
            for level in 1...4 {
                let h = heading(level), size = s.heading(level).size
                for (name, prev) in others() {
                    let above = BlockList.gap(between: prev, and: h, style: s, textSize: nil)
                    XCTAssertGreaterThanOrEqual(above, size * 1.2, "\(t) H\(level) after \(name): gap above \(above) < 1.2 em of \(size)")
                    // and clearly more than the gap to whatever follows
                    for (nextName, next) in others() where !nextName.hasPrefix("heading") && nextName != "rule" {   // a following heading or rule brings its own space
                        let below = BlockList.gap(between: h, and: next, style: s, textSize: nil)
                        XCTAssertGreaterThan(above, below * 1.2, "\(t) H\(level): above (after \(name)) \(above) not clearly more than below (before \(nextName)) \(below)")
                    }
                }
            }
        }
    }

    func testH1MidNoteGetsAtLeastAsMuchAsH2() {
        for t in templates {
            let s = ViewerStyle(template: t, serifBody: 20)
            XCTAssertGreaterThanOrEqual(BlockList.gap(between: para(), and: heading(1), style: s, textSize: nil),
                                        BlockList.gap(between: para(), and: heading(2), style: s, textSize: nil), "\(t)")
        }
    }

    func testH2AndH3KeepTheirSpecSpacing() {
        let s = ViewerStyle(template: .serif, serifBody: 20)
        XCTAssertEqual(BlockList.gap(between: para(), and: heading(2), style: s, textSize: nil), 26 * 1.7, accuracy: 0.01)
        XCTAssertEqual(BlockList.gap(between: para(), and: heading(3), style: s, textSize: nil), 20 * 1.5, accuracy: 0.01)
    }
}
