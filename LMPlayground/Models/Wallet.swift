import Foundation
import SwiftData
import Combine
import os

@MainActor
class Wallet :ObservableObject {
    private let modelContext: ModelContext
    private var apiToken: String
    /// Built per use so every call follows the API version currently selected
    /// in Settings — Wallet instances outlive settings changes.
    private var API: any LunchMoneyService {
        LunchMoneyServiceFactory.make(apiToken: apiToken)
    }
    private var lastLogTime: Date?
    var logger: Logger!

    var isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    init(context: ModelContext, apiToken: String) {
        self.modelContext = context
        self.apiToken = apiToken
        logger = Logger(subsystem: "com.littlebluebug.AppleCardSync", category: "Wallet")
    }

    func updateAPIToken(_ token: String) {
        self.apiToken = token
    }
    
    func getAPIAccountName() async throws -> String{
        let userInfo = try await API.getUser()
        return userInfo.userName
    }
    
    func getAPIAccount() async throws -> User{
        let userInfo = try await API.getUser()
        return userInfo
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
    
    func syncAccountTypes(updates: [(id: String, accountType: String)]) {
        for update in updates {
            guard !update.accountType.isEmpty else { continue }
            let id = update.id
            let fetchDescriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
            if let localAccount = try? modelContext.fetch(fetchDescriptor).first,
               localAccount.accountType.isEmpty {
                localAccount.accountType = update.accountType
            }
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
    /*
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
    */
    
    /// What `replaceTransaction` did with the incoming transaction, so callers
    /// (e.g. bulk import) can report an accurate summary to the log.
    enum ReplaceOutcome {
        case insertedNew    // not in the local store before; stored with its incoming sync status
        case requeued       // existed with changed fields; re-queued as .pending
        case unchanged      // existed with identical fields; left alone
    }

    @discardableResult
    func replaceTransaction(newTrans: Transaction) -> ReplaceOutcome {
        // find a transaction in the local store
        let id = newTrans.id
        let fetchDescriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        //print("replaceTransaction with \(id)")
        var outcome: ReplaceOutcome = .unchanged
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            
            if let transaction = transactions.first {
                // Only treat string fields as changes if the incoming value is non-empty (or non-nil and non-empty for optionals)
                let payeeChanged = (!newTrans.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (newTrans.payee != transaction.payee)
                let amountChanged = newTrans.amount != transaction.amount
                let dateChanged = newTrans.date != transaction.date
                let notesChanged = (!newTrans.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (newTrans.notes != transaction.notes)
                let pendingChanged = newTrans.isPending != transaction.isPending
                let categoryIdChanged = (newTrans.category_id?.isEmpty == false) && (newTrans.category_id != transaction.category_id)
                let categoryNameChanged = (newTrans.category_name?.isEmpty == false) && (newTrans.category_name != transaction.category_name)
                let lmCategoryIdChanged = (newTrans.lm_category_id?.isEmpty == false) && (newTrans.lm_category_id != transaction.lm_category_id)

                if(
                    payeeChanged ||
                    amountChanged ||
                    dateChanged ||
                    notesChanged ||
                    pendingChanged ||
                    categoryIdChanged ||
                    categoryNameChanged ||
                    lmCategoryIdChanged
                ){
                    outcome = .requeued
                    /*
                    print(" -- \(transaction.lm_id) has changes in payee, amount or date")
                    print(" -- -- \(newTrans.payee) != \(transaction.payee) \(newTrans.payee != transaction.payee)")
                    print(" -- -- \(newTrans.amount) != \(transaction.amount) \(newTrans.amount != transaction.amount)")
                    print(" -- -- \(newTrans.date) != \(transaction.date) \(newTrans.date != transaction.date)")
                     */
                    //print(" -- -- \(newTrans.category_id ?? "n/a") != \(transaction.category_id ?? "n/a") \(newTrans.category_name ?? "n/a" != transaction.category_name ?? "n/a")")
                    if payeeChanged { transaction.payee = newTrans.payee }
                    if amountChanged { transaction.amount = newTrans.amount }
                    if dateChanged { transaction.date = newTrans.date }
                    if notesChanged { transaction.notes = newTrans.notes }
                    transaction.lm_id = newTrans.lm_id
                    transaction.lm_account = newTrans.lm_account
                    transaction.sync = .pending
                    if pendingChanged {
                        transaction.isPending = newTrans.isPending
                        transaction.refreshMetadataPendingFlag()
                    }
                    if categoryIdChanged { transaction.category_id = newTrans.category_id }
                    if categoryNameChanged { transaction.category_name = newTrans.category_name }
                    if lmCategoryIdChanged { transaction.lm_category_id = newTrans.lm_category_id }
                    if (newTrans.lm_category_name?.isEmpty == false) && (newTrans.lm_category_name != transaction.lm_category_name) {
                        transaction.lm_category_name = newTrans.lm_category_name
                    }
                }
                //else{
                    //print(" -- \(transaction.payee) \(transaction.amount) has no changes: \(transaction.id)")
                //}
            }else{
                //print("replaceTransaction insert new \(newTrans.payee)")
                modelContext.insert(newTrans)
                outcome = .insertedNew
            }
        } catch {
            print("error searching")
        }
        try? modelContext.save() // Save after making updates
        return outcome
           
    }
    
    func setSyncStatus(newTrans: Transaction, newStatus: Transaction.SyncStatus){
        newTrans.sync = newStatus
        try? modelContext.save() // Save after making updates
    }
    
    /*
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
    */
    
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
    
    /*
    func getTransactions() -> [Transaction] {
        let fetchDescriptor = FetchDescriptor<Transaction>()
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("Failed to fetch transactions: \(error)")
            return []
        }
    }
     */
    
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
    
    func createAsset(name: String, institutionName: String, note: String, accountType: String = "") async -> Int? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let today = dateFormatter.string(from: Date())

        let typeName: String
        let subTypeName: String
        switch accountType {
        case "Credit":
            typeName = "credit"
            subTypeName = "credit card"
        case "Savings":
            typeName = "cash"
            subTypeName = "savings"
        default: // Cash or unset
            typeName = "cash"
            subTypeName = "digital wallet"
        }

        let assetRequest = CreateAssetRequest(
            typeName: typeName,
            subTypeName: subTypeName,
            balance: 0.0,
            currency: "usd",
            name: name,
            institutionName: institutionName,
            createdAt: today,
            note: note
        )

        do {
            let assetResponse = try await API.createAsset(requestBody: assetRequest)
            return assetResponse.resolvedId
        } catch {
            print("Error creating asset: \(error)")
        }
        return nil
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
        logger.error("\(fullMessage)")
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
    
    // MARK: save categories to user defaults

    public func getTrnCategories() -> [TrnCategory] {
        do{
            let categories = try modelContext.fetch(FetchDescriptor<TrnCategory>())
            return categories
        }catch{
            print("failed to fetch categories")
        }
        return []
    }
    
    // retrieve stored TrnCategories from User defaults
    public func clearTrnCategories(){
        let fetchDescriptor = FetchDescriptor<TrnCategory>()
        do {
            let categories = try modelContext.fetch(fetchDescriptor)
            for category in categories {
                modelContext.delete(category)
            }
            try modelContext.save()
        } catch {
            print("Failed to clear logs: \(error)")
        }
    }
    
    
}
