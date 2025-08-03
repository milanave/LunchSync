//
//  SafeSyncBroker.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/3/25.
//
import Foundation
import SwiftData
import SwiftUI



class SafeSyncBroker {
    private let modelContext: ModelContext
    private var apiToken: String
    private var API: LunchMoneyAPI
    private var appleWallet: AppleWallet
    private var logPrefix: String = ""
    
    init(context: ModelContext, logPrefix: String = "") {
        self.modelContext = context
        self.logPrefix = logPrefix
        let keychain = Keychain()
        do{
            self.apiToken = try keychain.retrieveTokenFromKeychain()
        } catch {
            self.apiToken = ""
        }
        self.API = LunchMoneyAPI(apiToken: apiToken, debug: false)
        appleWallet = AppleWallet()
    }
    
    public struct SafeSyncProgress {
        let current: Int
        let total: Int
        let status: String
    }
 
    public func addLog(message: String, level: Int = 1) {
        addLog(prefix: logPrefix, message: message, level: level)
    }
    
    public func addLog(prefix: String, message: String, level: Int = 1) {
        let log = Log(message: "\(prefix): \(message)", level: level)
        modelContext.insert(log)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save log: \(error)")
        }
    }
    
    public func fetchTransactions(prefix: String, showAlert: Bool = false, skipSync: Bool = false, progress: @escaping (String) -> Void) async throws -> Int {
        
        logPrefix = prefix
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")
        let autoImportTransactions = skipSync ? false : sharedDefaults.bool(forKey: "autoImportTransactions")
        
        do {
            addLog(prefix: prefix, message: "Starting transaction fetch (importAsCleared: \(importAsCleared), transStatusInNotes: \(putTransStatusInNotes), autoSync: \(autoImportTransactions))", level: 1)
            
            if apiToken.isEmpty {
                let keychain = Keychain()
                var errorStr = "attempting to fetch token..."
                
                do {
                    apiToken = try keychain.retrieveTokenFromKeychain()
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
            
            let initialPendingCount = getTransactionsWithStatus(.pending).count
            
            addLog(prefix: prefix, message: "got initialPendingCount: \(initialPendingCount)", level: 2)
            
            // get a list of accounts, then Apple Wallet transactions for those accounts
            let accounts = getSyncedAccounts()
            
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
                
                replaceTransaction(newTrans: transaction)
            }

            let pendingCount = getTransactionsWithStatus(.pending).count

            let body = "\(pendingCount) transaction\(pendingCount == 1 ? "" : "s") synced"
            addLog(prefix: prefix, message: "\(body) (4/8)", level: 2)
            if(pendingCount > 0 && pendingCount != initialPendingCount) {
                await addNotification(time: 0.5, title: "Transactions synced", subtitle: "", body: body)
            }else if showAlert {
                await addNotification(time: 0.1, title: "Transactions synced", subtitle: "", body: body)
            }

            if(autoImportTransactions){
                addLog(prefix: prefix, message: "starting import for \(pendingCount) transactions", level: 2)
                try await syncTransactions(prefix: prefix) { SafeSyncProgress in
                    self.addLog(prefix: prefix, message: "syncTransactions \(SafeSyncProgress.status) \(SafeSyncProgress.current)/\(SafeSyncProgress.total)", level: 2)
                }
                addLog(prefix: prefix, message: "auto import done, updating badge count", level: 2)
            } else {
                addLog(prefix: prefix, message: "skipping auto import", level: 2)
            }
                        
            // Get and sync account balances
            addLog(prefix: prefix, message: "Getting account balances", level: 2)
            let accountsToUpdate = try await appleWallet.getWalletAccounts()
            try await syncAccountBalances(accounts: accountsToUpdate)
            for acct in accountsToUpdate {
                addLog(prefix: prefix, message: "sync account: \(acct.name) \(CurrencyFormatter.shared.format(acct.balance))", level: 2)
            }
            
            // update the badge count
            /*
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .pendingTransactionsChanged,
                    object: pendingCount
                )
            }
            */
            
            addLog(prefix: prefix, message: "Sync complete with \(pendingCount) imported", level: 1)
            return pendingCount
        } catch {
            addLog(prefix: prefix, message: "Sync failed with error: \(error.localizedDescription)", level: 1)
            if showAlert {
                await addNotification(time: 0.1, title: "Sync Error", subtitle: "", body: "fetchTransactionsAndSync:\(autoImportTransactions) failed with error: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    func getTransactionsWithStatus(_ status: Transaction.SyncStatus) -> [Transaction] {
        return getTransactionsWithStatus([status])
    }
    
    func getTransactionsWithStatus(_ statuses: [Transaction.SyncStatus]) -> [Transaction] {
        let statusStrings = statuses.map { $0.rawValue }
        
        let fetchDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                statusStrings.contains(transaction.syncStatus)
            }
        )
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch transactions with statuses \(statuses): \(error)")
            return []
        }
    }
    
    func getSyncedAccounts() -> [Account] {
        let fetchDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { account in
                account.sync == true
            }
        )
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch synced accounts: \(error)")
            return []
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
    
    func replaceTransaction(newTrans: Transaction){
        // find a transaction in the local store
        let id = newTrans.id
        let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        //print("replaceTransaction with \(id)")
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            
            if let transaction = transactions.first {
                //print("replaceTransaction matched \(transaction.lm_id)")
                if(
                    newTrans.payee != transaction.payee ||
                    newTrans.amount != transaction.amount ||
                    newTrans.date != transaction.date ||
                    newTrans.notes != transaction.notes ||
                    newTrans.isPending != transaction.isPending ||
                    newTrans.category_id != transaction.category_id ||
                    newTrans.category_name != transaction.category_name ||
                    newTrans.lm_category_id != transaction.lm_category_id
                ){
                    /*
                    print(" -- \(transaction.lm_id) has changes in payee, amount or date")
                    print(" -- -- \(newTrans.payee) != \(transaction.payee) \(newTrans.payee != transaction.payee)")
                    print(" -- -- \(newTrans.amount) != \(transaction.amount) \(newTrans.amount != transaction.amount)")
                    print(" -- -- \(newTrans.date) != \(transaction.date) \(newTrans.date != transaction.date)")
                     */
                    //print(" -- -- \(newTrans.category_id ?? "n/a") != \(transaction.category_id ?? "n/a") \(newTrans.category_name ?? "n/a" != transaction.category_name ?? "n/a")")
                    transaction.payee = newTrans.payee
                    transaction.amount = newTrans.amount
                    transaction.date = newTrans.date
                    transaction.notes = newTrans.notes
                    transaction.lm_id = newTrans.lm_id
                    transaction.lm_account = newTrans.lm_account
                    transaction.sync = .pending
                    transaction.isPending = newTrans.isPending
                    transaction.category_id = newTrans.category_id
                    transaction.category_name = newTrans.category_name
                    transaction.lm_category_id = newTrans.lm_category_id
                    transaction.lm_category_name = newTrans.lm_category_name
                }
                //else{
                    //print(" -- \(transaction.payee) \(transaction.amount) has no changes: \(transaction.id)")
                //}
            }else{
                //print("replaceTransaction insert new \(newTrans.payee)")
                modelContext.insert(newTrans)
            }
        } catch {
            print("error searching")
        }
        try? modelContext.save() // Save after making updates
           
    }
    
    func addNotification(time: Double, title: String, subtitle: String, body: String) async {
        //print("addNotification \(title), \(body)")
        let center = UNUserNotificationCenter.current()
        
        // First check current authorization status
        let settings = await center.notificationSettings()
        //print("Notification settings: \(settings.authorizationStatus.rawValue)")
        
        guard settings.authorizationStatus == .authorized else {
            print("Notifications not authorized")
            return
        }
        
        // Create and add notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = UNNotificationSound.default
        
        // Add category identifier and increase interruption level
        content.categoryIdentifier = "TRANSACTION_UPDATE"
        //content.interruptionLevel = .timeSensitive  // Makes notification more likely to appear
        
        // For debugging, use a shorter time interval
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, time), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        do {
            try await center.add(request)
            //print("Notification scheduled successfully for \(Date().addingTimeInterval(time))")
            
            // Debug: List pending notifications
            _ = await center.pendingNotificationRequests()
            //print("Pending notifications: \(pending.count)")
            
            // Debug: List delivered notifications
            _ = await center.deliveredNotifications()
            //print("Delivered notifications: \(delivered.count)")
        } catch {
            print("Error scheduling notification: \(error)")
        }
    }
    
    public func syncTransactions(
        prefix: String,
        shouldContinue: @escaping () -> Bool = { true },
        progressCallback: @escaping (SafeSyncProgress) -> Void
    ) async throws {
        try await syncTransactions { progress in
            guard shouldContinue() else {
                return
            }
            progressCallback(progress)
        }
    }
    
    func syncTransactions(progressCallback: @escaping (SafeSyncProgress) -> Void) async throws {
        let pendingTransactions = getTransactionsWithStatus(.pending)
        let total = pendingTransactions.count
        var current = 0
        
        // Initial progress update
        progressCallback(SafeSyncProgress(
            current: 0,
            total: total,
            status: "Starting sync..."
        ))
        
        for transaction in pendingTransactions {
            current += 1
            
            // Update progress before each transaction
            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Syncing \(current) of \(total) for \(transaction.payee)"
            ))
            
            let matchingAccount = self.getSyncedAccounts().first(where: { $0.id == transaction.accountID })
            transaction.lm_account = matchingAccount?.lm_id ?? "0"
            
            // go into an infinite loop to sync the transaction
            var retryCount = 0
            while true {
                do {
                    let updatedTransaction = try await performSync(transaction: transaction)
                    replaceTransaction(newTrans: updatedTransaction)
                    break  // Break out of the while loop instead of returning
                } catch {
                    retryCount += 1
                    print("Error in syncTransaction: \(error) with \(current) of \(total), retry \(retryCount)")
                    addLog(message: "syncTransaction, error \(error) for \(transaction.id), retrying...", level: 2)
                    
                    progressCallback(SafeSyncProgress(
                        current: current,
                        total: total,
                        status: "Error with \(current) of \(total), retry \(retryCount)"
                    ))
                    
                    // Wait 2 seconds before retrying
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            
            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Completed \(current) of \(total)"
            ))

        }
        
        try modelContext.save()
    }
    
    private func performSync(transaction: Transaction) async throws -> Transaction {
        //debug = true
        //print("syncTransaction \(transaction.id)")
        
        // find an asset id and match it, otherwise die
        /*
        //print("DEBUG: Transaction details:")
            //print("- ID: \(transaction.id)")
            //print("- Date: \(transaction.date)")
            //print("- Payee: \(transaction.payee)")
            //print("- Amount: \(transaction.amount)")
            //print("- Notes: \(transaction.notes)")
            //print("- Status: \(transaction.status)")
            //print("- Is Pending: \(transaction.isPending)")
            //print("- LM Account: \(transaction.lm_account)")
            //print("- LM ID: \(transaction.lm_id)")
            //print("- Sync Status: \(transaction.sync)")
            fatalError("Stopping execution for debugging")
        */
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let calendar = Calendar.current
        let transactionDate = transaction.date
        guard let thirtyDaysBefore = calendar.date(byAdding: .day, value: -30, to: transactionDate),
              let thirtyDaysAfter = calendar.date(byAdding: .day, value: 30, to: transactionDate) else {
            print("Error calculating date range")
            addLog(message: "syncTransaction, Error calculating date range for \(transaction.id)", level: 2)
            transaction.sync = .never // TODO, pass this as an error instead?
            return transaction
        }
        
        let startDate = dateFormatter.string(from: thirtyDaysBefore)
        let endDate = dateFormatter.string(from: thirtyDaysAfter)
        let dateString = dateFormatter.string(from: transaction.date)
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")
        let applyRules = sharedDefaults.bool(forKey: "apply_rules")
        let skipDuplicates = sharedDefaults.bool(forKey: "skip_duplicates")
        let checkForRecurring = sharedDefaults.bool(forKey: "check_for_recurring")
        let skipBalanceUpdate = sharedDefaults.bool(forKey: "skip_balance_update")
        
        do {
            // First check for existing transactions
            let existingTransactions = try await API.getTransactions(
                request: GetTransactionsRequest(
                    startDate: startDate,
                    endDate: endDate
                )
            )
            
            // Check if transaction already exists
            for trn in existingTransactions {
                if trn.externalId == transaction.id {
                    //print("Matching \(String(describing: trn.externalId)) to existing transaction \(trn.id)")
                    
                    
                    let updateRequest = UpdateTransactionRequest(
                        transaction: UpdateTransactionRequest.TransactionUpdate(
                            date: dateString,
                            payee: transaction.payee,
                            amount: String(format: "%.2f", transaction.amount),
                            currency: "usd",
                            categoryId: transaction.lm_category_id != nil ? Int(transaction.lm_category_id!) : nil,
                            assetId: Int(transaction.lm_account),
                            notes: putTransStatusInNotes ? (transaction.notes.isEmpty ? nil : transaction.notes) : nil,
                            status: importAsCleared ? "cleared" : "uncleared",
                            externalId: transaction.id,
                            isPending: false //transaction.isPending
                        )
                    )
                    
                    // Call API to update the transaction
                    let result = try await API.updateTransaction(id: trn.id, request: updateRequest)
                    
                    if let errors = result.errors {
                        print("Failed to send transaction to LM: \(errors.joined(separator: ", "))")
                        addLog(message: "syncTransaction, Failed to send transaction to LM for \(transaction.id), \(errors.joined(separator: ", "))", level: 2)
                        // don't stop it from being re-synced this time
                        //transaction.sync = .never
                        return transaction
                    } else {
                        addLog(message: "synced \(transaction.payee), \(CurrencyFormatter.shared.format(transaction.amount))", level: 2)
                        //print("Transaction sent to LM: updated=\(result.updated ?? false)")
                        transaction.lm_id = String(trn.id)
                        if let assetId = trn.assetId {
                            transaction.lm_account = String(assetId)
                        } else {
                            transaction.lm_account = ""
                        }
                        transaction.sync = .complete
                        return transaction
                    }
                }
            }
            
            //print("did NOT find matching transactions, creating new one...")
            let createRequest = CreateTransactionRequest(
                date: dateString,
                payee: transaction.payee,
                amount: String(format: "%.2f", transaction.amount),
                currency: "usd",
                categoryId: transaction.lm_category_id != nil ? Int(transaction.lm_category_id!) : nil,
                assetId: Int(transaction.lm_account),
                notes: putTransStatusInNotes ? (transaction.notes.isEmpty ? nil : transaction.notes) : nil,
                status: importAsCleared ? "cleared" : "uncleared",
                externalId: transaction.id,
                isPending: false //transaction.isPending
            )
            
            // Create new transaction
            let response = try await API.createTransactions(
                transactions: [createRequest],
                applyRules: applyRules,
                skipDuplicates: skipDuplicates,
                checkForRecurring: checkForRecurring,
                skipBalanceUpdate: skipBalanceUpdate
            )
            
            if let transactionIds = response.transactionIds, !transactionIds.isEmpty {
                transaction.lm_id = String(transactionIds[0])
                transaction.sync = .complete
                //print("Inserted \(transaction.lm_id) -> \(transaction.sync)")
                addLog(message: "syncTransaction, synced to LM for \(transaction.id), status=\(importAsCleared ? "cleared" : "uncleared")", level: 2)
            } else {
                //print("No transaction ID received in response")
                addLog(message: "syncTransaction, No transaction ID received in response for \(transaction.id)", level: 2)
                transaction.sync = .never
            }
            
            return transaction
        } catch {
            print("Error in syncTransaction: \(error)")
            addLog(message: "syncTransaction, error \(error) for \(transaction.id)", level: 2)
            transaction.sync = .never
            throw error
        }
    }
    
    func syncAccountBalances(accounts: [Account]) async throws {
        let syncedAccounts = getSyncedAccounts()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for acct in accounts {
            //print("syncAccounts \(acct.name) \(acct.id) \(acct.balance)")
            replaceAccount(newAccount: acct, propertiesToUpdate: ["balance", "lastUpdated"])
            updateAccountBalance(accountId: acct.id, balance: acct.balance, lastUpdated: acct.lastUpdated)

            if let matchingAccount = syncedAccounts.first(where: { $0.id == acct.id }),
               let lmId = Int(matchingAccount.lm_id) { // Safely unwrap lm_id
                //print("Found synced account: \(matchingAccount.name) (ID: \(matchingAccount.id))")
                let today = dateFormatter.string(from: acct.lastUpdated)
                let request = UpdateAssetRequest(
                    balance: acct.balance,
                    balanceAsOf: today
                )
                //print("Sending balance: \(acct.balance) to \(lmId)")
                let _ = try await self.API.updateAsset(id: lmId, request: request)
            }
        }
        
    }
    
    // a new Account is being passed in from Apple, create an Asset in LM and set the lm_id
    func replaceAccount(newAccount: Account, propertiesToUpdate: [String]? = nil) {
        let id = newAccount.id
        let fetchDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        
        do {
            let accounts = try modelContext.fetch(fetchDescriptor)
            if let account = accounts.first {
                if let properties = propertiesToUpdate {
                    // Only update specified properties
                    for property in properties {
                        switch property {
                        case "name":
                            account.name = newAccount.name
                        case "balance":
                            account.balance = newAccount.balance
                        case "lm_id":
                            account.lm_id = newAccount.lm_id
                        case "lm_name":
                            account.lm_name = newAccount.lm_name
                        case "sync":
                            account.sync = newAccount.sync
                        case "lastUpdated":
                            account.lastUpdated = newAccount.lastUpdated
                        default:
                            print("Unknown property: \(property)")
                        }
                    }
                    //print("Update \(account.id) ->  \(account.lm_id) to \(newAccount.lm_id)")
                } else {
                    // Update all properties when propertiesToUpdate is nil
                    account.name = newAccount.name
                    account.balance = newAccount.balance
                    account.lm_id = newAccount.lm_id
                    account.lm_name = newAccount.lm_name
                    account.sync = newAccount.sync
                    account.lastUpdated = newAccount.lastUpdated
                    //print("Updated all properties for account \(account.id)")
                }
            } else {
                //print("Insert")
                modelContext.insert(newAccount)
            }
        } catch {
            //print("Error searching for account")
        }
        try? modelContext.save()
    }
    
    func updateAccountBalance(accountId: String, balance: Double, lastUpdated: Date){
        let fetchDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountId })
        
        do {
            let accounts = try modelContext.fetch(fetchDescriptor)
            if let account = accounts.first {
                account.balance = balance
                account.lastUpdated = lastUpdated
            }
        }catch{
            //print("Error searching for account")
        }
        try? modelContext.save()
    }
}
