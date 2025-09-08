//
//  SettingsView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
//  Updated 7/28/25, added new transaction settings

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Binding var isPresented: Bool
    
    @AppStorage("importTransactionsCleared", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var importTransactionsCleared = true
    @AppStorage("putTransStatusInNotes", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var putTransStatusInNotes = true
    @AppStorage("apply_rules", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var applyRules = false
    @AppStorage("skip_duplicates", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipDuplicates = false
    @AppStorage("check_for_recurring", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var checkForRecurring = false
    @AppStorage("skip_balance_update", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipBalanceUpdate = false
    @AppStorage("categorize_incoming", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var categorize_incoming = true
    @AppStorage("alert_after_import", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var alert_after_import = true
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle(isOn: $categorize_incoming) {
                        HStack {
                            Image(systemName: categorize_incoming ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(categorize_incoming ? .green : .gray)
                            Text("Categorize Transactions")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, map Wallet's MCC codes to Lunch Money categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $importTransactionsCleared) {
                        HStack {
                            Image(systemName: importTransactionsCleared ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(importTransactionsCleared ? .green : .gray)
                            Text("Import as \(importTransactionsCleared ? "Reviewed" : "Unreviewed")")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, transactions will be marked as 'reviewed' when imported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $putTransStatusInNotes) {
                        HStack {
                            Image(systemName: putTransStatusInNotes ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(putTransStatusInNotes ? .green : .gray)
                            Text("Transaction status in notes")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("Put the Wallet transaction's latest status in the LunchMoney notes field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $alert_after_import) {
                        HStack {
                            Image(systemName: alert_after_import ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(alert_after_import ? .green : .gray)
                            Text("Alert after import")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("Send an alert after an import finds new transactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Transaction Import Settings")
                }
                Section{
                    Toggle(isOn: $applyRules) {
                        HStack {
                            Image(systemName: applyRules ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(applyRules ? .green : .gray)
                            Text("Apply rules")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, will apply account’s existing rules to the inserted transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $skipDuplicates) {
                        HStack {
                            Image(systemName: skipDuplicates ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(skipDuplicates ? .green : .gray)
                            Text("Skip duplicates")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, the system will automatically dedupe based on transaction date, payee and amount.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $checkForRecurring) {
                        HStack {
                            Image(systemName: checkForRecurring ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(checkForRecurring ? .green : .gray)
                            Text("Check for recurring")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, will check new transactions for occurrences of new monthly expenses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $skipBalanceUpdate) {
                        HStack {
                            Image(systemName: skipBalanceUpdate ? "checkmark.circle.fill" : "circle")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(skipBalanceUpdate ? .green : .gray)
                            Text("Skip balance update")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    Text("If true, will skip updating balance if an asset_id is present for any of the transactions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("API Import Rules")
                } footer: {
                    Text("See LunchMoney API documentation for more information.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
}

// MARK: Preview
#Preview {
    SettingsView(isPresented: .constant(true)) 
}
