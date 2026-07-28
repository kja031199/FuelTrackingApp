import SwiftUI
import SwiftData
import Charts

/// Head-to-head comparison of two vehicles: a verdict, a metric table with
/// the winner highlighted per row, and their MPG trends overlaid.
struct ShowdownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?
    @Environment(\.colorScheme) private var colorScheme
    let vehicles: [Vehicle]

    @State private var leftID: UUID?
    @State private var rightID: UUID?

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    private var leftVehicle: Vehicle? { vehicles.first { $0.id == leftID } }
    private var rightVehicle: Vehicle? { vehicles.first { $0.id == rightID } }

    private var showdown: VehicleShowdown? {
        guard let left = leftVehicle, let right = rightVehicle else { return nil }
        return VehicleShowdown(
            leftName: left.name, leftEntries: left.fillUps,
            rightName: right.name, rightEntries: right.fillUps,
            units: units
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let showdown {
                    content(showdown)
                } else {
                    ContentUnavailableView(
                        "Pick Two Vehicles",
                        systemImage: "car.2",
                        description: Text("Choose two vehicles to compare their fuel economy and costs side by side.")
                    )
                }
            }
            .navigationTitle("Showdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if leftID == nil { leftID = vehicles.first?.id }
                if rightID == nil { rightID = vehicles.dropFirst().first?.id ?? vehicles.first?.id }
            }
        }
    }

    private func content(_ showdown: VehicleShowdown) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if vehicles.count > 2 {
                    vehiclePickers
                }

                Text(verdict(showdown))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                nameHeader(showdown)

                VStack(spacing: 0) {
                    ForEach(Array(showdown.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        rowView(row, leftName: showdown.leftName, rightName: showdown.rightName)
                    }
                }
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if showdown.leftMPGSeries.count >= 2 || showdown.rightMPGSeries.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fuel Economy")
                            .font(.headline)
                        ShowdownMPGChart(
                            leftName: showdown.leftName,
                            rightName: showdown.rightName,
                            leftSeries: showdown.leftMPGSeries,
                            rightSeries: showdown.rightMPGSeries,
                            units: units
                        )
                        .frame(height: 220)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var vehiclePickers: some View {
        HStack {
            Picker("Left", selection: $leftID) {
                ForEach(vehicles) { Text($0.name).tag(Optional($0.id)) }
            }
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer()
            Picker("Right", selection: $rightID) {
                ForEach(vehicles) { Text($0.name).tag(Optional($0.id)) }
            }
        }
    }

    private func nameHeader(_ showdown: VehicleShowdown) -> some View {
        HStack {
            Text(showdown.leftName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(showdown.rightName)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func rowView(_ row: ShowdownRow, leftName: String, rightName: String) -> some View {
        HStack(spacing: 8) {
            valueText(row.left, highlighted: row.winner == .left, metric: row.metric)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 2) {
                Image(systemName: row.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 110)

            valueText(row.right, highlighted: row.winner == .right, metric: row.metric)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel(leftName: leftName, rightName: rightName))
    }

    private func valueText(_ value: String?, highlighted: Bool, metric: Metric) -> some View {
        Text(value ?? "—")
            .font(.callout)
            .monospacedDigit()
            .fontWeight(highlighted ? .semibold : .regular)
            .foregroundStyle(highlighted ? metric.color(in: colorScheme) : (value == nil ? Color.secondary : Color.primary))
    }

    private func verdict(_ showdown: VehicleShowdown) -> String {
        guard showdown.hasContest else {
            return "Not enough data to compare yet"
        }
        let left = showdown.leftWins
        let right = showdown.rightWins
        if left == right {
            return "Too close to call"
        }
        let leader = left > right ? showdown.leftName : showdown.rightName
        return "\(leader) leads \(max(left, right))–\(min(left, right))"
    }
}

/// Two vehicles' MPG series overlaid, with a legend. Identical names are
/// disambiguated so their lines don't merge.
struct ShowdownMPGChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let leftName: String
    let rightName: String
    let leftSeries: [DateValuePoint]
    let rightSeries: [DateValuePoint]
    var units: UnitPreferences = .us

    private var labels: (left: String, right: String) {
        leftName == rightName ? ("\(leftName) ①", "\(rightName) ②") : (leftName, rightName)
    }

    var body: some View {
        // Economy is non-linear across units, so convert the plotted values.
        let (leftLabel, rightLabel) = labels
        let leftConverted = leftSeries.mapValues { units.economy.fromMPG($0) ?? $0 }.downsampled(max: 500)
        let rightConverted = rightSeries.mapValues { units.economy.fromMPG($0) ?? $0 }.downsampled(max: 500)
        let axisLabel = units.economy.abbreviation
        Chart {
            ForEach(leftConverted) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(axisLabel, point.value),
                    series: .value("Vehicle", leftLabel)
                )
                .foregroundStyle(by: .value("Vehicle", leftLabel))
                .interpolationMethod(.monotone)
                .accessibilityLabel("\(leftLabel), \(point.date.formatted(.dateTime.month(.abbreviated).day()))")
                .accessibilityValue("\(point.value.formatted(.number.precision(.fractionLength(1)))) \(axisLabel)")
            }
            ForEach(rightConverted) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(axisLabel, point.value),
                    series: .value("Vehicle", rightLabel)
                )
                .foregroundStyle(by: .value("Vehicle", rightLabel))
                .interpolationMethod(.monotone)
                .accessibilityLabel("\(rightLabel), \(point.date.formatted(.dateTime.month(.abbreviated).day()))")
                .accessibilityValue("\(point.value.formatted(.number.precision(.fractionLength(1)))) \(axisLabel)")
            }
        }
        .chartForegroundStyleScale([
            leftLabel: AccessiblePalette.color(.blue, in: colorScheme),
            rightLabel: AccessiblePalette.color(.orange, in: colorScheme)
        ])
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(position: .bottom)
    }
}
