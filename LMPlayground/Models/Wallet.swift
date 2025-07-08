import Foundation
import SwiftData
import Combine
import UserNotifications

@MainActor
class Wallet :ObservableObject {
    private let modelContext: ModelContext
    private var API: LunchMoneyAPI
    private var lastLogTime: Date?
    
    var isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    init(context: ModelContext, apiToken: String) {
        self.modelContext = context
        self.API = LunchMoneyAPI(apiToken: apiToken, debug: false)
    }
    
    func updateAPIToken(_ token: String) {
        self.API = LunchMoneyAPI(apiToken: token, debug: false)
    }
    
    func getAPIAccountName() async throws -> String{
        let userInfo = try await API.getUser()
        return userInfo.userName
    }
    
    // Add this type to handle progress updates
    struct SyncProgress {
        let current: Int
        let total: Int
        let status: String
    }
    
    // take an Apple Wallet transaction, store it, then add it via the API and save the id
    func syncTransactions(progressCallback: @escaping (SyncProgress) -> Void) async throws {
        let pendingTransactions = getTransactionsWithStatus(.pending)
        let total = pendingTransactions.count
        var current = 0
        
        // Initial progress update
        await MainActor.run {
            progressCallback(SyncProgress(
                current: 0,
                total: total,
                status: "Starting sync..."
            ))
        }
        
        for transaction in pendingTransactions {
            current += 1
            
            // Update progress before each transaction
            await MainActor.run {
                progressCallback(SyncProgress(
                    current: current,
                    total: total,
                    status: "Syncing \(current) of \(total) for \(transaction.payee)"
                ))
            }
            
            let matchedLMAccount = await MainActor.run {
                if let matchingAccount = getSyncedAccounts().first(where: { $0.id == transaction.accountID }) {
                    return matchingAccount.lm_id
                }
                fatalError("Couldn't find asset id for \(transaction.id) with account id \(transaction.accountID)")
            }
            
            await MainActor.run {
                transaction.lm_account = matchedLMAccount
            }
            
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
                    
                    await MainActor.run {
                        progressCallback(SyncProgress(
                            current: current,
                            total: total,
                            status: "Error with \(current) of \(total), retry \(retryCount)"
                        ))
                    }
                    
                    // Wait 2 seconds before retrying
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            
            
            
            
            // Update progress after each transaction
            await MainActor.run {
                progressCallback(SyncProgress(
                    current: current,
                    total: total,
                    status: "Completed \(current) of \(total)"
                ))
            }
        }
        
        try modelContext.save()
    }
    
    // all this does is take an array of Accounts (from Apple) and store/update each locally
    func syncAccountBalances(accounts: [Account]) async throws {
        let syncedAccounts = getSyncedAccounts()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        try await withThrowingTaskGroup(of: Void.self) { group in
            for acct in accounts {
                group.addTask {
                    //print("syncAccounts \(acct.name) \(acct.id) \(acct.balance)")
                    await MainActor.run {
                        self.replaceAccount(newAccount: acct, propertiesToUpdate: ["balance", "lastUpdated"])
                        self.updateAccountBalance(accountId: acct.id, balance: acct.balance, lastUpdated: acct.lastUpdated)
                    }

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
            try await group.waitForAll()
        }
    }
    
    // add a transaction to the local store
    func addTransaction(id: String, account: String, payee: String, amount: Double, date: Date, lm_id: String, lm_account: String) {
        let transaction = Transaction(id: id, account: account, payee: payee, amount: amount, date: date, lm_id: lm_id, lm_account: lm_account )
        replaceTransaction(newTrans: transaction)
    }
    
    // add an account to the local store
    func addAccount(account: Account){
        let account = Account(id: account.id, name: account.name, balance: account.balance, lm_id: account.lm_id, lm_name: account.lm_name)
        modelContext.insert(account)
        try? modelContext.save() // Save the new transaction
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
                    newTrans.isPending != transaction.isPending
                ){
                    /*
                    print(" -- \(transaction.lm_id) has changes in payee, amount or date")
                    print(" -- -- \(newTrans.payee) != \(transaction.payee) \(newTrans.payee != transaction.payee)")
                    print(" -- -- \(newTrans.amount) != \(transaction.amount) \(newTrans.amount != transaction.amount)")
                    print(" -- -- \(newTrans.date) != \(transaction.date) \(newTrans.date != transaction.date)")
                     */
                    transaction.payee = newTrans.payee
                    transaction.amount = newTrans.amount
                    transaction.date = newTrans.date
                    transaction.notes = newTrans.notes
                    transaction.lm_id = newTrans.lm_id
                    transaction.lm_account = newTrans.lm_account
                    transaction.sync = .pending
                    transaction.isPending = newTrans.isPending
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
    
    func setSyncStatus(newTrans: Transaction, newStatus: Transaction.SyncStatus){
        newTrans.sync = newStatus
        try? modelContext.save() // Save after making updates
    }
    
    func updateTransaction(id: String, account: String?, payee: String?, amount: Double?, date: Date?, lm_id: String?) {
        let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            if let transaction = transactions.first {
                // Update properties directly
                if let account = account {
                    transaction.account = account
                }
                if let payee = payee {
                    transaction.payee = payee
                }
                if let amount = amount {
                    transaction.amount = amount
                }
                if let date = date {
                    transaction.date = date
                }
                if let lm_id = lm_id {
                    transaction.lm_id = lm_id
                }
                try? modelContext.save() // Save after making updates
            }
        } catch {
            print("Failed to fetch transaction with id \(id): \(error)")
        }
    }
    
    func deleteTransaction(id: String) {
        let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            if let transaction = transactions.first {
                modelContext.delete(transaction)
                try? modelContext.save() // Save after deletion
            }
        } catch {
            print("Failed to fetch transaction with id \(id): \(error)")
        }
    }
    
    func getTransactions() -> [Transaction] {
        let fetchDescriptor = FetchDescriptor<Transaction>()
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch transactions: \(error)")
            return []
        }
    }
    
    func getAccounts() -> [Account] {
        let fetchDescriptor = FetchDescriptor<Account>()
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch accounts: \(error)")
            return []
        }
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
    
    // Keep old method for backward compatibility, but have it use the new implementation
    func getTransactionsWithStatus(_ status: Transaction.SyncStatus) -> [Transaction] {
        return getTransactionsWithStatus([status])
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
    
    func createAsset(name:String, institutionName:String, note:String) async -> Bool{
        let assetRequest = CreateAssetRequest(
            typeName: "cash", // cash, credit, investment, other, real estate, loan, vehicle, cryptocurrency, employee compensation
            balance: 0.0,
            currency: "usd",
            name: name,
            institutionName: institutionName,
            createdAt: "2024-10-27",
            note: note
        )

        do {
            _ = try await API.createAsset(requestBody: assetRequest)
            //print("Asset created with ID: \(assetResponse.assetId)")
            return true
        } catch {
            print("Error creating asset: \(error)")
        }
        return false
    }
    
    /*
     Takes a Transaction and attempts to sync it with the LM API
     */
    func syncTransaction(transaction: Transaction) async throws -> Transaction {
        while true {
            do {
                return try await performSync(transaction: transaction)
            } catch {
                print("Error in syncTransaction: \(error)")
                addLog(message: "syncTransaction, error \(error) for \(transaction.id), retrying...", level: 2)
                
                // Wait 2 seconds before retrying
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
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
        
        let importAsCleared = UserDefaults.standard.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = UserDefaults.standard.bool(forKey: "putTransStatusInNotes")
        let applyRules = UserDefaults.standard.bool(forKey: "apply_rules")
        let skipDuplicates = UserDefaults.standard.bool(forKey: "skip_duplicates")
        let checkForRecurring = UserDefaults.standard.bool(forKey: "check_for_recurring")
        let skipBalanceUpdate = UserDefaults.standard.bool(forKey: "skip_balance_update")
        
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
                            categoryId: nil,
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
                        addLog(message: "syncTransaction, synced to LM for \(transaction.id), status=\(importAsCleared ? "cleared" : "uncleared")", level: 2)
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
                categoryId: nil,
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
    
    func addLog(message: String, level: Int = 1) {
        let now = Date()
        var fullMessage = message
        
        if let lastTime = lastLogTime {
            let timeDiff = now.timeIntervalSince(lastTime)
            let hours = Int(timeDiff) / 3600
            let minutes = Int(timeDiff) / 60 % 60
            let seconds = Int(timeDiff) % 60
            fullMessage += String(format: " (%02d:%02d:%02d)", hours, minutes, seconds)
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
    
    func getLogs(limit: Int = 100) -> [Log] {
        let sortDescriptor = SortDescriptor<Log>(\.date, order: .reverse)
        var fetchDescriptor = FetchDescriptor<Log>(
            sortBy: [sortDescriptor]
        )
        fetchDescriptor.fetchLimit = limit
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch logs: \(error)")
            return []
        }
    }
    
    func clearLogs() {
        let fetchDescriptor = FetchDescriptor<Log>()
        do {
            let logs = try modelContext.fetch(fetchDescriptor)
            for log in logs {
                modelContext.delete(log)
            }
            try modelContext.save()
        } catch {
            print("Failed to clear logs: \(error)")
        }
    }
}
