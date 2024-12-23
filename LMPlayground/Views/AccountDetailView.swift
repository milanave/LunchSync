import Foundation
import SwiftUI

struct AccountDetailView: View {
    let account: Account
    let wallet: Wallet
    @State private var showingConfirmation = false

    var body: some View {
        List {
            Section("Basic Information") {
                DetailRow(label: "Name", value: account.name)
                DetailRow(label: "Balance", value: CurrencyFormatter.shared.format(account.balance))
                if account.available != 0.0 {
                    DetailRow(label: "Available Balance", value: CurrencyFormatter.shared.format(account.available))
                }
                DetailRow(label: "Currency", value: account.currency)
            }
            
            Section("Institution Details") {
                DetailRow(label: "Institution Name", value: account.institution_name.isEmpty ? "Not specified" : account.institution_name)
                DetailRow(label: "Institution ID", value: account.institution_id.isEmpty ? "Not specified" : account.institution_id)
                //DetailRow(label: "Last Updated", value: account.lastUpdated.formatted(date: .long, time: .short))
                //DetailRow(label: "Date", value: account.lastUpdated.date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).year(.twoDigits)))
            }
            
            Section("External IDs") {
                DetailRow(label: "Account ID", value: account.id)
                DetailRow(label: "Lunch Money ID", value: account.lm_id.isEmpty ? "Not synced" : account.lm_id)
            }
            
            Section("Sync Status") {
                DetailRow(label: "Sync Enabled", value: account.sync ? "Yes" : "No")
            }
            
            Section("Options"){
                Button(role: .destructive, action: { showingConfirmation = true }) {
                    Label("Don't Sync", systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle(account.name)
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
            Text("Transactions from this account will no longer sync with Lunch Money. You can re-pair it in settings.")
        }
    }
    
    private func stopSync() {
        account.sync = false
        wallet.replaceAccount(newAccount: account, propertiesToUpdate: ["sync"])
    }
}
