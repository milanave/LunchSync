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
		@Environment(\.modelContext) private var modelContext
		private var syncBroker: SyncBroker { SyncBroker(context: modelContext, logPrefix: "ST") }
    
    @AppStorage("importTransactionsCleared", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var importTransactionsCleared = true
    @AppStorage("putTransStatusInNotes", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var putTransStatusInNotes = true
    @AppStorage("apply_rules", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var applyRules = false
    @AppStorage("skip_duplicates", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipDuplicates = false
    @AppStorage("check_for_recurring", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var checkForRecurring = false
    @AppStorage("skip_balance_update", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipBalanceUpdate = false
    @AppStorage("categorize_incoming", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var categorize_incoming = true
    @AppStorage("alert_after_import", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var alert_after_import = true
    @AppStorage("remove_old_transactions", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var remove_old_transactions = false
    @AppStorage("remove_old_days", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var remove_old_days = 90
		
		@State private var removeOldMatchesCount: Int = 0
		@State private var totalTransactionCount: Int? = nil
		@State private var showDeleteConfirmation: Bool = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle(isOn: $categorize_incoming) {
                        HStack {
                            Text("Categorize Transactions")
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Import Settings")
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
                
                Section {
                    Toggle(isOn: $remove_old_transactions) {
                        HStack {
                            Text("Remove old transactions")
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    if remove_old_transactions {
                        Picker("Automatically delete after:", selection: $remove_old_days) {
                            Text("1 Month").tag(30)
                            Text("3 Months").tag(90)
                            Text("6 Months").tag(180)
                            Text("1 Year").tag(365)
                        }
						.pickerStyle(.menu)
                        .listRowSeparator(.hidden)
							.onChange(of: remove_old_days) { _, _ in
								Task {
									do {
                                        removeOldMatchesCount = try await syncBroker.countTransactionsOlderThanDays(remove_old_days)
									} catch {
										removeOldMatchesCount = 0
									}
								}
							}
							
							Text("Found \(removeOldMatchesCount) matching transaction\(removeOldMatchesCount == 1 ? "" : "s")")
								.font(.caption)
								.foregroundStyle(.secondary)
								.listRowSeparator(.hidden)
							
							Button("Delete \(removeOldMatchesCount) transactions now") {
								showDeleteConfirmation = true
							}
							.disabled(removeOldMatchesCount == 0)
							.listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Cleanup")
                } footer: {
                    Text("Transactions in will be removed from LunchSync automatically, but will remain in LunchMoney. LunchSync currently has: \(totalTransactionCount ?? 0) transactions in its database.")
                        .font(.caption)
                }
                
                Section{
                    Toggle(isOn: $applyRules) {
                        HStack {
                            Text("Apply rules")
                        }
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("API Import Rules")
                } footer: {
                    Text("If true, will apply account’s existing rules to the inserted transactions")
                        .font(.caption)
                }
                Section{
                    Toggle(isOn: $skipDuplicates) {
                        HStack {
                            Text("Skip duplicates")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, the system will automatically dedupe based on transaction date, payee and amount.")
                        .font(.caption)
                }
                Section{
                    Toggle(isOn: $checkForRecurring) {
                        HStack {
                            Text("Check for recurring")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, will check new transactions for occurrences of new monthly expenses.")
                        .font(.caption)
                }
                Section{
                    Toggle(isOn: $skipBalanceUpdate) {
                        HStack {
                            Text("Skip balance update")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, will skip updating balance if an asset_id is present for any of the transactions.")
                        .font(.caption)
                }
					
                
                Section{
                    
                } footer: {
                    Text(.init("See [LunchMoney API](https://lunchmoney.dev/#getting-started) documentation for more information.")).foregroundStyle(.secondary)
                }
            }
			.task {
				do {
					totalTransactionCount = try await syncBroker.countAllTransactions()
				} catch {
					totalTransactionCount = nil
				}
			}
			.alert("Are you sure?", isPresented: $showDeleteConfirmation) {
				Button("Delete", role: .destructive) {
					Task {
						do {
							_ = try await syncBroker.getTransactionsOlderThanDays(remove_old_days, andDelete: true)
							removeOldMatchesCount = 0
							if let newTotal = try? await syncBroker.countAllTransactions() {
								totalTransactionCount = newTotal
							}
						} catch {
							// ignore; UI already reflects attempted deletion
						}
					}
				}
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("This will delete \(removeOldMatchesCount) transaction\(removeOldMatchesCount == 1 ? "" : "s") from LunchSync. This action cannot be undone.")
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
