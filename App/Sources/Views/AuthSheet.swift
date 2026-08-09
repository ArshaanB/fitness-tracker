import SwiftUI

/// Two-step email sign-in: send a one-time code, then verify it. No passwords,
/// no deep links.
struct AuthSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(SyncModel.self) private var sync
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case email
        case code
    }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .email:
                    Text("Enter your email and we'll send a six-digit code — no password needed.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    actionButton("Send code", disabled: !email.contains("@")) {
                        try await sync.sendCode(to: email)
                        step = .code
                        code = ""
                    }
                case .code:
                    Text("Enter the code we sent to \(email).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .focused($focused)
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    actionButton("Verify & sign in", disabled: code.count < 6) {
                        try await sync.verify(email: email, code: code, appModel: model)
                        dismiss()
                    }
                    Button("Use a different email") {
                        step = .email
                        errorMessage = nil
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.ringLow)
                }
                Spacer()
            }
            .padding(20)
            .appBackground()
            .navigationTitle("Back up your training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func actionButton(_ title: String, disabled: Bool,
                              action: @escaping () async throws -> Void) -> some View {
        Button {
            busy = true
            errorMessage = nil
            Task {
                do {
                    try await action()
                } catch {
                    errorMessage = "\(error.localizedDescription)"
                }
                busy = false
            }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(disabled ? Theme.inkTertiary : Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
    }
}
