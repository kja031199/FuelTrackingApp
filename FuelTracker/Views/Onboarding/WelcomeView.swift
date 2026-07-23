import SwiftUI
import SwiftData

/// First-run experience: a short welcome, then a guided path to add the first
/// vehicle and log the first fill-up — both reusing the real forms (and their
/// validation). Skippable at any point; the caller persists completion so it
/// never shows again.
struct WelcomeView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    /// Called when the user finishes or skips. The caller records completion and
    /// dismisses.
    let onFinish: () -> Void

    @State private var showingVehicleForm = false
    @State private var showingFillUpForm = false

    private var hasVehicle: Bool { !vehicles.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    features
                    actions
                        .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { onFinish() }
                }
            }
            .sheet(isPresented: $showingVehicleForm) {
                AddEditVehicleView()
            }
            .sheet(isPresented: $showingFillUpForm, onDismiss: onFinish) {
                AddEditFillUpView(defaultVehicle: vehicles.first)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome to FuelTracker")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Log your fill-ups and see your real fuel economy and cost — all on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            feature("gauge.with.dots.needle.67percent", "Track MPG & cost",
                    "See your fuel economy and spending trends after a couple of fill-ups.")
            feature("camera.viewfinder", "Scan the pump",
                    "Point your camera at the pump or a receipt to fill in the numbers.")
            feature("lock.fill", "Private by default",
                    "Everything stays on your device. No account, no tracking.")
        }
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        if hasVehicle {
            VStack(spacing: 12) {
                Label("Vehicle added", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Now log your first fill-up to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingFillUpForm = true
                } label: {
                    Text("Log Your First Fill-Up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Not now") { onFinish() }
            }
        } else {
            Button {
                showingVehicleForm = true
            } label: {
                Text("Add Your First Vehicle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview {
    WelcomeView(onFinish: {})
        .modelContainer(ModelContainerFactory.makeInMemory())
        .environment(UnitSettings())
        .environment(PrivacySettings())
}
