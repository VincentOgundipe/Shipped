import SwiftUI
import AuthenticationServices

/// Tracks the stored identity. Persisted in the App Group so the Mac app can recognise the
/// same person once CloudKit sync lands.
@Observable
final class AuthState {
    private static let userIDKey = "authUserID"
    private static let providerKey = "authProvider"
    private static let nameKey = "authDisplayName"

    var userID: String? {
        didSet { AppSettings.defaults.set(userID, forKey: Self.userIDKey) }
    }
    var provider: AuthProvider? {
        didSet { AppSettings.defaults.set(provider?.rawValue, forKey: Self.providerKey) }
    }
    var displayName: String? {
        didSet { AppSettings.defaults.set(displayName, forKey: Self.nameKey) }
    }

    var isSignedIn: Bool { userID?.isEmpty == false }

    init() {
        userID = AppSettings.defaults.string(forKey: Self.userIDKey)
        provider = AppSettings.defaults.string(forKey: Self.providerKey).flatMap(AuthProvider.init)
        displayName = AppSettings.defaults.string(forKey: Self.nameKey)
    }

    func signIn(id: String, provider: AuthProvider, name: String?) {
        if let name, !name.isEmpty { displayName = name }
        self.provider = provider
        userID = id
    }

    func signOut() {
        userID = nil
        provider = nil
        displayName = nil
    }
}

struct SignInView: View {
    @Environment(\.themePalette) private var palette
    var auth: AuthState

    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var showEmailEntry = false
    @State private var email = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground(palette: palette)
            if palette.isDark { GrainOverlay(opacity: 0.045) }

            VStack(spacing: 0) {
                Spacer()

                AnimatedMarkView(palette: palette, visible: appeared)
                    .frame(width: 104, height: 104)

                VStack(spacing: 10) {
                    Text("Shipped")
                        .displayStyle(palette, size: 42)
                    Text("Say what you're chasing.\nGet told what to do today.")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.top, 26)
                .staggeredEntrance(index: 6, visible: appeared)

                Spacer()

                if showEmailEntry {
                    emailEntry
                } else {
                    providerButtons
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.accentSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                Text("Your plan stays on your devices. Nothing is uploaded to a server we run.")
                    .font(.system(size: TypeScale.label))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                    .staggeredEntrance(index: 11, visible: appeared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear { appeared = true }
    }

    // MARK: - Providers

    private var providerButtons: some View {
        VStack(spacing: 12) {
            Button {
                signInWithGoogle()
            } label: {
                HStack(spacing: 10) {
                    GoogleGlyph()
                    Text("Continue with Google")
                        .font(.system(size: TypeScale.body, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.isDark ? Color.white : Color.white)
                .foregroundStyle(Color.black.opacity(0.82))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(palette.isDark ? 0 : 0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .staggeredEntrance(index: 9, visible: appeared)

            Button {
                withAnimation(Motion.settle) {
                    errorMessage = nil
                    showEmailEntry = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: TypeScale.body))
                    Text("Continue with email")
                        .font(.system(size: TypeScale.body, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(palette.text)
                .background(palette.surfaceRaised)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(palette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .staggeredEntrance(index: 10, visible: appeared)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Email

    private var emailEntry: some View {
        VStack(spacing: 12) {
            TextField("you@example.com", text: $email)
                .textFieldStyle(ShippedTextFieldStyle(palette: palette))
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()

            Text("No password — this identifies you on this device only, until cloud sync is added.")
                .font(.system(size: TypeScale.label))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)

            Button("Continue") {
                let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard trimmed.contains("@"), trimmed.count > 3 else {
                    errorMessage = "That doesn't look like an email address."
                    return
                }
                withAnimation(Motion.settle) {
                    auth.signIn(id: "email:\(trimmed)", provider: .email, name: nil)
                }
            }
            .buttonStyle(FilledPillButtonStyle(
                palette: palette,
                isDisabled: !email.contains("@")
            ))
            .disabled(!email.contains("@"))

            Button("Back") {
                withAnimation(Motion.settle) {
                    showEmailEntry = false
                    errorMessage = nil
                }
            }
            .buttonStyle(OutlinePillButtonStyle(palette: palette))
        }
        .padding(.horizontal, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Handlers

    private func signInWithGoogle() {
        errorMessage = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await GoogleAuth.signIn(presentationAnchor: nil)
                withAnimation(Motion.settle) {
                    auth.signIn(id: "google:\(result.id)", provider: .google, name: result.email)
                }
            } catch AuthError.cancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Google's four-color G, drawn rather than bundled as an asset.
private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(Color(hex: 0xea4335), lineWidth: 4)
                .rotationEffect(.degrees(-135))
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(Color(hex: 0xfbbc05), lineWidth: 4)
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0.0, to: 0.25)
                .stroke(Color(hex: 0x34a853), lineWidth: 4)
                .rotationEffect(.degrees(45))
            Circle()
                .trim(from: 0.0, to: 0.22)
                .stroke(Color(hex: 0x4285f4), lineWidth: 4)
                .rotationEffect(.degrees(-30))
            Rectangle()
                .fill(Color(hex: 0x4285f4))
                .frame(width: 8, height: 4)
                .offset(x: 4, y: 0)
        }
        .frame(width: 18, height: 18)
    }
}

/// The app's mark — a 4×4 grid that fills in, echoing the progress widget.
struct AnimatedMarkView: View {
    let palette: ThemePalette
    let visible: Bool

    private let filled: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        let isFilled = filled.contains(index)
                        let isCursor = index == 10

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isFilled ? palette.accent
                                    : isCursor ? palette.accentSecondary.opacity(0.25)
                                    : palette.border.opacity(0.5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isCursor ? palette.accentSecondary : .clear, lineWidth: 2)
                            )
                            .scaleEffect(visible ? 1 : 0.3)
                            .opacity(visible ? 1 : 0)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.03),
                                value: visible
                            )
                    }
                }
            }
        }
    }
}
