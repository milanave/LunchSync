//
//  TokenPromptView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
// 337f665be832d9e0e999248275ae4998628c7464756067e903
import SwiftUI
import SwiftData

struct TokenPromptView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var isPresented: Bool
    @Binding var apiToken: String
    let onSave: () -> Void
    let allowDismissal: Bool
    
    @State private var isVerifying = false
    @State private var isTokenValid = false
    @State private var verificationError: String?
    @State private var statusText: String = ""
    @State private var verifiedUsername: String?
    @State private var verifiedBudgetname: String?
    @State private var mirrorURLString: String = ""
    @State private var mirrorURLError: String?
    @State private var mirrorOnly: Bool = false


    private let keychain = Keychain()
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                            .padding(.bottom, 4)
                        
                        Text("LunchMoney API Token")
                            .font(.headline)
                        
                        Text("Connect to your LunchMoney account by entering your API token below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                
                Section {
                    TextEditor(text: $apiToken)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disableAutocorrection(true)
                        .onChange(of: apiToken) { _, newValue in
                            let withoutNewlines = newValue.replacingOccurrences(of: "\\R", with: "", options: .regularExpression)
                            let filtered = withoutNewlines.trimmingCharacters(in: .whitespaces)
                            if filtered != newValue {
                                apiToken = filtered
                            }
                        }
                        .onAppear {
                            UITextView.appearance().textContainer.lineBreakMode = .byTruncatingTail
                        }
                    

                } header: {
                    Text("API Token")
                } footer: {
                    if !isVerifying && !isTokenValid {
                        Link("Get your token at LunchMoney.app",
                             destination: URL(string: "https://my.lunchmoney.app/developers")!)
                            .font(.footnote)
                    }
                }
                
                Section {
                    HStack {
                        Button(action: verifyToken) {
                            if isVerifying {
                                HStack{
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Text("Verifying...")
                                }
                            } else {
                                Text("Verify Token")
                            }
                        }
                        .disabled(apiToken.isEmpty || isVerifying)
                        
                        /*
                        if let username = verifiedUsername {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(username)
                                .foregroundColor(.secondary)
                        }
                        */
                        
                    }
                    
                    if let username = verifiedUsername {
                        HStack{
                            Text("    Account:")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(username)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let budgetName = verifiedBudgetname {
                        HStack{
                            Text("    Budget:")
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(budgetName)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Save") {
                        guard saveMirrorURL() else { return }
                        if !apiToken.isEmpty {
                            keychain.storeTokenInKeychain(token: apiToken)
                        }
                        onSave()
                        dismiss()
                    }
                    .disabled(!isTokenValid && !canSaveMirrorOnly)

                    if let error = verificationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    TextField("https://example.com", text: $mirrorURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: mirrorURLString) { _, newValue in
                            mirrorURLError = nil
                            // Mirror-only without a URL makes no sense; drop
                            // the toggle when the field is cleared.
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                mirrorOnly = false
                            }
                        }

                    if !mirrorURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Toggle("Mirror only — don't sync to Lunch Money", isOn: $mirrorOnly)
                    }

                    if let error = mirrorURLError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                } header: {
                    Text("Mirror Server (Optional)")
                } footer: {
                    if mirrorOnly {
                        Text("Mirror only: each sync sends a JSON snapshot of your accounts and transactions to <base URL>/finance-kit-sync and skips Lunch Money entirely. No Lunch Money API token is required. The URL must use https.")
                    } else {
                        Text("When set, each sync also sends a JSON snapshot of your accounts and transactions to <base URL>/finance-kit-sync. The URL must use https. Leave blank to disable.")
                    }
                }
                /*
                #if DEBUG
                Section {
                    Button("Fill Test Token") {
                        apiToken = "337f665be832d9e0e999248275ae4998628c7464756067e903"
                    }
                    .foregroundColor(.accentColor)
                }
                #endif
                 */
            }
            .navigationBarTitleDisplayMode(.inline)

        }
        .interactiveDismissDisabled(!allowDismissal)
        .onAppear {
            let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
            mirrorURLString = sharedDefaults.string(forKey: MirrorAPI.defaultsKey) ?? ""
            mirrorOnly = sharedDefaults.bool(forKey: MirrorAPI.mirrorOnlyDefaultsKey)
        }
    }

    /// Mirror-only mode lets the user save with no verified (or even entered)
    /// API token, as long as the mirror URL validates.
    private var canSaveMirrorOnly: Bool {
        mirrorOnly && MirrorAPI.validatedBaseURL(from: mirrorURLString) != nil
    }

    /// Persists the mirror URL and mirror-only flag alongside the token save.
    /// Returns false (and shows an inline error) when the entered URL is
    /// invalid, so bad values are never stored. A blank field clears both
    /// settings.
    private func saveMirrorURL() -> Bool {
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let trimmed = mirrorURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            sharedDefaults.removeObject(forKey: MirrorAPI.defaultsKey)
            sharedDefaults.set(false, forKey: MirrorAPI.mirrorOnlyDefaultsKey)
            mirrorURLError = nil
            return true
        }

        guard let url = MirrorAPI.validatedBaseURL(from: trimmed) else {
            mirrorURLError = "Enter a valid https:// URL (e.g. https://example.com)"
            return false
        }

        sharedDefaults.set(url.absoluteString, forKey: MirrorAPI.defaultsKey)
        sharedDefaults.set(mirrorOnly, forKey: MirrorAPI.mirrorOnlyDefaultsKey)
        mirrorURLString = url.absoluteString
        mirrorURLError = nil
        return true
    }

    private func verifyToken() {
        isVerifying = true
        verificationError = nil
        isTokenValid = false
        verifiedUsername = nil
        verifiedBudgetname = nil
        
        //print("Verifying token: \(apiToken)")
        // Verifies against the API version selected in Settings, so a broken
        // v2 selection surfaces here rather than silently at sync time.
        let api = LunchMoneyServiceFactory.make(apiToken: apiToken)
        
        Task {
            do {
                let user = try await api.getUser()
                DispatchQueue.main.async {
                    isVerifying = false
                    isTokenValid = true
                    verifiedUsername = user.userName
                    verifiedBudgetname = user.budgetName
                }
            } catch {
                DispatchQueue.main.async {
                    isVerifying = false
                    verificationError = "Verification failed: \(error.localizedDescription)"
                    isTokenValid = false
                    verifiedUsername = nil
                    verifiedBudgetname = nil
                }
            }
        }
    }
}

struct TokenPromptView_Previews: PreviewProvider {
    static var previews: some View {
        TokenPromptView(
            isPresented: .constant(true),
            apiToken: .constant(""),
            onSave: {},
            allowDismissal: true
        )
    }
}

