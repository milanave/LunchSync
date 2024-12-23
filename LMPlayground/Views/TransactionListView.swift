import Foundation
import SwiftUI
import SwiftData

struct TransactionListView: View {
    let wallet: Wallet
    let syncStatus: Transaction.SyncStatus
    @State private var transactions: [Transaction] = []
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                List {
                    ForEach(transactions.sorted(by: { $0.date > $1.date }), id: \.id) { account in
                        TransactionRowView(transaction: account, wallet: wallet)
                    }
                }
            }
            .navigationTitle("\(transactions.count) Transactions with status: \(syncStatus.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            refreshTransactions()
        }
    }
    
    private func refreshTransactions() {
        transactions = wallet.getTransactionsWithStatus(syncStatus)
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
                }
                HStack {
                    Text(transaction.account).font(.footnote)
                    Spacer()
                }
            }
        }
    }
}

