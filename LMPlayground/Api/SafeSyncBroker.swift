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
    
    // MARK main import function
    public func fetchTransactions(prefix: String, showAlert: Bool = false, skipSync: Bool = false, progress: @escaping (String) -> Void) async throws -> Int {
        
        logPrefix = prefix
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")
        let autoImportTransactions = skipSync ? false : sharedDefaults.bool(forKey: "autoImportTransactions")
        
        let categorize_incoming = sharedDefaults.object(forKey: "categorize_incoming") == nil ? true : sharedDefaults.bool(forKey: "categorize_incoming")
        let alert_after_import = sharedDefaults.object(forKey: "alert_after_import") == nil ? true : sharedDefaults.bool(forKey: "alert_after_import")
        
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
            
            //let initialPendingCount = getTransactionsWithStatus(.pending).count
            //addLog(prefix: prefix, message: "got initialPendingCount: \(initialPendingCount)", level: 2)
            
            // get a list of accounts, then Apple Wallet transactions for those accounts
            let accounts = getSyncedAccounts()
            
            addLog(prefix: prefix, message: "got accounts: \(accounts.count) to sync", level: 2)
            
            let newTransactions = try await appleWallet.refreshWalletTransactionsForAccounts(accounts: accounts)
            addLog(prefix: prefix, message: "found \(newTransactions.count) transactions to sync", level: 2)
            
            // Process MCCs and create category mappings
            if(categorize_incoming){
                let trnCategoryMap = try processMCCCategories(transactions: newTransactions, prefix: prefix)
                addLog(prefix: prefix, message: "processing \(trnCategoryMap.count) mcc categories", level: 2)
                
                // Now process each transaction with the category mapping
                newTransactions.forEach { transaction in
                    // If we have a category mapping and it has a linked LMCategory, set the transaction's lm_category_id
                    if let categoryId = transaction.category_id,
                       let trnCategory = trnCategoryMap[categoryId] {
                        if( !trnCategory.lm_id.isEmpty && trnCategory.lm_id != "0" ){
                            transaction.lm_category_id = trnCategory.lm_id
                            transaction.lm_category_name = trnCategory.lm_name
                        }
                    }
                    replaceTransaction(newTrans: transaction)
                }
            }
            

            let transactionsToSyncCount = getTransactionsWithStatus(.pending).count
            addLog(prefix: prefix, message: "\(transactionsToSyncCount) transactions ready to sync", level: 2)
            
            if(autoImportTransactions){
                addLog(prefix: prefix, message: "starting import for \(transactionsToSyncCount) transactions", level: 2)
                try await syncTransactions(prefix: prefix) { SafeSyncProgress in
                    self.addLog(prefix: prefix, message: "syncTransactions \(SafeSyncProgress.status) \(SafeSyncProgress.current)/\(SafeSyncProgress.total)", level: 2)
                }
                addLog(prefix: prefix, message: "auto import complete", level: 2)
            } else {
                addLog(prefix: prefix, message: "skipping auto import", level: 2)
            }
                        
            let finalPendingCount = getTransactionsWithStatus(.pending).count
            
            // Get and sync account balances
            addLog(prefix: prefix, message: "Updating account balances", level: 2)
            let accountsToUpdate = try await appleWallet.getWalletAccounts()
            try await syncAccountBalances(accounts: accountsToUpdate)
            for acct in accountsToUpdate {
                addLog(prefix: prefix, message: "sync account: \(acct.name) \(CurrencyFormatter.shared.format(acct.balance))", level: 2)
            }
            
            // get number of unmapped categories
            addLog(prefix: prefix, message: "Updating badge counts", level: 2)
            let fetchDescriptor = FetchDescriptor<TrnCategory>(
                predicate: #Predicate<TrnCategory> { $0.lm_id == "" }
            )
            let uncategorizedCount = (try? modelContext.fetch(fetchDescriptor).count) ?? 0
            
            var body = ""
            if(transactionsToSyncCount == 0 && uncategorizedCount == 0){
                // no alert needed
                
            }else if(transactionsToSyncCount > 0 && uncategorizedCount == 0){
                body = "\(transactionsToSyncCount) transaction\(transactionsToSyncCount == 1 ? "" : "s") synced"
            }else if(transactionsToSyncCount > 0 && uncategorizedCount > 0){
                body = "\(transactionsToSyncCount) transaction\(transactionsToSyncCount == 1 ? "" : "s") synced, \(uncategorizedCount) categories that need mapping"
            }else if(transactionsToSyncCount == 0 && uncategorizedCount > 0){
                body = "\(uncategorizedCount) categories that need mapping"
            }
            
            // update the badge count
            addLog(prefix: prefix, message: "Updating badge count to \(finalPendingCount+uncategorizedCount)", level: 2)
            updateBadgeCounts(count:finalPendingCount+uncategorizedCount)
                    
            if( body.isEmpty ){
                addLog(prefix: prefix, message: "Sync complete, pending=\(finalPendingCount), uncategorized=\(uncategorizedCount)", level: 2)
            }else{
                addLog(prefix: prefix, message: body, level: 2)
                if showAlert {
                    if(alert_after_import){
                        await addNotification(time: 0.5, title: "Transactions synced", subtitle: "", body: body)
                    }
                }
            }
            
            
            
            if let storedDeviceToken = sharedDefaults.string(forKey: "deviceToken") {
                await registerWalletCheck(deviceToken: storedDeviceToken)
                addLog( prefix: logPrefix, message: "registerWalletCheck complete", level: 2)
            }else{
                addLog( prefix: logPrefix, message: "registerWalletCheck failed, no deviceToken", level: 1)
            }
            
            addLog(prefix: prefix, message: "Sync complete with \(finalPendingCount) imported", level: 1)
            return finalPendingCount
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
    
    private func updateBadgeCounts(count: Int){
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Error setting badge count: \(error)")
            }
        }
    }
    
    private func processMCCCategories(transactions: [Transaction], prefix: String) throws -> [String: TrnCategory] {
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
        
        try modelContext.save()
        //print("TrnCategory summary: Found \(foundCount), Created \(createdCount), Total \(foundCount + createdCount)")
        
        return trnCategoryMap
    }
    
    func replaceTransaction(newTrans: Transaction){
        // find a transaction in the local store
        let id = newTrans.id
        let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
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
                    var changes: [String] = []
                    
                    if newTrans.payee != transaction.payee { changes.append("payee = \(newTrans.payee)") }
                    if newTrans.amount != transaction.amount { changes.append("amount = \(CurrencyFormatter.shared.format(newTrans.amount))") }
                    let noteDate = dateFormatter.string(from: newTrans.date)
                    if newTrans.date != transaction.date { changes.append("date = \(noteDate)") }
                    if newTrans.notes != transaction.notes { changes.append("notes = \(newTrans.notes)") }
                    if newTrans.isPending != transaction.isPending { changes.append("pending = \(newTrans.isPending)") }
                    if newTrans.category_name != transaction.category_name { changes.append("category = \(newTrans.category_name ?? "nil")") }
                    
                    let changeSummary = changes.joined(separator: ", ")
                    if !changeSummary.isEmpty {
                        transaction.addHistory(note: changeSummary)
                    }
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
                newTrans.addHistory(note: "Created")
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
        content.interruptionLevel = .timeSensitive  // Makes notification more likely to appear
        
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
                transaction.addHistory(note: "Synced to LM")
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
            transaction.addHistory(note: "Error syncing to LM: \(error)")
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
    
    func registerWalletCheck(deviceToken: String) async {
        guard let url = URL(string: "https://push.littlebluebug.com/register.php") else {
            print("Invalid URL for wallet check")
            return
        }
        
        guard let pushServiceKey = Bundle.main.infoDictionary?["PUSH_SERVICE_KEY"] as? String ??
                Bundle.main.object(forInfoDictionaryKey: "INFOPLIST_KEY_PUSH_SERVICE_KEY") as? String else{
            print("Unable to get PUSH_SERVICE_KEY")
            return
        }
        
        #if DEBUG
        let environment = "Test"
        #else
        let environment = "Production"
        #endif
        
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let versionString = "\(appVersion) (\(buildNumber))"
        let osVersionString = ProcessInfo.processInfo.operatingSystemVersionString        
        
        let payload = [
            "device_token": deviceToken,
            "app_id": "WalletSync",
            "key": pushServiceKey,
            "environment": environment,
            "action_id": logPrefix == "BGD" ? "bgd_complete" : "push_received",
            "app_version": versionString,
            "os_version": osVersionString
        ] as [String : Any]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PushRegistrationResponse.self, from: data)
            print("Wallet check registration status: \(response.status)")
        } catch {
            print("Error in wallet check registration: \(error.localizedDescription)")
        }
    }
}
