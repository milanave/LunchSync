import SwiftUI

struct AssetSelectionView: View {
    let account: Account
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [Asset] = []
    @State private var isLoading = true
    @State private var error: String?
    
    
    var body: some View {
        VStack{
            Text("Select a Lunch Money asset to sync to \(account.name)")
            List {
                
                if isLoading {
                    ProgressView("Loading assets...")
                } else {
                    Section {
                        Button(action: {
                            unLinkAsset()
                        }) {
                            Label("Don't Sync Account", systemImage: "minus.circle.fill")
                        }
                    }
                    
                    Section {
                        if assets.isEmpty {
                            Text("No manually-managed assets found. Create one below.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(assets, id: \.id) { asset in
                                Button(action: {
                                    linkAsset(asset)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(asset.displayName ?? asset.name)
                                            Spacer()
                                            if let balance = Double(asset.balance) {
                                                CurrencyFormatter.shared.formattedText(balance)
                                            }
                                        }
                                        if let institutionName = asset.institutionName {
                                            Text(institutionName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Available Assets")
                    } footer: {
                        Text("Avoid syncing transactions to existing Lunch Money accounts, or accounts linked to Plaid. Create a new asset below if needed.")
                            .font(.subheadline)
                    }
                    
                    Section {
                        Button(action: {
                            Task{
                                do{
                                    if(await wallet.createAsset(name:account.name, institutionName:account.institution_name, note: account.id)){
                                        await loadAssets()
                                    }else{
                                        print("Create failed")
                                    }
                                    
                                }
                            }
                                }) {
                            Label("Create New Asset", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Link Asset")
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error = error {
                    Text(error)
                }
            }
            .task {
                await loadAssets()
            }
        }
    }
    
    private func loadAssets() async {
        do {
            let keychain = Keychain()
            if let token = try? keychain.retrieveTokenFromKeychain() {
                let api = LunchMoneyAPI(apiToken: token, debug: false)
                self.assets = try await api.getAssets() //WithLastTransaction()
                
            }
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    private func linkAsset(_ asset: Asset) {
        //print("linkAsset \(asset.id) \(asset.name)")
        account.lm_id = String(asset.id)
        account.lm_name = String(asset.name)
        account.sync = true
        wallet.replaceAccount(newAccount: account, propertiesToUpdate: ["lm_id", "lm_name", "sync"])
        dismiss()
    }
    
    private func unLinkAsset() {
        account.lm_id = ""
        account.lm_name = ""
        account.sync = false
        wallet.replaceAccount(newAccount: account, propertiesToUpdate: ["lm_id", "lm_name", "sync"])
        dismiss()
    }
}

