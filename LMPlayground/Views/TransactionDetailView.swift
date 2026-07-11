import Foundation
import SwiftUI
import SwiftData




struct TransactionDetailView: View {
    let transaction: Transaction
    let wallet: Wallet
    @Environment(\.modelContext) private var modelContext
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
                DetailRow(label: "Pending", value: transaction.isPending ? "Pending" : "Booked")
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
                            Button("Mark as skipped") { wallet.setSyncStatus(newTrans: transaction, newStatus: .skipped)   }
                            Button("Mark as error", role: .destructive) {  wallet.setSyncStatus(newTrans: transaction, newStatus: .never) }
                        }else if transaction.sync == .never{
                            Button("Queue for Sync") { wallet.setSyncStatus(newTrans: transaction, newStatus: .pending) }
                            Button("Mark as skipped") { wallet.setSyncStatus(newTrans: transaction, newStatus: .skipped)   }
                        }else if transaction.sync == .complete{
                            Button("Queue for Sync") { wallet.setSyncStatus(newTrans: transaction, newStatus: .pending) }
                            Button("Mark as error", role: .destructive) { wallet.setSyncStatus(newTrans: transaction, newStatus: .never)   }
                        }else if transaction.sync == .skipped{
                            Button("Queue for Sync") { wallet.setSyncStatus(newTrans: transaction, newStatus: .pending) }
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
            
            Section{
                DetailRow(label: "Category Id", value: transaction.category_id ?? "")
                DetailRow(label: "Category Name", value: transaction.category_name ?? "")
                DetailRow(label: "LM Category Id", value: transaction.lm_category_id ?? "")
                DetailRow(label: "LM Category Name", value: transaction.lm_category_name ?? "")
            } header:{
                Text("Category")
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

            Section {
                if let pretty = prettyPrintedMetadata {
                    Text(pretty)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text("No metadata captured")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Metadata")
            } footer: {
                if prettyPrintedMetadata != nil {
                    Text("This is the JSON that will be sent to Lunch Money in the `custom_metadata` field when this transaction syncs.")
                        .font(.caption)
                }
            }

            Section {
                if (transaction.histories ?? []).isEmpty {
                    Text("No transaction history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array((transaction.histories ?? []).sorted { $0.date < $1.date }.enumerated()), id: \.offset) { _, history in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(history.note)
                            HStack{
                                Text(history.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(history.source)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                /*
                Button("add history") {
                    transaction.addHistory(note: "Added manually")
                    try? modelContext.save()
                }
                */
            } header: {
                Text("History")
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
                    Text("This deletes the transaction from the local cache and may re-sync from the Wallet. It will not be deleted from Lunch Money.")
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
    
    /// Re-pretty-prints the stored `walletMetadataJSON` for display. Uses
    /// JSONSerialization round-tripping so the field order from the original
    /// encoder (which uses our CodingKeys order) is preserved.
    private var prettyPrintedMetadata: String? {
        guard
            let json = transaction.walletMetadataJSON,
            !json.isEmpty,
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes]
            )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
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
        
        let encodedPayee = encodePayee(transaction.payee)
        
        return "https://my.lunchmoney.app/transactions/\(year)/\(month)?start_date=\(dateString)&end_date=\(dateString)&match=all&payee_exact=\(encodedPayee)&time=custom"
    }

    private func encodePayee(_ payee: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed
        var encoded = payee.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        encoded = encoded.replacingOccurrences(of: "&", with: "%26")
        encoded = encoded.replacingOccurrences(of: "+", with: "%2B")
        encoded = encoded.replacingOccurrences(of: "#", with: "%23")
        encoded = encoded.replacingOccurrences(of: "=", with: "%3D")
        encoded = encoded.replacingOccurrences(of: "/", with: "%2F")
        encoded = encoded.replacingOccurrences(of: "?", with: "%3F")
        return encoded
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


#Preview {
    // In-memory model container for previews
    let schema = Schema([
        Transaction.self,
        Account.self,
        Log.self,
        Item.self,
        TransactionHistory.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = container.mainContext

    // Mock wallet and sample transaction
    let wallet = MockWallet(context: context, apiToken: "preview-token")

    let sampleMetadataJSON = WalletMetadata(
        source: "lunchsync",
        sourceVersion: "1.4.2",
        wallet: WalletMetadata.WalletPayload(
            transactionId: "B3C2A1D0-8F77-4E2A-9C40-7E1D2F5A6B91",
            accountId: "A1F2E3D4-1234-5678-9ABC-DEF012345678",
            accountDisplayName: "Apple Card",
            institutionName: "Goldman Sachs",
            transactionDate: "2026-04-29T18:14:22Z",
            postedDate: "2026-04-30T03:00:00Z",
            status: "booked",
            isPending: false,
            transactionType: "pointOfSale",
            creditDebitIndicator: "debit",
            transactionDescription: "BLUE BOTTLE COFFEE #142",
            originalTransactionDescription: "SQ *BLUE BOTTLE COFFEE  OAKLAND CA",
            merchantName: "Blue Bottle Coffee",
            merchantCategoryCode: "5814",
            merchantCategoryDescription: "Eating Places, Restaurants",
            amount: WalletMetadata.Money(value: "7.85", currency: "USD"),
            foreignAmount: nil,
            foreignExchangeRate: nil
        )
    ).toJSONString()

    let sample = Transaction(
        id: "txn_preview_001",
        account: "Apple Card",
        payee: "Blue Bottle Coffee",
        amount: 7.85,
        date: Date(),
        lm_id: "",
        lm_account: "",
        notes: "Latte and croissant",
        category: "Food & Drink",
        type: "card",
        accountID: "acc_preview_001",
        status: "cleared",
        isPending: false,
        sync: .complete,
        lm_category_id: "123",
        lm_category_name: "Dining",
        category_id: "200",
        category_name: "Restaurants",
        walletMetadataJSON: sampleMetadataJSON
    )
    sample.addHistory(note: "Queued for sync", source: "BGD")
    sample.addHistory(note: "amount = $1,000.23, payee = Acme Corp", source: "BGD")

    return NavigationStack {
        TransactionDetailView(transaction: sample, wallet: wallet)
    }
    .modelContainer(container)
}

