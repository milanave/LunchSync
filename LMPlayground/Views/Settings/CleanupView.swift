//
//  APIImportRulesView.swift
//  LMPlayground
//
//  Created by AI Assistant on 1/9/26.
//

import SwiftUI

struct CleanupView: View {
    @Environment(\.modelContext) private var modelContext
    private var syncBroker: SyncBroker { SyncBroker(context: modelContext, logPrefix: "ST") }
    
    @AppStorage("remove_old_transactions", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var remove_old_transactions = false
    @AppStorage("remove_old_days", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var remove_old_days = 90

    @State private var removeOldMatchesCount: Int = 0
    @State private var totalTransactionCount: Int? = nil
    @State private var showDeleteConfirmation: Bool = false

    
    var body: some View {
        List{
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
                Text("LunchSync keeps a record of transactions that are synced to LunchMoney. Once synced, it is safe to remove them from LunchSync. Remove them manually below, or select a time frame to remove them automatically.")
            } footer: {
                Text("Transactions in will be removed from LunchSync automatically, but will remain in LunchMoney. LunchSync currently has: \(totalTransactionCount ?? 0) transactions in its database.")
                    .font(.caption)
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
        .navigationTitle("Remove Old Transactions")
    }
}

#Preview {
    NavigationView {
        CleanupView()
    }
}


