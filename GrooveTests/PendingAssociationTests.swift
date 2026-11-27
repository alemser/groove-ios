import XCTest
@testable import Groove

/// The context line of a pending association, as groove-catalog's queue
/// hands it over (`docs/contracts.md` there).
final class PendingAssociationTests: XCTestCase {
    private func decode(_ json: String) throws -> PendingAssociation {
        try APIClient.decoder.decode(PendingAssociation.self, from: Data(json.utf8))
    }

    /// groove-identity #101: a disc swap inside the programme's carryover.
    func testDifferentRecordNamesTheRecordThatWasPlaying() throws {
        let item = try decode("""
        {"listener_epoch": 446, "suggested_track_id": 183,
         "suggestion": {"source": "acrcloud", "reason": "different_record", "title": "Chant Down Babylon",
                        "track_id": 183, "session_artist": "Pink Floyd", "session_album": "The Division Bell"}}
        """)
        XCTAssertEqual(item.contextLabel, "Was playing Pink Floyd – The Division Bell. This sounds like another record.")
        XCTAssertTrue(PendingAssociation.contextReasons.contains("different_record"))
    }

    func testDifferentRecordWithoutSessionNames() throws {
        let item = try decode(#"{"listener_epoch": 7, "suggestion": {"reason": "different_record"}}"#)
        XCTAssertEqual(item.contextLabel, "This sounds like another record.")
    }

    func testExpectedNextKeepsItsLine() throws {
        let item = try decode(#"{"listener_epoch": 8, "suggestion": {"reason": "expected_next_track"}}"#)
        XCTAssertEqual(item.contextLabel, "During known play: expected next track in album")
    }
}
