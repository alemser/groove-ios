import Foundation

/// Shared EAN/UPC validation — every screen that searches by barcode (typed,
/// scanned, or autodetected out of a free-text query) uses the same 8–14
/// digit rule the web studio's dedicated barcode field applies, so a query
/// that reads as a barcode in one place reads as one everywhere.
enum Barcode {
    /// Strips everything but digits and returns them only when the count
    /// falls in the EAN-8…14-digit GTIN range; empty otherwise.
    static func digits(from raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        return (8...14).contains(digits.count) ? digits : ""
    }
}
