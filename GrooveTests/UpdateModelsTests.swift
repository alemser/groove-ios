import XCTest
@testable import Groove

/// The board-update status as groove-catalog forwards it from groove-updater
/// (`docs/contracts.md` there), and what the app shows for it.
final class UpdateModelsTests: XCTestCase {
    /// The status example of groove-updater's `docs/contracts.md`, verbatim.
    private let contractExample = """
    {
      "preference": "ask_first",
      "phase": "waiting_for_idle",
      "installed": {
        "release": "2026.12.1",
        "components": [{"name": "groove-catalog", "version": "a1b2c3d"}]
      },
      "available": {
        "release": "2026.12.2",
        "published_at": "2026-12-14T10:00:00Z",
        "notes": "Fixes the screen staying dim after Bluetooth pauses.",
        "security": false,
        "components": ["groove-display"]
      },
      "approved_release": "2026.12.2",
      "last_check": {"at": "2026-12-14T11:02:00Z", "error": ""},
      "last_result": {
        "release": "2026.12.1",
        "outcome": "installed",
        "at": "2026-12-01T02:14:00Z",
        "notes": "…",
        "error": ""
      }
    }
    """

    private func decode(_ json: String) throws -> UpdateStatus {
        try APIClient.decoder.decode(UpdateStatus.self, from: Data(json.utf8))
    }

    /// A status built from the contract example, then changed where a case needs it.
    private func status(_ change: (inout UpdateStatus) -> Void = { _ in }) throws -> UpdateStatus {
        var s = try decode(contractExample)
        change(&s)
        return s
    }

    private let available = UpdateStatus.AvailableRelease(release: "2026.12.2", notes: "Fixes the dim screen.", security: true)

    private func result(_ outcome: UpdateOutcome, release: String = "2026.12.2") -> UpdateStatus.UpdateResult {
        UpdateStatus.UpdateResult(release: release, outcome: outcome, at: "2026-12-15T02:00:00Z", notes: "Notes.")
    }

    // MARK: Decoding

    func testDecodesTheContractExample() throws {
        let s = try decode(contractExample)
        XCTAssertEqual(s.preference, .askFirst)
        XCTAssertEqual(s.phase, .waitingForIdle)
        XCTAssertEqual(s.installed.release, "2026.12.1")
        XCTAssertEqual(s.available?.release, "2026.12.2")
        XCTAssertEqual(s.available?.notes, "Fixes the screen staying dim after Bluetooth pauses.")
        XCTAssertEqual(s.available?.security, false)
        XCTAssertEqual(s.approvedRelease, "2026.12.2")
        XCTAssertEqual(s.lastCheck?.at, "2026-12-14T11:02:00Z")
        XCTAssertEqual(s.lastResult?.outcome, .installed)
    }

    func testDecodesNullsBeforeTheFirstCheckAndInstall() throws {
        let s = try decode("""
        {"preference": "unset", "phase": "idle", "installed": {"release": "", "components": []},
         "available": null, "approved_release": "", "last_check": null, "last_result": null}
        """)
        XCTAssertEqual(s.preference, .unset)
        XCTAssertNil(s.available)
        XCTAssertNil(s.lastCheck)
        XCTAssertNil(s.lastResult)
        XCTAssertEqual(s.installedLabel, "Not a release")
    }

    /// A newer board may add fields and values: the answer still decodes.
    func testUnknownFieldsAndValuesDecodeAsUnknown() throws {
        let s = try decode("""
        {"preference": "scheduled", "phase": "rebooting", "channel": "beta",
         "installed": {"release": "2026.12.1", "kernel": "6.18"},
         "available": null, "approved_release": "", "last_check": null,
         "last_result": {"release": "2026.12.1", "outcome": "partially_installed", "at": "2026-12-01T02:14:00Z", "notes": "", "error": ""}}
        """)
        XCTAssertEqual(s.preference, .unknown)
        XCTAssertEqual(s.phase, .unknown)
        XCTAssertEqual(s.lastResult?.outcome, .unknown)
        XCTAssertFalse(s.isChanging)
    }

    func testPreferenceEncodesItsWireValue() throws {
        let data = try JSONEncoder().encode(["preference": UpdatePreference.askFirst])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"preference":"ask_first"}"#)
    }

    /// The level band shares the unknown-tolerant decoding.
    func testCaptureLevelBandStillDecodesUnknownValues() throws {
        let bands = try APIClient.decoder.decode([CaptureLevelBand].self, from: Data(#"["too_low", "deafening"]"#.utf8))
        XCTAssertEqual(bands, [.tooLow, .unknown])
    }

    // MARK: Settings status line

    func testStatusLine() throws {
        let cases: [(String, (inout UpdateStatus) -> Void, String)] = [
            ("downloading", { $0.phase = .downloading }, "Updating…"),
            ("installing", { $0.phase = .installing }, "Updating…"),
            ("verifying", { $0.phase = .verifying }, "Updating…"),
            ("rolling back", { $0.phase = .rollingBack }, "Updating…"),
            ("approved, waiting for idle", { $0.phase = .waitingForIdle }, "Will install when the record ends"),
            ("available, not approved", { $0.phase = .idle; $0.approvedRelease = "" }, "Available: 2026.12.2"),
            ("automatic, waiting for the night", { $0.preference = .automatic; $0.approvedRelease = "" }, "Available: 2026.12.2"),
            ("installed the running release", { s in
                s.phase = .idle; s.approvedRelease = ""; s.available = nil
            }, "Updated to 2026.12.1"),
            ("rolled back", { s in
                s.phase = .idle; s.approvedRelease = ""; s.available = nil; s.lastResult = self.result(.rolledBack)
            }, "Update to 2026.12.2 failed; the previous version is running"),
            ("failed", { s in
                s.phase = .idle; s.approvedRelease = ""; s.available = nil; s.lastResult = self.result(.failed)
            }, "Update to 2026.12.2 failed; the previous version is running"),
            ("never installed", { s in
                s.phase = .idle; s.approvedRelease = ""; s.available = nil; s.lastResult = nil
            }, "Up to date"),
            ("never checked", { s in
                s.phase = .idle; s.approvedRelease = ""; s.available = nil; s.lastResult = nil; s.lastCheck = nil
            }, "Not checked yet"),
        ]
        for (name, change, line) in cases {
            XCTAssertEqual(try status(change).statusLine, line, name)
        }
    }

    // MARK: Actions and polling

    func testUpdateNowAndCancelApplyAtTheRightTimes() throws {
        let offered = try status { $0.phase = .idle; $0.approvedRelease = "" }
        XCTAssertTrue(offered.canApprove)
        XCTAssertFalse(offered.isWaitingToInstall)

        let approved = try status()
        XCTAssertFalse(approved.canApprove)
        XCTAssertTrue(approved.isWaitingToInstall)

        let installing = try status { $0.phase = .installing }
        XCTAssertFalse(installing.canApprove)
        XCTAssertFalse(installing.isWaitingToInstall, "the approval can't be withdrawn once the install started")

        let unanswered = try status { $0.preference = .unset; $0.phase = .idle; $0.approvedRelease = "" }
        XCTAssertFalse(unanswered.canApprove)
    }

    func testPollsOnlyWhileTheStatusChangesOnItsOwn() throws {
        XCTAssertTrue(try status().isChanging, "approved, waiting for idle")
        XCTAssertTrue(try status { $0.phase = .verifying }.isChanging)
        XCTAssertTrue(try status { $0.phase = .checking; $0.approvedRelease = "" }.isChanging)
        XCTAssertFalse(try status { $0.phase = .idle; $0.approvedRelease = "" }.isChanging)
        XCTAssertFalse(try status { $0.phase = .waitingForIdle; $0.approvedRelease = "" }.isChanging,
                       "automatic mode waiting for the night changes over hours, not seconds")
    }

    // MARK: Notices

    private let nothingSeen = UpdateNoticeMemory()

    func testAsksTheQuestionWhileUnset() throws {
        let s = try status { $0.preference = .unset; $0.lastResult = nil }
        XCTAssertEqual(UpdateNotice.next(for: s, seen: nothingSeen, questionDeferred: false), .question)
        XCTAssertNil(UpdateNotice.next(for: s, seen: nothingSeen, questionDeferred: true))
    }

    func testOffersAnAvailableReleaseInAskFirstModeUntilLater() throws {
        let s = try status { s in
            s.phase = .idle; s.approvedRelease = ""; s.available = self.available; s.lastResult = nil
        }
        XCTAssertEqual(
            UpdateNotice.next(for: s, seen: nothingSeen, questionDeferred: false),
            .available(release: "2026.12.2", notes: "Fixes the dim screen.", security: true)
        )
        XCTAssertNil(UpdateNotice.next(for: s, seen: UpdateNoticeMemory(dismissedRelease: "2026.12.2"), questionDeferred: false))

        var newer = s
        newer.available?.release = "2026.12.3"
        XCTAssertEqual(
            UpdateNotice.next(for: newer, seen: UpdateNoticeMemory(dismissedRelease: "2026.12.2"), questionDeferred: false)?.id,
            "available-2026.12.3",
            "Later holds for one release only"
        )
    }

    func testNoAvailableNoticeOnceApprovedOrInAutomaticMode() throws {
        let approved = try status { $0.lastResult = nil }
        XCTAssertNil(UpdateNotice.next(for: approved, seen: nothingSeen, questionDeferred: false))

        let automatic = try status { s in
            s.preference = .automatic; s.phase = .idle; s.approvedRelease = ""; s.lastResult = nil
        }
        XCTAssertNil(UpdateNotice.next(for: automatic, seen: nothingSeen, questionDeferred: false))
    }

    func testTellsAnInstallsOutcomeOnce() throws {
        let installed = try status { s in
            s.preference = .automatic; s.available = nil; s.approvedRelease = ""; s.lastResult = self.result(.installed)
        }
        XCTAssertEqual(
            UpdateNotice.next(for: installed, seen: nothingSeen, questionDeferred: false),
            .installed(release: "2026.12.2", notes: "Notes.")
        )
        XCTAssertNil(UpdateNotice.next(
            for: installed, seen: UpdateNoticeMemory(acknowledgedResult: installed.lastResult?.key), questionDeferred: false
        ))

        for outcome in [UpdateOutcome.rolledBack, .failed] {
            let failed = try status { s in
                s.available = nil; s.approvedRelease = ""; s.lastResult = self.result(outcome)
            }
            let notice = UpdateNotice.next(for: failed, seen: nothingSeen, questionDeferred: false)
            XCTAssertEqual(notice, .failed(release: "2026.12.2"))
            XCTAssertEqual(notice?.message, "The update to 2026.12.2 didn't work; the previous version is running.")
        }
    }

    func testTheOutcomeComesBeforeTheNextAvailableRelease() throws {
        let s = try status { s in
            s.phase = .idle; s.approvedRelease = ""; s.available = self.available; s.lastResult = self.result(.installed, release: "2026.12.1")
        }
        XCTAssertEqual(UpdateNotice.next(for: s, seen: nothingSeen, questionDeferred: false)?.id, "installed-2026.12.1")
        let acknowledged = UpdateNoticeMemory(acknowledgedResult: s.lastResult?.key)
        XCTAssertEqual(UpdateNotice.next(for: s, seen: acknowledged, questionDeferred: false)?.id, "available-2026.12.2")
    }

    // MARK: A board without the update service

    func testOnlyMissingRoutesAndAnUnreachableUpdaterHideUpdates() {
        for code in [404, 502, 503] {
            XCTAssertTrue(APIError.http(status: code, body: "").meansNoUpdater, "\(code)")
        }
        XCTAssertFalse(APIError.http(status: 409, body: #"{"error": "release is not the available one"}"#).meansNoUpdater)
        XCTAssertFalse(APIError.http(status: 500, body: "").meansNoUpdater)
        XCTAssertFalse(APIError.unanswered.meansNoUpdater)
    }
}
