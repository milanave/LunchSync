import SwiftUI

struct AssetSelectionView: View {
    let account: Account
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [Asset] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isPresentingCreateSheet = false
    @State private var newAssetName: String = ""
    @State private var createError: String?
    @State private var createdAssetId: Int?
    
    
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
                            newAssetName = account.name
                            createError = nil
                            createdAssetId = nil
                            isPresentingCreateSheet = true
                        }) {
                            Label("Create New Asset", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Link Asset")
            .alert("Error", isPresented: Binding(
                  get: { error != nil },
                  set: { if !$0 { error = nil } }
              )) { Button("OK") { error = nil } } message: {
                  if let error { Text(error) }
              }
            .sheet(isPresented: $isPresentingCreateSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Asset Name")) {
                            TextField("Name", text: $newAssetName)
                        }
                        Section {
                            Button("Create") {
                                Task {
                                    createError = nil
                                    createdAssetId = nil
                                    let id = await wallet.createAsset(name: newAssetName.isEmpty ? account.name : newAssetName,
                                                                      institutionName: account.institution_name,
                                                                      note: account.id)
                                    if let id {
                                        createdAssetId = id
                                        await loadAssets()
                                    } else {
                                        createError = "Failed to create asset. Please try again."
                                    }
                                }
                            }
                            .disabled(createdAssetId != nil || newAssetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let createError {
                            Section {
                                Text(createError)
                                    .foregroundColor(.red)
                            }
                        }
                        if let createdAssetId {
                            Section(footer: Text("Asset created successfully: ID \(createdAssetId)")) {
                                Button("Link Asset") {
                                    if let asset = assets.first(where: { $0.id == createdAssetId }) {
                                        linkAsset(asset)
                                    } else {
                                        // Fallback: reload assets to find it, then link
                                        Task {
                                            await loadAssets()
                                            if let asset = assets.first(where: { $0.id == createdAssetId }) {
                                                linkAsset(asset)
                                            } else {
                                                // If still not found, just dismiss
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Create Asset")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPresentingCreateSheet = false }
                        }
                    }
                }
            }
            .task {
                await loadAssets()
            }
        }
    }
    
    @MainActor
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

