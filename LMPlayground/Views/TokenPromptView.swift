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
                        
                        
                        if let username = verifiedUsername {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(username)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button("Save") {
                        keychain.storeTokenInKeychain(token: apiToken)
                        onSave()
                        dismiss()
                    }
                    .disabled(!isTokenValid)
                    
                    if let error = verificationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
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
    }
    
    private func verifyToken() {
        isVerifying = true
        verificationError = nil
        isTokenValid = false
        verifiedUsername = nil
        
        print("Verifying token: \(apiToken)")
        let api = LunchMoneyAPI(apiToken: apiToken, debug: false)
        
        Task {
            do {
                let user = try await api.getUser()
                DispatchQueue.main.async {
                    isVerifying = false
                    isTokenValid = true
                    verifiedUsername = user.userName
                }
            } catch {
                DispatchQueue.main.async {
                    isVerifying = false
                    verificationError = "Verification failed: \(error.localizedDescription)"
                    isTokenValid = false
                    verifiedUsername = nil
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

