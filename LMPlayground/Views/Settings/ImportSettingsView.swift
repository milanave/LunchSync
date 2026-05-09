//
//  APIImportRulesView.swift
//  LMPlayground
//
//  Created by AI Assistant on 1/9/26.
//

import SwiftUI

struct ImportSettingsView: View {
    
    @AppStorage("importTransactionsCleared", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var importTransactionsCleared = true
    @AppStorage("putTransStatusInNotes", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var putTransStatusInNotes = true
    @AppStorage("apply_rules", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var applyRules = false
    
    @AppStorage("alert_after_import", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var alert_after_import = true
    @AppStorage("categorize_incoming", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var categorize_incoming = true
    @AppStorage("send_finance_kit_metadata", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var send_finance_kit_metadata = true
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $categorize_incoming) {
                    HStack {
                        Text("Categorize Transactions")
                    }
                }
                .listRowSeparator(.hidden)
            } footer: {
                Text("If true, map Wallet's MCC codes to Lunch Money categories")
                    .font(.caption)
                
            }
            Section {
                Toggle(isOn: $importTransactionsCleared) {
                    HStack {
                        Text("Import as \(importTransactionsCleared ? "Reviewed" : "Unreviewed")")
                    }
                }
                .listRowSeparator(.hidden)
            } footer: {
                Text("If true, transactions will be marked as 'reviewed' when imported.")
                    .font(.caption)
            }
            Section{
                Toggle(isOn: $putTransStatusInNotes) {
                    HStack {
                        Text("Transaction status in notes")
                    }
                }
                .listRowSeparator(.hidden)
            } footer: {
                Text("Put the Wallet transaction's latest status in the LunchMoney notes field.")
                    .font(.caption)
            }
            Section{
                Toggle(isOn: $alert_after_import) {
                    HStack {
                        Text("Alert after import")
                    }
                }
                .listRowSeparator(.hidden)
            } footer: {
                Text("Send an alert after an import finds new transactions.")
                    .font(.caption)
            }
            Section{
                Toggle(isOn: $send_finance_kit_metadata) {
                    HStack {
                        Text("Send FinanceKit metadata")
                    }
                }
                .listRowSeparator(.hidden)
            } footer: {
                Text("Attach the raw Apple Wallet transaction details (merchant name, MCC, original description, foreign-currency info, etc.) to each synced transaction's `custom_metadata` field in Lunch Money.")
                    .font(.caption)
            }
        }
        .navigationTitle("Import Settings")
    }
}

#Preview {
    NavigationView {
        ImportSettingsView()
    }
}


