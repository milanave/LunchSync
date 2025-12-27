import Foundation
import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let account: Account
    let wallet: Wallet
    @State private var showingAssetSelection = false
    @Query private var recentTransactions: [Transaction]
    
    init(account: Account, wallet: Wallet) {
        self.account = account
        self.wallet = wallet
        let accountId = account.id
        _recentTransactions = Query(
            filter: #Predicate<Transaction> { $0.accountID == accountId },
            sort: [SortDescriptor(\.date, order: .reverse)],
            animation: .default
        )
    }

    var body: some View {
        List {
            Section("Account Information") {
                DetailRow(label: "Name", value: account.name)
                DetailRow(label: "Balance", value: CurrencyFormatter.shared.format(account.balance))
                if account.available != 0.0 {
                    DetailRow(label: "Available Balance", value: CurrencyFormatter.shared.format(account.available))
                }
                //DetailRow(label: "Currency", value: account.currency)
                DetailRow(label: "Institution Name", value: account.institution_name.isEmpty ? "Not specified" : account.institution_name)
                DetailRow(label: "Institution ID", value: account.institution_id.isEmpty ? "Not specified" : account.institution_id)
                DetailRow(label: "Lunch Money ID", value: account.lm_id.isEmpty ? "Not synced" : account.lm_id)
            }
            
            Section("Options"){
                Toggle("Sync Balance Only", isOn: Binding(
                    get: { account.syncBalanceOnly },
                    set: { newValue in
                        account.syncBalanceOnly = newValue
                        wallet.replaceAccount(newAccount: account, propertiesToUpdate: ["syncBalanceOnly"])
                    }
                ))
                Button {
                    showingAssetSelection = true
                } label: {
                    Text("Re-Link Account")
                }
            }
            
            Section("Recent transactions") {
                if recentTransactions.isEmpty {
                    Text("No recent transactions")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentTransactions.prefix(10), id: \.id) { transaction in
                        TransactionRowView(transaction: transaction, wallet: wallet)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAssetSelection) {
            NavigationStack {
                AssetSelectionView(account: account, wallet: wallet)
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
    let wallet = Wallet(context: context, apiToken: "preview-token")
    let sampleAccount = Account(
        id: "acc_123",
        name: "Everyday Checking",
        balance: 1234.56,
        lm_id: "456",
        lm_name: "LM Everyday Checking",
        available: 987.65,
        currency: "USD",
        institution_name: "Sample Bank",
        institution_id: "bank_001"
    )
    
    AccountDetailView(account: sampleAccount, wallet: wallet)
        .modelContainer(container)
}
