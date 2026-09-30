import SwiftUI
import EncoreMomentCore

/// Sign-in / sign-up form. Every account has a profile for posting events, while
/// favorites/follows sync across devices once signed in.
struct AuthView: View {
    var allowsCancel = true
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case login, register }

    @State private var mode: Mode = .login

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var handle = ""
    /// Required by App Review (guideline 1.2): users must accept the Terms of
    /// Use — which state zero tolerance for objectionable content and abusive
    /// users — before registering or logging in.
    @State private var agreedToTerms = false
    @State private var showingTerms = false

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedHandle: String {
        handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .replacingOccurrences(of: " ", with: "_")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    Text("Sign In").tag(Mode.login)
                    Text("Create Account").tag(Mode.register)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                }

                if mode == .register {
                    Section {
                        TextField("Display name", text: $displayName)
                        TextField("Handle (e.g. aurora_live)", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: handle) { newValue in
                                let cleaned = normalizeHandleInput(newValue)
                                if cleaned != newValue {
                                    handle = cleaned
                                }
                            }
                        Text(handleHelpText)
                            .font(.caption)
                            .foregroundStyle(Creator.isValidHandle(normalizedHandle) ? Color.secondary : Color.orange)
                    } header: {
                        Text("Your profile")
                    } footer: {
                        Text("Use this profile to post events, comment, follow creators, and sync your saved items.")
                    }
                }

                if let error = auth.errorMessage {
                    Section {
                        Text(error).foregroundStyle(Color.red).font(.footnote)
                    }
                }

                Section {
                    Toggle(isOn: $agreedToTerms) {
                        Text("I agree to the Terms of Use")
                    }
                    Button {
                        showingTerms = true
                    } label: {
                        Text("Read Terms of Use")
                    }
                } footer: {
                    Text("Our terms make clear there is zero tolerance for objectionable content or abusive users.")
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if auth.isWorking {
                                ProgressView()
                            } else {
                                Text(mode == .login ? "Sign In" : "Create Account").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(auth.isWorking || !isValid || !agreedToTerms)
                }
            }
            .navigationTitle(mode == .login ? "Welcome back" : "Join EncoreMoment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsCancel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showingTerms) {
                TermsView()
            }
        .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
    }

    private var isValid: Bool {
        let base = normalizedEmail.contains("@") && password.count >= 8
        if mode == .register {
            return base && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
                && Creator.isValidHandle(normalizedHandle)
        }
        return base
    }

    private var handleHelpText: String {
        if handle.isEmpty {
            return "Handle must be 3-30 characters using only letters, numbers, and underscores."
        }
        if Creator.isValidHandle(normalizedHandle) {
            return "Your handle will be @\(normalizedHandle)."
        }
        return "Use 3-30 letters, numbers, or underscores."
    }

    private func normalizeHandleInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .replacingOccurrences(of: " ", with: "_")
    }

    private func submit() {
        Task {
            let account: Account?
            switch mode {
            case .login:
                account = await auth.login(email: normalizedEmail, password: password)
            case .register:
                account = await auth.register(
                    email: normalizedEmail,
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    handle: normalizedHandle
                )
            }
            if let account {
                await model.didSignIn(account)
                dismiss()
            }
        }
    }
}
