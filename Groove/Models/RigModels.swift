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
    /// Set when the profile has remote tone control.
    var tone: RigToneStatus?
}

/// `active`/`activeUntil` are set while the amp is in bass/treble mode
/// (Volume ± adjusts that control; groove-rig holds volume presses).
struct RigToneStatus: Decodable {
    var mode: String
    var active: String?
    var activeUntil: String?
}

/// How this amplifier's remote adjusts bass/treble (profile `tone`).
struct RigToneConfig: Codable, Hashable {
    var mode: String
    var settleMs: Int?
    var timeoutMs: Int?
}

struct RigToneRequest: Encodable {
    var control: String
    var direction: String
}

struct RigTargetActionStatus: Decodable {
    var learned: Bool
    var learnedAt: String?
    /// Works through the amplifier profile's shipped code (nothing learned
    /// locally). Re-learning replaces it locally.
    var builtin: Bool?
    /// The profile ships a code for this button, even if a local one
    /// overrides it — forgetting the local code falls back to it, and the
    /// button can't be removed.
    var builtinAvailable: Bool?
}

/// Optional where groove-rig can omit/null a field: this decodes inside the
/// one `/status` snapshot every learned flag comes from, so a single
/// unexpected null used to fail the whole decode — and the remote then hid
/// every button as "not learned" (a passive turntable's
/// `"capabilities": null` did exactly that).
struct RigTargetStatus: Decodable, Identifiable {
    var id: String
    var label: String
    var backend: String?
    var capabilities: [String]?
    var actions: [String: RigTargetActionStatus]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? id
        backend = try c.decodeIfPresent(String.self, forKey: .backend)
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities)
        actions = try c.decodeIfPresent([String: RigTargetActionStatus].self, forKey: .actions) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, backend, capabilities, actions
    }
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

// MARK: - Rules (GET/POST /rig/rules, PATCH/DELETE /rig/rules/{id})

/// The event a rule waits for. A struct, not an enum, so a trigger a newer
/// rig adds still decodes here (shown by its raw value).
struct RigRuleTrigger: RawRepresentable, Codable, Hashable {
    var rawValue: String
    /// An AirPlay or Bluetooth session starts.
    static let streamingStarted = RigRuleTrigger(rawValue: "streaming_started")
}

/// What a rule does when it fires; same decoding reasoning as the trigger.
struct RigRuleAction: RawRepresentable, Codable, Hashable {
    var rawValue: String
    /// Power the amplifier on if it reads off, then select `inputId`.
    static let selectInput = RigRuleAction(rawValue: "select_input")
}

/// A rule's latest firing since groove-rig started.
struct RigRuleRun: Decodable, Hashable {
    var at: String
    var source: String
    /// Amplifier power state after the power step.
    var power: String?
    var powerError: String?
    /// Input selection failure; nil when the input was selected.
    var error: String?
}

struct RigRule: Decodable, Identifiable, Hashable {
    var id: String
    var enabled: Bool
    var when: RigRuleTrigger
    var then: RigRuleAction
    var inputId: String?
    var inputLabel: String?
    /// The action can run now (the amplifier is remote-controlled and can
    /// reach the input); `unavailableReason` says why not.
    var available: Bool
    var unavailableReason: String?
    var lastRun: RigRuleRun?
}

struct RigRuleListResponse: Decodable {
    var items: [RigRule]
}

struct RigRuleCreateRequest: Encodable {
    var when: RigRuleTrigger
    var then: RigRuleAction
    var inputId: String
}

/// nil fields are left as they are.
struct RigRulePatchRequest: Encodable {
    var enabled: Bool?
    var inputId: String?
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
    /// Resolved display name for every entry in `actions` (custom label →
    /// server vocabulary → title-cased id). Use `label(for:)`.
    var actionLabels: [String: String]?
    /// The equipment template it was created from, if any — drives which
    /// buttons are suggested ("Common on CD player remotes").
    var templateId: String?
    /// The built-in model (GET /rig/equipment/models) whose IR codes this
    /// equipment ships with — its buttons work without being taught.
    var modelId: String?
    /// Wiring per amplifier profile id; `inputIds` is the active one's.
    var inputsByProfile: [String: [String]]?

    func label(for action: String) -> String {
        if ["power_toggle", "power_on", "power_off"].contains(action) { return "Power" }
        return actionLabels?[action] ?? action.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct RigEquipmentListResponse: Decodable {
    var items: [RigEquipmentItem]
}

// MARK: - Button vocabulary, equipment templates (GET /rig/actions, /rig/equipment/templates)

/// A well-known remote button. `icon` is an SF Symbol name.
struct RigActionDef: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var group: String
    var icon: String?
}

struct RigActionVocabulary: Decodable {
    var groups: [String]
    var items: [RigActionDef]
}

/// A starting point for new equipment: IR can't report which buttons a
/// remote has, so this is the "typical" set plus optional extras.
struct RigEquipmentTemplate: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
    var role: String
    var physicalFormat: String
    var hasRemote: Bool
    var actions: [String]
    var optionalActions: [String]
}

struct RigEquipmentTemplateList: Decodable {
    var items: [RigEquipmentTemplate]
}

/// A built-in make/model whose remote's IR codes groove-rig ships, so the
/// equipment works without its remote (GET /rig/equipment/models).
/// `actions` are the buttons it has codes for; `defaultActions` the
/// standard ones registered when equipment is created from it — the rest
/// are offered in Add Button, ready to use without teaching.
struct RigEquipmentModel: Decodable, Identifiable, Hashable {
    var id: String
    var maker: String
    var model: String
    var label: String
    var templateId: String
    var actions: [String]
    var defaultActions: [String]?
}

struct RigEquipmentModelList: Decodable {
    var items: [RigEquipmentModel]
}

struct RigEquipmentActionRequest: Encodable {
    var label: String
}

/// Registers a vocabulary button by id (POST /rig/equipment/{id}/actions),
/// without learning it — for buttons a built-in model ships codes for.
struct RigEquipmentAddActionRequest: Encodable {
    var id: String
}

// MARK: - Remote layout (GET/PUT/DELETE /rig/remote/layout)

/// One placed control. `widget` is power | input_select | volume | action;
/// `key`, `label`, `icon` are server-resolved display hints (read-only).
struct RigLayoutControl: Codable, Identifiable, Hashable {
    var widget: String
    var target: String
    var action: String?
    var span: Int
    var key: String
    var label: String
    var icon: String?
    var id: String { key }
}

struct RigLayoutPanel: Codable, Identifiable, Hashable {
    var id: String
    /// Stored override; "" means "use the target's label".
    var title: String?
    /// What to show: title, else the owning target's label.
    var label: String
    var target: String?
    var controls: [RigLayoutControl]
}

/// The remote's arrangement — the same one the web remote draws. Saving
/// sends it straight back; the server ignores the display-hint fields and
/// reads `hidden` controls by key.
struct RigRemoteLayout: Codable, Hashable {
    var version: Int
    var columns: Int
    var customised: Bool
    var panels: [RigLayoutPanel]
    var hidden: [RigLayoutControl]
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
    /// Seeds role/format and the suggested buttons (GET /rig/equipment/templates).
    var templateId: String?
    /// A built-in model: the server pre-registers the buttons it ships
    /// codes for (when `actions` is empty).
    var modelId: String? = nil
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
    /// Attach a built-in model (adds the buttons it ships codes for), or
    /// `""` to detach it (buttons stay, they just need teaching). nil
    /// leaves it unchanged.
    var modelId: String? = nil
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
    var tone: RigToneConfig?
}

/// Whether the amplifier's selected input may be read as evidence of which
/// medium is playing, when an album exists in the catalogue on more than one
/// format.
///
/// Deliberately its own endpoint rather than a field on `RigAmplifierConfig`:
/// it belongs to the installation, and activating another amplifier profile
/// replaces that config wholesale, which would silently reset the choice.
struct RigFormatHint: Codable, Hashable {
    var useAmplifierInput: Bool
}

struct RigStoredAmplifierProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var origin: String?
    var config: RigAmplifierConfig
    /// A built-in with this installation's changes applied (`config` is the
    /// effective one). "Reset to Factory Settings" clears it.
    var customised: Bool?
}

/// `POST /amplifier/profiles` for a duplicate: the source profile's config
/// under a new id, plus `copyCodesFrom` so the copy keeps the source's
/// learned IR codes and equipment wiring (same amplifier, same cabling).
struct RigProfileDuplicateRequest: Encodable {
    var id: String
    var name: String
    var origin: String = "custom"
    var config: RigAmplifierConfig
    var copyCodesFrom: String
}

struct RigProfileResetRequest: Encodable {
    var profileId: String
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
}

/// Generic ack shape shared by the profile mutation endpoints (upsert/delete/
/// activate/import) — each returns a small `{"ok": true, ...}` payload with a
/// different mix of extra keys, all optional here.
struct RigOkResponse: Decodable {
    var ok: Bool
    var profileId: String?
    var activeProfileId: String?
    var updated: Bool?
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
    /// Learn only: other buttons on the same target whose learned code is
    /// the same press as this capture — usually the wrong button pressed.
    var duplicateOf: [String]?
}

struct RigLearnRequest: Encodable {
    var backendId: String?
    var targetId: String
    /// nil with `register` + `label` = a custom button, id slugged server-side.
    var action: String?
    var timeoutSecs: Int?
    /// Add the button (with `label`) to the target only once a code is
    /// captured — cancel/timeout leaves nothing behind.
    var register: Bool?
    var label: String?
}

// MARK: - Streaming (AirPlay output device — proxied `/rig/streaming/*` →
// groove-rig → groove-detector's `/audio-outputs*`)

struct RigAudioOutput: Decodable, Identifiable, Hashable {
    var id: String
    var label: String
}

struct RigAudioOutputsResponse: Decodable {
    var selected: String
    var outputs: [RigAudioOutput]
}

struct RigSelectAudioOutputRequest: Encodable {
    var device: String
}

// MARK: - Audio input (capture level calibration — proxied `/rig/capture/*` →
// groove-rig → groove-detector's `/capture/*`)

/// Whether the recognition tap is a fixed-level output (REC OUT / Tape Out)
/// or a line / pre out that follows the amplifier's volume knob.
enum CaptureInputLevel: String, Codable {
    case fixed
    case variable
}

/// The detector's verdict on the recent programme level. Decided server-side
/// so every client agrees; an unrecognised value decodes as `.unknown`.
enum CaptureLevelBand: String, Decodable {
    case unknown
    case tooLow = "too_low"
    case low
    case good
    case high
    case clipping

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptureLevelBand(rawValue: raw) ?? .unknown
    }
}

struct CaptureLevel: Decodable {
    var inputLevel: CaptureInputLevel
    var gate: String
    /// Absent when the detector has no ALSA capture device.
    var gain: CaptureGain?
    var programme: ProgrammeLevel

    var isPlaying: Bool { gate == "programme" }
}

struct CaptureGain: Decodable, Equatable {
    var pct: Int
    var step: Int
    var maxStep: Int
    /// Absent on cards that don't report dB.
    var db: Double?
    /// dB one step adds; absent without a dB range (no preview then).
    var dbPerStep: Double?
    var control: String?
}

struct ProgrammeLevel: Decodable {
    var band: CaptureLevelBand
    /// RMS of the last ~0.5 s — the needle that follows the music.
    var liveRms: Double
    /// The step that centres the level in the good band; absent when there
    /// is nothing to suggest.
    var suggestedStep: Int?
    /// 95th percentile of frame RMS over the window, 0–1 full scale.
    var rmsP95: Double
    var peakMax: Double
    var headroomDb: Double?
    /// Programme seconds in the window; `band` stays `.unknown` below `minSeconds`.
    var seconds: Double
    var minSeconds: Double
    var windowSeconds: Double
    var target: CaptureLevelTarget
}

/// Band edges (frame-RMS P95), for drawing the meter scale.
struct CaptureLevelTarget: Decodable {
    var tooLowBelow: Double
    var lowBelow: Double
    var highAbove: Double
}

struct CaptureGainStepRequest: Encodable {
    var captureGainStep: Int
}

struct CaptureGainApplied: Decodable {
    var captureGainStep: Int
    var captureGainMaxStep: Int
    var captureGainDb: Double?
}

struct CaptureInputLevelBody: Codable {
    var inputLevel: CaptureInputLevel
}
