import XCTest
@testable import Groove

/// The context line of a pending association: groove-catalog words it once
/// (`context_label`, its `domain.PendingContextLabel`) and the review row
/// shows it as is.
final class PendingAssociationTests: XCTestCase {
    private func decode(_ json: String) throws -> PendingAssociation {
        try APIClient.decoder.decode(PendingAssociation.self, from: Data(json.utf8))
    }

    /// groove-identity #101: a disc swap inside the programme's carryover.
    func testContextLabelComesFromTheQueue() throws {
        let item = try decode("""
        {"listener_epoch": 446, "suggested_track_id": 183,
         "suggestion": {"source": "acrcloud", "reason": "different_record", "title": "Chant Down Babylon", "track_id": 183},
         "context_label": "Was playing Pink Floyd – The Division Bell. This sounds like another record."}
        """)
        XCTAssertEqual(item.contextLabel, "Was playing Pink Floyd – The Division Bell. This sounds like another record.")
    }

    func testNoContextLabelFromAnOlderCatalog() throws {
        let item = try decode(#"{"listener_epoch": 7, "suggestion": {"reason": "expected_next_track"}}"#)
        XCTAssertNil(item.contextLabel)
    }
}
