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
                        // A valid mirror URL allows saving with no token at
                        // all (mirror-only); never write an empty token.
                        if !apiToken.isEmpty {
                            keychain.storeTokenInKeychain(token: apiToken)
                        }
                        onSave()
                        dismiss()
                    }
                    .disabled(!isTokenValid && !canSaveWithoutToken)

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
                        .onChange(of: mirrorURLString) { _, _ in
                            mirrorURLError = nil
                        }

                    if let error = mirrorURLError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                } header: {
                    Text("Mirror Server (Optional)")
                } footer: {
                    Text("When set, your full Apple Wallet transaction history is mirrored as JSON to <base URL>/finance-kit-sync on every sync. If the server is unreachable, the mirror catches up automatically on a later sync. The URL must use https; leave blank to disable.")
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
            mirrorURLString = MirrorAPI.storedBaseURLString()
        }
    }

    /// Mirror-only saves need no token (and no token verification): a valid
    /// mirror URL with an empty token is enough.
    private var canSaveWithoutToken: Bool {
        apiToken.isEmpty && MirrorAPI.validatedBaseURL(from: mirrorURLString) != nil
    }

    /// Persists the mirror URL alongside the token save. Returns false (with
    /// an inline error) for an invalid URL so bad values are never stored;
    /// a blank field clears the setting.
    private func saveMirrorURL() -> Bool {
        let trimmed = mirrorURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            MirrorAPI.setConfiguredBaseURL(nil)
            mirrorURLError = nil
            return true
        }
        guard let url = MirrorAPI.validatedBaseURL(from: trimmed) else {
            mirrorURLError = "Enter a valid https:// URL (e.g. https://example.com)"
            return false
        }
        MirrorAPI.setConfiguredBaseURL(url)
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

