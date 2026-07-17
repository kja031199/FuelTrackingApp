import SwiftUI

/// The app's dashboard metrics and their fixed colors.
///
/// Color follows the metric everywhere — KPI tiles and charts, iPhone and
/// watch — so a reader can connect "blue" to fuel economy across screens.
enum Metric {
    case economy
    case price
    case spending
    case distance

    var color: Color {
        switch self {
        case .economy: .blue
        case .price: .orange
        case .spending: .purple
        case .distance: .teal
        }
    }
}
