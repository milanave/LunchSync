import Foundation
import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.dismiss) private var dismiss
    let wallet: Wallet
    let syncStatuses: [Transaction.SyncStatus]
    @State private var transactions: [Transaction] = []
    
    init(wallet: Wallet, syncStatuses: [Transaction.SyncStatus]) {
        self.wallet = wallet
        self.syncStatuses = syncStatuses
    }
    
    init(wallet: Wallet, syncStatus: Transaction.SyncStatus) {
        self.init(wallet: wallet, syncStatuses: [syncStatus])
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
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
                    ForEach(transactions.sorted(by: { $0.date > $1.date }), id: \.id) { account in
                        TransactionRowView(transaction: account, wallet: wallet)
                    }
                }
            }
            .navigationTitle("\(transactions.count) Transactions with status: \(syncStatuses.map { $0.rawValue }.joined(separator: ", "))")
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

