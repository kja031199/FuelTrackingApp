import SwiftUI

/// A single stat tile on the dashboard.
struct KPICard: View {
    let kpi: KPI

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility text sizes let the text wrap and grow (the grid
        // drops to one column to give it room). At normal sizes keep the tidy
        // single-line tile, scaling down only slightly so long values fit.
        let accessible = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: kpi.icon)
                    .font(.caption)
                    .foregroundStyle(kpi.metric.color)
                Text(kpi.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(accessible ? nil : 1)
                    .minimumScaleFactor(accessible ? 1 : 0.8)
            }

            Text(kpi.value ?? "—")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(accessible ? nil : 1)
                .minimumScaleFactor(accessible ? 1 : 0.6)

            // Always render the detail line, using a blank placeholder when a
            // stat has none, so every card is the same height and the grid
            // reads as a tidy, uniform set of tiles.
            Text(kpi.detail ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(accessible ? nil : 1)
                .minimumScaleFactor(accessible ? 1 : 0.8)
                .opacity(kpi.detail == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kpi.accessibilityLabel)
    }
}

/// Card container that gives every chart the same framing.
struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    /// A spoken overview of the chart's data, read by VoiceOver after the
    /// title and subtitle so a non-visual user gets the trend at a glance.
    var accessibilitySummary: String? = nil
    @ViewBuilder let content: Content

    private var headerLabel: String {
        [title, subtitle, accessibilitySummary].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerLabel)

            content
                .frame(height: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
