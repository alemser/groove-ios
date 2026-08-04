import Foundation

// MARK: - Stylus (wire models for /catalog/stylus*)

struct StylusCatalogItem: Decodable, Identifiable, Hashable {
    var id: Int64
    var brand: String
    var model: String
    var stylusProfile: String
    var minHours: Int?
    var maxHours: Int?
    var recommendedHours: Int
    var confidence: String

    var displayLabel: String { "\(brand) \(model)" }
    var hoursLabel: String { "\(stylusProfile) · ~\(recommendedHours)h" }
}

struct StylusCatalogResponse: Decodable {
    var items: [StylusCatalogItem]
}

struct StylusProfile: Decodable {
    var id: Int64
    var catalogId: Int64?
    var brand: String
    var model: String
    var stylusProfile: String
    var lifetimeHours: Int
    var initialUsedHours: Double
    var installedAt: String
    var isCustom: Bool
}

struct StylusMetrics: Decodable {
    var vinylHoursSinceInstall: Double
    var stylusHoursTotal: Double
    var remainingHours: Double
    var wearPercent: Double
    var state: String
}

struct StylusState: Decodable {
    var active: Bool
    var profile: StylusProfile?
    var metrics: StylusMetrics
}

/// Shared body for both `PUT /catalog/stylus` (register/update) and
/// `POST /catalog/stylus/replace` — the backend request structs are
/// field-for-field identical.
struct StylusSaveRequest: Encodable {
    var catalogId: Int64?
    var brand: String?
    var model: String?
    var stylusProfile: String?
    var lifetimeHours: Int?
    var initialUsedHours: Double?
    var isNew: Bool?
}
