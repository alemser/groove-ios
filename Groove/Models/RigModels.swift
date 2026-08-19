import Foundation

// MARK: - Rig (wire models for the `/rig/*` proxy → groove-rig's management API)

struct RigInputStatus: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var visible: Bool
}

struct RigPowerStatus: Decodable {
    var state: String
    var confidence: String
    var method: String?
    var rms: Double?
    var lastProbeAt: String?
    var warmingUpUntil: String?
}

struct RigAmplifierStatus: Decodable {
    var profileId: String?
    var maker: String?
    var model: String?
    var inputMode: String?
    var activeInputId: String?
    var activeInputLabel: String?
    var inputs: [RigInputStatus]?
    var power: RigPowerStatus?
}

struct RigTargetActionStatus: Decodable {
    var learned: Bool
    var learnedAt: String?
}

struct RigTargetStatus: Decodable, Identifiable {
    var id: String
    var label: String
    var backend: String
    var capabilities: [String]
    var actions: [String: RigTargetActionStatus]
}

struct RigSnapshot: Decodable {
    var schemaVersion: Int
    var targets: [RigTargetStatus]
    var amplifier: RigAmplifierStatus?
}

struct RigSelectInputRequest: Encodable {
    var inputId: String
    var currentInputId: String?
}

struct RigActiveInputRequest: Encodable {
    var inputId: String
}

// MARK: - Rig equipment (IR-controlled devices other than the amplifier)

struct RigEquipmentItem: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var backend: String?
    var actions: [String]?
    var role: String
    var physicalFormat: String
    var inputIds: [String]?
    var hasRemote: Bool
}

struct RigEquipmentListResponse: Decodable {
    var items: [RigEquipmentItem]
}

struct RigEquipmentSaveRequest: Encodable {
    var id: String?
    var label: String?
    var backend: String?
    var actions: [String]?
    var role: String?
    var physicalFormat: String?
    var inputIds: [String]?
    var hasRemote: Bool?
}

/// Edits an existing piece of equipment. Distinct from `RigEquipmentSaveRequest`
/// (create): `backend` here can be sent as `""` to explicitly clear it, so it's
/// not `omitempty`-collapsible the same way — omit the property (nil) to leave
/// a field untouched, matching the server's partial-merge semantics.
struct RigEquipmentPatchRequest: Encodable {
    var label: String?
    var backend: String?
    var actions: [String]?
    var role: String?
    var physicalFormat: String?
    var inputIds: [String]?
    var hasRemote: Bool?
}

// MARK: - Amplifier configuration (editable) and profiles

struct RigCycleConfig: Codable, Hashable {
    var armingSettleMs: Int?
    var stepNextWaitMs: Int?
    var stepPrevWaitMs: Int?
    var selectionActiveWindowMs: Int?
}

struct RigInputConfig: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var visible: Bool
    var recognitionPolicy: String?
}

/// The amplifier's own config (maker/model/timing/inputs) — distinct from
/// `RigAmplifierStatus`, which is a live runtime projection missing these
/// config-only fields. Must be fetched fresh before a `PATCH` since the
/// server merges by field-presence: an omitted field is left untouched, but
/// this struct has no way to represent "I never saw this field" once decoded,
/// so always round-trip a freshly-loaded value rather than a stale cached one.
struct RigAmplifierConfig: Codable, Hashable {
    var profileId: String?
    var maker: String?
    var model: String?
    var inputMode: String?
    var warmUpSecs: Int?
    var standbyTimeoutMins: Int?
    var cycle: RigCycleConfig?
    var inputs: [RigInputConfig]?
}

struct RigStoredAmplifierProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var origin: String?
    var config: RigAmplifierConfig
}

struct RigAmplifierProfilesResponse: Decodable {
    var activeProfileId: String
    var profiles: [RigStoredAmplifierProfile]
}

struct RigProfileExportDoc: Codable {
    var schemaVersion: String
    var profile: RigStoredAmplifierProfile
}

struct RigProfileActivateRequest: Encodable {
    var profileId: String
    /// Skips the server's unsaved-local-changes guard, overwriting the live
    /// amplifier config anyway. Only set true after the user confirms
    /// discarding those changes (see `AmplifierConfigModel.activate`).
    var force: Bool = false
}

/// Generic ack shape shared by the profile mutation endpoints (upsert/delete/
/// activate/import) — each returns a small `{"ok": true, ...}` payload with a
/// different mix of extra keys, all optional here.
struct RigOkResponse: Decodable {
    var ok: Bool
    var profileId: String?
    var activeProfileId: String?
    var updated: Bool?
    /// Set by a forced `activate` when the live config had diverged from
    /// its profile — the server auto-saves that diverged config under this
    /// new profile id before switching, so it's recoverable afterward.
    var backupProfileId: String?
}

// MARK: - Rig sessions (IR learn / pair)

struct RigSessionSummary: Decodable, Identifiable {
    var id: String
    var kind: String
    var status: String
    var backend: String?
    var targetId: String?
    var action: String?
    var message: String?
    var code: String?
}

struct RigLearnRequest: Encodable {
    var backendId: String?
    var targetId: String
    var action: String
    var timeoutSecs: Int?
}
