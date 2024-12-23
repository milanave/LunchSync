import Foundation
import SwiftUI
import SwiftData




struct TransactionDetailView: View {
    let transaction: Transaction
    let wallet: Wallet
    @Environment(\.dismiss) private var dismiss
    @State private var showingConfirmation = false        
    @State private var showingConfirmationDialog: Bool = false
    
    @State private var showingAlert: Bool = false
    
    var body: some View {
        List {
            Section {
                DetailRow(label: "Payee", value: transaction.payee)
                DetailRow(label: "Amount", value: CurrencyFormatter.shared.format(transaction.amount))
                DetailRow(label: "Date", value: transaction.date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).year(.twoDigits)))
                DetailRow(label: "Account", value: transaction.account)
                DetailRow(label: "Account ID", value: transaction.accountID)
            } header: {
                Text("Basic Information")
            }
            
            Section {
                DetailRow(label: "Category", value: transaction.category.isEmpty ? "Uncategorized" : transaction.category)
                DetailRow(label: "Type", value: transaction.type.isEmpty ? "Not specified" : transaction.type)
                DetailRow(label: "Status", value: transaction.status.isEmpty ? "Not specified" : transaction.status)
                DetailRow(label: "Sync Status", value: transaction.sync.rawValue)
                Button(action: {
                    showingConfirmationDialog = true
                }) {
                    Text("Set Sync Status")
                }.confirmationDialog(Text("Change transaction status"),
                    isPresented: $showingConfirmationDialog,
                    titleVisibility: .automatic,
                    actions: {
                        if transaction.sync == .pending{
                            Button("Mark completed") { wallet.setSyncStatus(newTrans: transaction, newStatus: .complete)   }
                            Button("Mark as error", role: .destructive) {  wallet.setSyncStatus(newTrans: transaction, newStatus: .never) }
                        }else if transaction.sync == .never{
                            Button("Queue for Sync") { wallet.setSyncStatus(newTrans: transaction, newStatus: .pending) }
                            Button("Mark completed") { wallet.setSyncStatus(newTrans: transaction, newStatus: .complete)   }
                        }else if transaction.sync == .complete{
                            Button("Queue for Sync") { wallet.setSyncStatus(newTrans: transaction, newStatus: .pending) }
                            Button("Mark as error", role: .destructive) { wallet.setSyncStatus(newTrans: transaction, newStatus: .never)   }
                        }
                        Button("Cancel", role: .cancel) { }
                    },
                    message: {
                        Text("Change the sync status to:")
                    }
                )

            } header: {
                Text("Additional Details")
            }
            
            Section {
                DetailRow(label: "Transaction ID", value: transaction.id)
                DetailRow(label: "Lunch Money ID", value: transaction.lm_id.isEmpty ? "Not synced" : transaction.lm_id)
                DetailRow(label: "Lunch Money Account", value: transaction.lm_account.isEmpty ? "Not synced" : transaction.lm_account)
                
                if !transaction.lm_id.isEmpty {
                    Link(destination: URL(string: buildLunchMoneyURL())!) {
                        HStack {
                            Text("Open in Lunch Money")
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
            } header: {
                Text("External IDs")
            }
            
            if !transaction.notes.isEmpty {
                Section {
                    Text(transaction.notes)
                        .font(.body)
                } header: {
                    Text("Notes")
                }
            }
            
            Button(role: .destructive, action: {
                showingAlert = true
            }) {
                Text("Delete Transaction")
            }.alert(Text("Delete the transaction?"),
                isPresented: $showingAlert,
                actions: {
                    Button("Are you sure?") {
                        wallet.deleteTransaction(id: transaction.id)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) { }
                }, message: {
                    Text("It may be re-synced from Apple Wallet")
                }
            )
        }
        .listStyle(GroupedListStyle())
        .navigationTitle(transaction.payee)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Stop Syncing Transaction",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Syncing", role: .destructive) {
                stopSync()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This transaction will no longer sync with Lunch Money. This action cannot be undone.")
        }
    }
    
    private func setSync(newStatus: Transaction.SyncStatus){
        wallet.setSyncStatus(newTrans: transaction, newStatus: newStatus)
    }
    
    private func stopSync() {
        transaction.sync = .never
        wallet.replaceTransaction(newTrans: transaction)
    }
    
    private func buildLunchMoneyURL() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: transaction.date)
        
        let year = Calendar.current.component(.year, from: transaction.date)
        let month = Calendar.current.component(.month, from: transaction.date)
        
        let encodedPayee = transaction.payee
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26")
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "#", with: "%23")
            .replacingOccurrences(of: "=", with: "%3D")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: "?", with: "%3F") ?? ""
        
        return "https://my.lunchmoney.app/transactions/\(year)/\(month)?start_date=\(dateString)&end_date=\(dateString)&match=all&payee_exact=\(encodedPayee)&time=custom"
    }

}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

