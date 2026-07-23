import SwiftUI

/// Covers the app with a lock screen whenever ``AppLock`` is locked, and
/// re-locks when the app leaves the foreground. Applied once at the app root.
struct AppLockGate: ViewModifier {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if appLock.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                }
            }
            .animation(.default, value: appLock.isLocked)
            .onChange(of: scenePhase) { _, phase in
                // Re-arm the lock as soon as the app is no longer active, so the
                // content isn't visible in the app switcher or on return.
                if phase != .active {
                    appLock.lockOnBackground()
                }
            }
    }
}

/// The opaque lock screen. Prompts for authentication on appear and offers a
/// button to retry if the prompt is dismissed.
struct LockScreenView: View {
    @Environment(AppLock.self) private var appLock
    @State private var authenticating = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(.systemBackground))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("FuelTracker is Locked")
                    .font(.headline)
                Button {
                    Task { await attemptUnlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authenticating)
            }
            .padding()
        }
        .task { await attemptUnlock() }
    }

    private func attemptUnlock() async {
        guard !authenticating else { return }
        authenticating = true
        await appLock.unlock()
        authenticating = false
    }
}
