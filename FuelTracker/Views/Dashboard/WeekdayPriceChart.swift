import SwiftUI
import Charts

/// Average price per gallon by day of the week. A dot plot with a zoomed
/// axis: gas is never $0, and a zero-based bar would bury the cent-level
/// differences that are the whole point — while a truncated bar would
/// exaggerate them. The cheapest day is highlighted.
struct WeekdayPriceChart: View {
    let prices: [WeekdayPrice]
    let cheapestWeekday: Int?

    var body: some View {
        Chart(prices) { day in
            PointMark(
                x: .value("Day", day.symbol),
                y: .value("Price", day.averagePrice)
            )
            .foregroundStyle(color(for: day))
            .symbolSize(day.weekday == cheapestWeekday ? 160 : 90)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(Format.plainCurrency(price))
                    }
                }
            }
        }
    }

    private func color(for day: WeekdayPrice) -> Color {
        day.weekday == cheapestWeekday ? .green : Metric.price.color
    }
}
