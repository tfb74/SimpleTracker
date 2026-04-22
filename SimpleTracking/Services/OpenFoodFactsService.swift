import Foundation

struct OFFProduct {
    let name: String
    let brand: String?
    let kcalPer100g: Double
    let carbsPer100g: Double
    let barcode: String
}

enum OFFError: Error { case notFound, network, parse }

/// Simple wrapper around the public Open Food Facts API.
/// No key required. Respectful User-Agent as required by their terms.
struct OpenFoodFactsService {
    private static let userAgent = "SimpleTracking/1.0 (iOS)"

    static func lookup(barcode: String) async throws -> OFFProduct {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,nutriments,code") else {
            throw OFFError.network
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OFFError.parse
        }
        guard let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any] else {
            throw OFFError.notFound
        }

        let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces)
        let brand = (product["brands"] as? String)?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let kcal = doubleValue(nutriments["energy-kcal_100g"]) ?? kcalFromKJ(nutriments["energy_100g"])
        let carbs = doubleValue(nutriments["carbohydrates_100g"]) ?? 0

        guard let displayName = name, !displayName.isEmpty else {
            throw OFFError.parse
        }

        return OFFProduct(
            name: displayName,
            brand: brand,
            kcalPer100g: kcal ?? 0,
            carbsPer100g: carbs,
            barcode: barcode
        )
    }

    private static func doubleValue(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func kcalFromKJ(_ v: Any?) -> Double? {
        guard let kj = doubleValue(v) else { return nil }
        return kj / 4.184
    }
}
