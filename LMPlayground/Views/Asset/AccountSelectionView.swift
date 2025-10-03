//
//  AccountSelectionView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
//
import SwiftUI
import SwiftData
import FinanceKit
import FinanceKitUI

struct AccountSelectionView: View {
    @Binding var isPresented: Bool
    let onSave: () -> Void
    let allowDismissal: Bool
    @StateObject private var viewModel: AccountSelectionViewModel
    @State private var appleWallet: AppleWallet
    @State private var showingPreviewTransactions = false
    @State private var transactions: [Transaction] = []
    
    init(isPresented: Binding<Bool>,
         onSave: @escaping () -> Void,
         allowDismissal: Bool = true,
         wallet: Wallet) {
        self._isPresented = isPresented
        self.onSave = onSave
        self.allowDismissal = allowDismissal
        self._viewModel = StateObject(wrappedValue: AccountSelectionViewModel(wallet: wallet))
        
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            _appleWallet = State(initialValue: MockAppleWallet())
        } else {
            _appleWallet = State(initialValue: AppleWallet())
        }
        #else
        _appleWallet = State(initialValue: AppleWallet())
        #endif
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select Apple Wallet accounts to sync, and pair each with a Lunch Money asset.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                List {
                    ForEach(viewModel.wallet.getAccounts(), id: \.id) { account in
                        NavigationLink {
                            AssetSelectionView(account: account, wallet: viewModel.wallet)
                        } label: {
                            AccountRowView(account: account)
                        }
                    }
                    if viewModel.wallet.getAccounts().count > 0{
                        importButtons()
                    }
                    /*
                     Section() {
                         Button {
                             Task { @MainActor in
                                 do {
                                     if(!viewModel.wallet.isSimulator){
                                         let authStatus = await appleWallet.requestAuth()
                                         guard authStatus == .authorized else {
                                             print("Authorization denied")
                                             return
                                         }
                                     }
                                     
                                     let allAppleAccounts = try await viewModel.wallet.isSimulator ?
                                         appleWallet.getSimulatedAccounts() :
                                         appleWallet.getWalletAccounts()
                                     try await viewModel.wallet.syncAccountBalances(accounts: allAppleAccounts)
                                     viewModel.objectWillChange.send()
                                 } catch {
                                     print("Error fetching wallet accounts: \(error)")
                                     // Handle error appropriately
                                 }
                             }
                         } label: {
                             HStack {
                                 Text("Refresh Apple Wallet")
                                 Spacer()
                                 Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                             }
                         }
                     }
                     */
                }
            }
            .navigationTitle("Select Accounts")
            .sheet(isPresented: $showingPreviewTransactions) {
                PreviewTransactionsView(
                    transactions: transactions,
                    onImport: { selectedTransactions in
                        //print("selected for import: \(selectedTransactions.count)")
                        selectedTransactions.forEach { transaction in
                            viewModel.wallet.replaceTransaction(newTrans: transaction)
                        }
                    }
                )
            }
        }
        .interactiveDismissDisabled(!allowDismissal)
        .onDisappear {
            onSave()
        }
        
        
    }
    
    private func importButtons() -> some View {
        Section {
            Button {
                Task {
                    // Disable the button while loading
                    showingPreviewTransactions = false
                    let accounts = viewModel.wallet.getSyncedAccounts()
                    transactions = try await appleWallet.fetchhWalletTransactionsForAccounts(accounts: accounts)
                    
                    // Show preview only after transactions are loaded
                    showingPreviewTransactions = true
                }
            } label: {
                HStack {
                    Text("Review transactions for import")
                    Spacer()
                    Image(systemName: "arrow.down.circle.fill")
                }
            }
            .disabled(viewModel.wallet.getSyncedAccounts().isEmpty || showingPreviewTransactions)
        } header: {
            Text("Import Historical Transactions")
        } footer: {
            Text("See a list of transactions by month from your Apple Wallet to import into Lunch Money").foregroundStyle(.secondary)
        }
    }
    
    
}

struct AccountRowView: View {
    let account: Account
    
    var body: some View {
        VStack {
            HStack {
                Image("WalletIcon")
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(account.name)
                Spacer()
                CurrencyFormatter.shared.formattedText(account.balance)
            }
            HStack {
                Group {
                    if account.sync {
                        Image("LunchIcon")
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "rectangle.on.rectangle.slash.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.gray)
                    }
                }
                if account.sync {
                    Text("Synced to \(account.lm_id) \(account.lm_name)")
                        .font(.footnote)
                } else {
                    Text("Not Synced")
                        .font(.footnote)
                }
                Spacer()
            }
        }
    }
}

class AccountSelectionViewModel: ObservableObject {
    @Published var wallet: Wallet
    private let appleWallet = AppleWallet()
    
    init(wallet: Wallet) {
        self.wallet = wallet
        
        Task {
            do {
                let isSimulator = await wallet.isSimulator
                if(!isSimulator){
                    let authStatus = await appleWallet.requestAuth()
                    guard authStatus == .authorized else {
                        print("Authorization denied")
                        return
                    }
                }
                
                let allAppleAccounts = try await wallet.isSimulator ?
                    appleWallet.getSimulatedAccounts() : 
                    appleWallet.getWalletAccounts()
                try await wallet.syncAccountBalances(accounts: allAppleAccounts)
                await MainActor.run {                    
                    objectWillChange.send()
                }
            } catch {
                print("Error fetching wallet accounts: \(error)")
                // Handle error appropriately
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Transaction.self,
        Account.self,
        Log.self,
        Item.self,
        LMCategory.self,
        TrnCategory.self,
        TransactionHistory.self
    ])
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    let mockWallet = MockWallet(context: context, apiToken: "mock-token")
    
    return AccountSelectionView(
        isPresented: .constant(true),
        onSave: {},
        allowDismissal: true,
        wallet: mockWallet
    )
    .modelContainer(container)
}
