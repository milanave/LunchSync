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
        // Check if API token is empty and try to retrieve it
        
        do {
            addLog(prefix: prefix, message: "Starting transaction fetch", level: 2)
            
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
            
            let initialPendingCount = wallet.getTransactionsWithStatus(.pending).count
            
            // get a list of accounts, then Apple Wallet transactions for those accounts
            let accounts = wallet.getSyncedAccounts()
            let newTransactions = try await appleWallet.refreshWalletTransactionsForAccounts(accounts: accounts)
            addLog(prefix: prefix, message: "Found \(newTransactions.count) transactions to sync", level: 2)
            
            // update the local store with each of these transactions
            newTransactions.forEach { transaction in
                wallet.replaceTransaction(newTrans: transaction)
            }
            
            // Get and sync account balances
            addLog(prefix: prefix, message: "Getting account balances", level: 2)
            let accountsToUpdate = try await appleWallet.getWalletAccounts()
            try await wallet.syncAccountBalances(accounts: accountsToUpdate)
            /*for acct in accountsToUpdate {
                addLog(prefix: prefix, message: "sync account: \(acct.name) \(acct.id) \(acct.balance)")
            }*/
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
            return 0
        }
    }
    
    public func syncTransactions(prefix: String, progressCallback: @escaping (Wallet.SyncProgress) -> Void) async throws {
        try await wallet.syncTransactions { progress in
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
    
}
