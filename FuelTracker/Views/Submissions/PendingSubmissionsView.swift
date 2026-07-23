import SwiftUI
import SwiftData

/// The owner's review queue: fill-ups submitted by other people, each shown in
/// full so the owner can approve it (it becomes a real fill-up, validated
/// through `FuelEntryDraft`) or dismiss it.
struct PendingSubmissionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PendingFillUp.submittedAt, order: .reverse) private var submissions: [PendingFillUp]
    @Query private var vehicles: [Vehicle]

    var body: some View {
        NavigationStack {
            Group {
                if submissions.isEmpty {
                    ContentUnavailableView(
                        "No Submissions",
                        systemImage: "tray",
                        description: Text("Fill-ups submitted by other people show up here to review before they're added to your log.")
                    )
                } else {
                    List {
                        ForEach(submissions) { submission in
                            SubmissionReviewRow(
                                submission: submission,
                                vehicle: vehicle(for: submission),
                                approve: { approve(submission) },
                                dismissSubmission: { modelContext.delete(submission) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Submissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func vehicle(for submission: PendingFillUp) -> Vehicle? {
        vehicles.first { $0.id == submission.vehicleID }
    }

    private func approve(_ submission: PendingFillUp) {
        guard let vehicle = vehicle(for: submission) else { return }
        submission.approve(onto: vehicle, in: modelContext)
    }
}

/// One submission, laid out for a decision: who sent it, which vehicle, the
/// fill-up details, and approve / dismiss actions.
private struct SubmissionReviewRow: View {
    let submission: PendingFillUp
    let vehicle: Vehicle?
    let approve: () -> Void
    let dismissSubmission: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(submission.submitterName.isEmpty ? "Someone" : submission.submitterName)
                        .font(.headline)
                    Text("for \(vehicle?.name ?? "a removed vehicle") · \(submission.submittedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if submission.hasReceipt {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Has a receipt photo")
                }
            }

            detailGrid

            if vehicle == nil {
                Label("This vehicle was removed — you can only dismiss this submission.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    dismissSubmission()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    approve()
                } label: {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vehicle == nil)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            detail("Date", submission.date.formatted(date: .abbreviated, time: .omitted))
            detail("Odometer", "\(Format.odometer(submission.odometer)) mi")
            detail("Fuel", "\(Format.gallons(submission.gallons)) gal @ \(Format.fuelPrice(submission.pricePerGallon)) = \(Format.currency(submission.totalCost))")
            if !submission.station.isEmpty {
                detail("Station", submission.station)
            }
        }
        .font(.subheadline)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
