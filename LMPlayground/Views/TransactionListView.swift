import Foundation
import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.dismiss) private var dismiss
    let wallet: Wallet
    let syncStatuses: [Transaction.SyncStatus]
    @State private var transactions: [Transaction] = []
    @State private var searchText: String = ""
    @State private var selectedStatusFilter: String
    
    init(wallet: Wallet, syncStatuses: [Transaction.SyncStatus]) {
        self.wallet = wallet
        self.syncStatuses = syncStatuses
        // Default to first status when multiple statuses, otherwise "All"
        self._selectedStatusFilter = State(initialValue: syncStatuses.count > 1 ? syncStatuses.first?.rawValue ?? "All" : "All")
    }
    
    init(wallet: Wallet, syncStatus: Transaction.SyncStatus) {
        self.init(wallet: wallet, syncStatuses: [syncStatus])
    }
    
    private var filteredTransactions: [Transaction] {
        var result = transactions.sorted(by: { $0.date > $1.date })
        
        // Filter by selected status tab (if not "All")
        if selectedStatusFilter != "All",
           let status = syncStatuses.first(where: { $0.rawValue == selectedStatusFilter }) {
            result = result.filter { $0.sync == status }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { transaction in
                let payeeMatch = transaction.payee.localizedCaseInsensitiveContains(searchText)
                let amountString = String(format: "%.2f", abs(transaction.amount))
                let amountMatch = amountString.contains(searchText)
                return payeeMatch || amountMatch
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if syncStatuses.count > 1 {
                    Picker("Filter by status", selection: $selectedStatusFilter) {
                        Text("All").tag("All")
                        ForEach(syncStatuses, id: \.rawValue) { status in
                            Text(status.rawValue.capitalized).tag(status.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                if syncStatuses.count == 1 && syncStatuses.first == .never {
                    Button(action: {
                        transactions.forEach { transaction in
                            wallet.setSyncStatus(newTrans: transaction, newStatus: .pending)
                        }
                        refreshTransactions()
                        dismiss()
                    }) {
                        Text("Re-sync \(transactions.count) transactions")
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                }
                List {
                    ForEach(filteredTransactions, id: \.id) { account in
                        TransactionRowView(transaction: account, wallet: wallet)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by payee or amount")
            .navigationTitle("\(filteredTransactions.count) Transactions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshTransactions()
        }
    }
    
    private func refreshTransactions() {
        transactions = wallet.getTransactionsWithStatus(syncStatuses)
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    let wallet: Wallet
    
    var body: some View {
        NavigationLink {
            TransactionDetailView(transaction: transaction, wallet: wallet)
        } label: {
            VStack {
                HStack {
                    Text(transaction.payee)
                    Spacer()
                    CurrencyFormatter.shared.formattedText(transaction.amount)
                }
                HStack {
                    Text(transaction.date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).year(.twoDigits)))
                    Spacer()
                    Text(transaction.lm_category_name?.isEmpty == false ? transaction.lm_category_name! : "unknown")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(transaction.account).font(.footnote)
                    Spacer()
                    if transaction.isPending {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.yellow)
                                .font(.footnote)
                            Text("Pending")
                                .font(.footnote)
                                .italic()
                        }
                    }else if transaction.sync == .complete {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.green)
                                .font(.footnote)
                            Text("Synced")
                                .font(.footnote)
                                .italic()
                        }
                    }else if transaction.sync == .never {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.red)
                                .font(.footnote)
                            Text("Error")
                                .font(.footnote)
                                .italic()
                        }
                    }else if transaction.sync == .skipped {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.gray)
                                .font(.footnote)
                            Text("Skipped")
                                .font(.footnote)
                                .italic()
                        }
                    }else if transaction.sync == .pending {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                                .font(.footnote)
                            Text("Pending Sync")
                                .font(.footnote)
                                .italic()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Transaction.self)
    let context = container.mainContext
    let wallet = MockWallet(context: context, apiToken: "mock-token")
    
    return NavigationStack {
        TransactionListView(wallet: wallet, syncStatuses: [.complete, .skipped])
    }
    .modelContainer(container)
}

