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
