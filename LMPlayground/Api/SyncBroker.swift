//
//  SyncBroker.swift
//  LMPlayground
//
//  Created by Bob Sanders on 12/8/24.
//
import Foundation
import SwiftData
import SwiftUI

@MainActor
class SyncBroker {
    private let modelContext: ModelContext
    private var wallet: Wallet
    private var appleWallet: AppleWallet
    private var lastLogTime: Date?
    private var apiToken: String
    
    init(context: ModelContext) {
        self.modelContext = context
        self.lastLogTime = Date()
        let keychain = Keychain()
        do{
            print("SyncBroker init retrieveTokenFromKeychain")
            self.apiToken = try keychain.retrieveTokenFromKeychain()
        } catch {
            self.apiToken = ""
        }
        
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            wallet = MockWallet(context: context, apiToken: "mock-token")
            appleWallet = MockAppleWallet()
        } else {
            wallet = Wallet(context: context, apiToken: self.apiToken)
            appleWallet = AppleWallet()
        }
        #else
        wallet = Wallet(context: context, apiToken: self.apiToken)
        appleWallet = AppleWallet()
        #endif
    }
    
    public func fetchTransactions(prefix: String, andSync: Bool, showAlert: Bool = false, progress: @escaping (String) -> Void) async throws -> Int {
        print("----------------- starting fetchTransactions")
        // Check if API token is empty and try to retrieve it
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")

        do {
            addLog(prefix: prefix, message: "Starting transaction fetch (importAsCleared: \(importAsCleared), transStatusInNotes: \(putTransStatusInNotes), autoSync: \(andSync))", level: 2)
            
            if apiToken.isEmpty {
                let keychain = Keychain()
                var errorStr = "attempting to fetch token..."
                
                do {
                    let apiToken = try keychain.retrieveTokenFromKeychain()
                    wallet.updateAPIToken(apiToken)
                } catch KeychainError.itemNotFound {
                    errorStr = "Keychain item not found."
                } catch KeychainError.unableToConvertData {
                    errorStr = "Failed to convert Keychain data to a string."
                } catch KeychainError.unexpectedStatus(let status) {
                    errorStr = "Unexpected Keychain status: \(status)."
                } catch {
                    errorStr = "An unknown error occurred: \(error)."
                }
                
                if apiToken.isEmpty {
                    addLog(prefix: prefix, message: "error getting token \(errorStr)", level: 1)
                    return 0
                }
                addLog(prefix: prefix, message: "token was blank, but successfully retrieved", level: 2)
            }
            
            addLog(prefix: prefix, message: "token rertrieved", level: 2)
            
            let initialPendingCount = wallet.getTransactionsWithStatus(.pending).count
            
            addLog(prefix: prefix, message: "got initialPendingCount: \(initialPendingCount)", level: 2)
            
            // get a list of accounts, then Apple Wallet transactions for those accounts
            let accounts = wallet.getSyncedAccounts()
            
            addLog(prefix: prefix, message: "got accounts: \(accounts.count)", level: 2)
            
            let newTransactions = try await appleWallet.refreshWalletTransactionsForAccounts(accounts: accounts)
            addLog(prefix: prefix, message: "Found \(newTransactions.count) transactions to sync", level: 2)
            
            //print("DEBUG: About to process \(newTransactions.count) transactions")
            
            // Process MCCs and create category mappings
            let trnCategoryMap = try await processMCCCategories(transactions: newTransactions, prefix: prefix)
            
            // Now process each transaction with the category mapping
            newTransactions.forEach { transaction in
                // If we have a category mapping and it has a linked LMCategory, set the transaction's lm_category_id
                if let categoryId = transaction.category_id,
                   let trnCategory = trnCategoryMap[categoryId],
                   let lmCategory = trnCategory.lm_category {
                    transaction.lm_category_id = lmCategory.id
                    transaction.lm_category_name = lmCategory.name
                }
                
                wallet.replaceTransaction(newTrans: transaction)
            }

            let pendingCount = wallet.getTransactionsWithStatus(.pending).count

            let body = "\(pendingCount) transaction\(pendingCount == 1 ? "" : "s") synced"
            addLog(prefix: prefix, message: "\(body) (4/8)", level: 2)
            if(pendingCount > 0 && pendingCount != initialPendingCount) {
                await wallet.addNotification(time: 0.5, title: "Transactions synced", subtitle: "", body: body)
            }else if showAlert {
                await wallet.addNotification(time: 0.1, title: "Transactions synced", subtitle: "", body: body)
            }

            if(andSync){
                addLog(prefix: prefix, message: "starting import for \(pendingCount) transactions", level: 2)
                try await syncTransactions(prefix: prefix) { syncProgress in
                    self.addLog(prefix: prefix, message: "syncTransactions \(syncProgress.status) \(syncProgress.current)/\(syncProgress.total)", level: 2)
                }
                addLog(prefix: prefix, message: "auto import done, updating badge count", level: 2)
            } else {
                addLog(prefix: prefix, message: "skipping auto import", level: 2)
            }
                        
            // Get and sync account balances
            addLog(prefix: prefix, message: "Getting account balances", level: 2)
            let accountsToUpdate = try await appleWallet.getWalletAccounts()
            try await wallet.syncAccountBalances(accounts: accountsToUpdate)
            for acct in accountsToUpdate {
                addLog(prefix: prefix, message: "sync account: \(acct.name) \(acct.balance)", level: 2)
            }
            
            // update the badge count
            NotificationCenter.default.post(
                name: .pendingTransactionsChanged,
                object: pendingCount
            )
            addLog(prefix: prefix, message: "Sync complete with \(pendingCount) imported", level: 1)
            return pendingCount
        } catch {
            addLog(prefix: prefix, message: "Sync failed with error: \(error.localizedDescription)", level: 1)
            if showAlert {
                await wallet.addNotification(time: 0.1, title: "Sync Error", subtitle: "", body: "fetchTransactionsAndSync:\(andSync) failed with error: \(error.localizedDescription)")
            }
            throw error
            //return 0
        }
    }
    
    public func syncTransactions(
        prefix: String,
        shouldContinue: @escaping () -> Bool = { true },
        progressCallback: @escaping (Wallet.SyncProgress) -> Void
    ) async throws {
        try await wallet.syncTransactions { progress in
            guard shouldContinue() else {
                return
            }
            progressCallback(progress)
        }
    }
    
    public func addLog(prefix: String, message: String, level: Int = 1) {
        let now = Date()
        var fullMessage = "\(prefix): \(message)"
        
        if let lastTime = lastLogTime {
            let timeDiff = now.timeIntervalSince(lastTime)
            let hours = Int(timeDiff) / 3600
            let minutes = Int(timeDiff) / 60 % 60
            let seconds = Int(timeDiff) % 60
            if(seconds>1){
                fullMessage += String(format: " (%02d:%02d:%02d)", hours, minutes, seconds)
            }
        }
        
        let log = Log(message: fullMessage, level: level)
        modelContext.insert(log)
        
        do {
            try modelContext.save()
            lastLogTime = now
        } catch {
            print("Failed to save log: \(error)")
        }
    }
    
    private func processMCCCategories(transactions: [Transaction], prefix: String) async throws -> [String: TrnCategory] {
        // Collect all unique MCC codes and create missing TrnCategories
        let uniqueMCCs = Set(transactions.compactMap { $0.category_id?.isEmpty == false ? $0.category_id : nil })
        print("Processing \(uniqueMCCs.count) unique MCCs: \(Array(uniqueMCCs).sorted())")
        
        var trnCategoryMap: [String: TrnCategory] = [:]
        var foundCount = 0
        var createdCount = 0
        
        for mcc in uniqueMCCs {
            let fetchDescriptor = FetchDescriptor<TrnCategory>(
                predicate: #Predicate<TrnCategory> { $0.mcc == mcc }
            )
            
            do {
                let existingCategories = try modelContext.fetch(fetchDescriptor)
                
                if let existingCategory = existingCategories.first {
                    trnCategoryMap[mcc] = existingCategory
                    foundCount += 1
                    print("Found existing TrnCategory - MCC: \(existingCategory.mcc), Name: \(existingCategory.name)")
                } else {
                    // Find the transaction with this MCC to get the category name
                    if let sampleTransaction = transactions.first(where: { $0.category_id == mcc }) {
                        let newTrnCategory = TrnCategory(
                            mcc: mcc,
                            name: sampleTransaction.category_name ?? "Unknown Category"
                        )
                        modelContext.insert(newTrnCategory)
                        trnCategoryMap[mcc] = newTrnCategory
                        createdCount += 1
                        addLog(prefix: prefix, message: "Created new TrnCategory for MCC: \(mcc), name: \(sampleTransaction.category_name ?? "Unknown Category")", level: 2)
                        print("Created new TrnCategory for MCC: \(mcc), name: \(sampleTransaction.category_name ?? "Unknown Category")")
                    }
                }
            } catch {
                addLog(prefix: prefix, message: "Error checking/creating TrnCategory for MCC \(mcc): \(error)", level: 1)
            }
        }
        
        // Save all new categories at once
        do {
            try modelContext.save()
            print("TrnCategory summary: Found \(foundCount), Created \(createdCount), Total \(foundCount + createdCount)")
        } catch {
            print("Failed to save TrnCategories: \(error)")
            throw error
        }
        
        return trnCategoryMap
    }
    
}
