import Foundation

enum FuelGrade: String, CaseIterable, Identifiable, Codable {
    case regular = "Regular"
    case midgrade = "Midgrade"
    case premium = "Premium"
    case diesel = "Diesel"
    case e85 = "E85"
    case other = "Other"

    var id: String { rawValue }
}
