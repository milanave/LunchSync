//
//  SyncBroker.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/3/25.
//
import Foundation
import SwiftData
import SwiftUI

class SyncBroker {
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

    public struct SyncMetadataProgress {
        public enum Step: String {
            case fetching = "Fetching wallet transactions"
            case capturing = "Capturing metadata"
            case pushing = "Pushing to Lunch Money"
            case done = "Complete"
        }
        public let step: Step
        public let current: Int
        public let total: Int
        public let detail: String?
        public let matched: Int
        public let pushed: Int
        public let failed: Int
    }

    public struct SyncMetadataResult {
        public let matched: Int
        public let pushed: Int
        public let failed: Int
    }
 
    //MARK: Logging functions
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
    
    // MARK: main import function
    public func fetchTransactions(prefix: String, showAlert: Bool = false, skipSync: Bool = false, progress: @escaping (String) -> Void, preFetchedWalletData: PreFetchedWalletData? = nil) async throws -> Int {
        
        logPrefix = prefix
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
        let putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")
        let autoImportTransactions = skipSync ? false : sharedDefaults.bool(forKey: "autoImportTransactions")
        
        let categorize_incoming = sharedDefaults.object(forKey: "categorize_incoming") == nil ? true : sharedDefaults.bool(forKey: "categorize_incoming")
        let alert_after_import = sharedDefaults.object(forKey: "alert_after_import") == nil ? true : sharedDefaults.bool(forKey: "alert_after_import")
        
        let remove_old_transactions = sharedDefaults.bool(forKey: "remove_old_transactions")
        let remove_old_days = sharedDefaults.integer(forKey: "remove_old_days")
        
        
        do {
            addLog(prefix: prefix, message: "Starting transaction fetch (importAsCleared: \(importAsCleared), transStatusInNotes: \(putTransStatusInNotes), autoSync: \(autoImportTransactions), categorize: \(categorize_incoming)", level: 1)
            
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
                        
            // get a list of accounts, then Apple Wallet transactions for those accounts
            let accounts = getSyncedAccounts()
            
            addLog(prefix: prefix, message: "got accounts: \(accounts.count) to sync", level: 2)
            
            
            
            var newTransactions: [Transaction] = []
            if let _ = preFetchedWalletData {
                addLog(prefix: prefix, message: "preFetchedWalletData provided, (transactions:  \(preFetchedWalletData!.transactions.count), accounts: \(preFetchedWalletData!.accounts.count))", level: 2)
                // The passed transactions won't have account/category set; handling to be added next
                newTransactions = self.prepPrefetchedTransactions(transactions: preFetchedWalletData!.transactions, accounts: accounts)
            } else {
                newTransactions = try await appleWallet.refreshWalletTransactionsForAccounts(accounts: accounts, logPrefix: prefix)
                addLog(prefix: prefix, message: "found \(newTransactions.count) transactions to sync", level: 2)
            }
            
            // always import Apple MCC codes/categories, so we'll have them if the user enabled this feature later
            let trnCategoryMap = try processMCCCategories(transactions: newTransactions, prefix: prefix)
            
            // Process MCCs and create category mappings
            if(categorize_incoming){
                print("categorize_incoming")
                
                addLog(prefix: prefix, message: "processing \(trnCategoryMap.count) MCC categories", level: 2)
                
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
            }else{
                print("Skipping MCC categories")
                newTransactions.forEach { transaction in
                    if transaction.lm_id.isEmpty || transaction.lm_id == "0" {
                        replaceTransaction(newTrans: transaction)
                    }
                }
            }
            

            let transactionsToSyncCount = getTransactionsWithStatus(.pending).count
            //addLog(prefix: prefix, message: "\(transactionsToSyncCount) transactions ready to sync", level: 2)
            
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
            
            var accountsToUpdate: [Account] = []
            if let _ = preFetchedWalletData {
                accountsToUpdate = preFetchedWalletData!.accounts
            }else{
                accountsToUpdate = try await appleWallet.getWalletAccounts()
            }
            try await syncAccountBalances(accounts: accountsToUpdate)
            for acct in accountsToUpdate {
                addLog(prefix: prefix, message: "sync account: \(acct.name) \(CurrencyFormatter.shared.format(acct.balance))", level: 2)
            }
            
            // get number of unmapped categories
            //addLog(prefix: prefix, message: "Updating badge counts", level: 2)
            let fetchDescriptor = FetchDescriptor<TrnCategory>(
                predicate: #Predicate<TrnCategory> { $0.lm_id == "" }
            )
            let uncategorizedCount = (try? modelContext.fetch(fetchDescriptor).count) ?? 0
            
            var body = ""
            
            if(categorize_incoming){
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

            }else{
                if(transactionsToSyncCount == 0 ){
                    // no alert needed
                }else if(transactionsToSyncCount > 0){
                    body = "\(transactionsToSyncCount) transaction\(transactionsToSyncCount == 1 ? "" : "s") synced"
                }
                // update the badge count
                addLog(prefix: prefix, message: "Updating badge count to \(finalPendingCount)", level: 2)
                updateBadgeCounts(count:finalPendingCount)
            }
            
                        
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
                await PushAPI.registerWalletCheck(deviceToken: storedDeviceToken, logPrefix: logPrefix)
                addLog( prefix: logPrefix, message: "registerWalletCheck complete", level: 2)
            }else{
                addLog( prefix: logPrefix, message: "registerWalletCheck failed, no deviceToken", level: 1)
            }
            
            addLog(prefix: prefix, message: "Sync complete with \(finalPendingCount) imported", level: 1)
            
            if(remove_old_transactions){
                let deletedTransactions = try await getTransactionsOlderThanDays(remove_old_days, andDelete: true)
                addLog(prefix: prefix, message: "Deleted \(deletedTransactions.count) transactions older than \(remove_old_days) days", level: 1)
            }
            
            return finalPendingCount
        } catch {
            addLog(prefix: prefix, message: "Sync failed with error: \(error.localizedDescription)", level: 1)
            if showAlert {
                await addNotification(time: 0.1, title: "Sync Error", subtitle: "", body: "fetchTransactionsAndSync:\(autoImportTransactions) failed with error: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    // go through the transactions and update the account and category
    func prepPrefetchedTransactions(transactions: [Transaction], accounts:[Account]) -> [Transaction] {
        var returnedTransactions: [Transaction] = []
        
        // Build a set of allowed account ID strings
        let accountIdSet = Set(accounts.map { $0.id })
        guard !accountIdSet.isEmpty else {
            print("No valid account UUIDs found")
            return []
        }
        
        let filteredTransactions = transactions.filter { accountIdSet.contains($0.accountID) }
        print("Filtered to \(filteredTransactions.count) transactions for \(accountIdSet.count) accounts")

        for transaction in filteredTransactions {
            let account = accounts.first(where: { $0.id == transaction.accountID })
            let accountName = account?.name ?? ""
            let syncBalanceOnly = account?.syncBalanceOnly ?? false
            
            let category_id = transaction.category_id
            let category_name = category_id.flatMap { appleWallet.getMCCDescription(for: $0) }
            
            print("prepPrefetchedTransactions: \(transaction.payee), \(transaction.amount), \(transaction.date) cat_id=\(category_id ?? "n/a"), cat_name=\(category_name ?? "n/a"), balance_only=\(syncBalanceOnly)")
            if( accountName != ""){
                transaction.account = accountName
                transaction.category_id = category_id
                transaction.category_name = category_name
                transaction.sync = syncBalanceOnly ? .skipped : .pending

                // Patch the metadata captured by getRecentTransactions with the
                // account/institution/MCC-description info we now have.
                if let existing = WalletMetadata.from(jsonString: transaction.walletMetadataJSON) {
                    transaction.walletMetadataJSON = existing.enriched(
                        accountDisplayName: account?.name,
                        institutionName: account?.institution_name,
                        merchantCategoryDescription: category_name
                    ).toJSONString()
                }

                returnedTransactions.append(transaction)
            }else{
                print("prepPrefetchedTransactions account name is empty, skipping")
            }
        }
        print("returning \(returnedTransactions.count) transactions")
        return returnedTransactions
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
        print("updateBadgeCounts: \(count)")        
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
                print("replaceTransaction matched \(transaction.lm_id)")
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
                    var changes: [String] = []
                    
                    if payeeChanged { changes.append("payee: \(transaction.payee) -> \(newTrans.payee)") }
                    if amountChanged { changes.append("amount: \(CurrencyFormatter.shared.format(transaction.amount)) -> \(CurrencyFormatter.shared.format(newTrans.amount))") }
                    let noteDate = dateFormatter.string(from: newTrans.date)
                    let oldNoteDate = dateFormatter.string(from: transaction.date)
                    if dateChanged { changes.append("date: \(oldNoteDate) -> \(noteDate)") }
                    if notesChanged { changes.append("notes: \(transaction.notes) -> \(newTrans.notes)") }
                    if pendingChanged { changes.append("pending: \(transaction.isPending) -> \(newTrans.isPending)") }
                    if categoryNameChanged { changes.append("category: \(transaction.category_name ?? "nil") -> \(newTrans.category_name ?? "nil")") }
                    
                    let changeSummary = changes.joined(separator: ", ")
                    if !changeSummary.isEmpty {
                        transaction.addHistory(note: changeSummary, source: logPrefix)
                    }
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
                    if pendingChanged { transaction.isPending = newTrans.isPending }
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

                // Backfill / refresh wallet metadata regardless of whether
                // user-visible fields changed. Doesn't flip sync to .pending —
                // we don't want to re-send to LM just because Apple cleaned up
                // a merchant name. The freshly-encoded JSON simply replaces
                // whatever (if anything) was previously stored.
                if let incoming = newTrans.walletMetadataJSON, !incoming.isEmpty {
                    let existing = transaction.walletMetadataJSON ?? ""
                    if existing != incoming {
                        transaction.walletMetadataJSON = incoming
                        if existing.isEmpty {
                            transaction.addHistory(note: "Captured wallet metadata", source: logPrefix)
                        }
                    }
                }
            }else{
                print("replaceTransaction insert new \(newTrans.payee)")
                //newTrans.addHistory(note: "Created")
                modelContext.insert(newTrans)
            }
        } catch {
            print("error searching")
        }
        try? modelContext.save() // Save after making updates
           
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

        guard !pendingTransactions.isEmpty else { return }

        let runStart = Date()
        let requestsBefore = API.requestCount
        let settings = SyncSettings()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let syncedAccounts = getSyncedAccounts()
        for transaction in pendingTransactions {
            let matchingAccount = syncedAccounts.first(where: { $0.id == transaction.accountID })
            transaction.lm_account = matchingAccount?.lm_id ?? "0"
        }

        // The LM API allows 100 requests/minute per IP, so fetch the LM side once
        // for the whole run instead of a ±30-day GET per transaction: one window
        // covering every pending date (with the same ±30-day margin the old
        // per-transaction lookup used), paginated so the duplicate check can't
        // silently truncate at the API's page size.
        let calendar = Calendar.current
        let dates = pendingTransactions.map(\.date)
        let earliest = dates.min() ?? Date()
        let latest = dates.max() ?? Date()
        let startDate = dateFormatter.string(from: calendar.date(byAdding: .day, value: -30, to: earliest) ?? earliest)
        let endDate = dateFormatter.string(from: calendar.date(byAdding: .day, value: 30, to: latest) ?? latest)
        addLog(message: "pending dates span \(dateFormatter.string(from: earliest)) → \(dateFormatter.string(from: latest)); fetching LM window \(startDate) → \(endDate) (±30 days)", level: 2)

        progressCallback(SafeSyncProgress(
            current: 0,
            total: total,
            status: "Checking Lunch Money for existing transactions..."
        ))

        let fetchStart = Date()
        var fetchPages = 0
        let existingTransactions = try await withRateLimitRetry(label: "existing-transactions fetch", status: { message in
            progressCallback(SafeSyncProgress(current: 0, total: total, status: message))
        }) {
            try await API.getAllTransactions(startDate: startDate, endDate: endDate) { page, pageCount, runningTotal in
                fetchPages = page
                self.addLog(message: "LM fetch page \(page): \(pageCount) transactions (total \(runningTotal))", level: 2)
            }
        }
        addLog(message: "found \(existingTransactions.count) existing LM transactions between \(startDate) and \(endDate) (\(fetchPages) page\(fetchPages == 1 ? "" : "s"), \(Self.elapsed(since: fetchStart)))", level: 2)

        // First match wins, mirroring the old linear scan of the fetched window.
        var existingByExternalId: [String: LMTransaction] = [:]
        for trn in existingTransactions {
            if let externalId = trn.externalId, existingByExternalId[externalId] == nil {
                existingByExternalId[externalId] = trn
            }
        }

        var toCreate: [Transaction] = []
        var toUpdate: [(local: Transaction, remote: LMTransaction)] = []
        for transaction in pendingTransactions {
            if let remote = existingByExternalId[transaction.id] {
                toUpdate.append((transaction, remote))
            } else {
                toCreate.append(transaction)
            }
        }
        addLog(message: "syncing \(toCreate.count) new and \(toUpdate.count) changed transactions", level: 2)

        var needIdResolution: [Transaction] = []
        var finished = false
        defer {
            // One level-1 line per run so exported logs show what happened, even
            // for runs that abort partway (e.g. persistent rate limiting).
            let created = toCreate.filter { $0.sync == .complete }.count
            let updated = toUpdate.filter { $0.local.sync == .complete }.count
            let failed = pendingTransactions.filter { $0.sync == .never }.count
            let requests = API.requestCount - requestsBefore
            addLog(message: "sync run \(finished ? "complete" : "aborted"): \(created) created, \(updated) updated, \(failed) failed, \(needIdResolution.count) needed id resolution, \(requests) API requests, \(Self.elapsed(since: runStart))", level: 1)
        }

        // New transactions go up in batches (the API accepts up to 500 per call)
        // rather than one POST each. LM dedupes on external_id server-side, so
        // re-running after an interrupted sync can't create duplicates.
        let batchCount = (toCreate.count + Self.createBatchSize - 1) / Self.createBatchSize
        if !toCreate.isEmpty {
            addLog(message: "inserting \(toCreate.count) transactions in \(batchCount) batch\(batchCount == 1 ? "" : "es") of up to \(Self.createBatchSize), status=\(settings.importAsCleared ? "cleared" : "uncleared")", level: 2)
        }
        var chunkIndex = 0
        var chunkStart = 0
        while chunkStart < toCreate.count {
            let chunk = Array(toCreate[chunkStart..<min(chunkStart + Self.createBatchSize, toCreate.count)])
            chunkStart += chunk.count
            chunkIndex += 1
            let batchLabel = "batch \(chunkIndex)/\(batchCount)"

            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Syncing \(current + 1)-\(current + chunk.count) of \(total)"
            ))

            let chunkDates = chunk.map(\.date)
            if let firstDate = chunkDates.min(), let lastDate = chunkDates.max() {
                addLog(message: "\(batchLabel): sending \(chunk.count) transactions (\(dateFormatter.string(from: firstDate)) → \(dateFormatter.string(from: lastDate)))", level: 2)
            }

            let batchStart = Date()
            let requests = chunk.map { buildCreateRequest(for: $0, settings: settings, dateFormatter: dateFormatter) }
            do {
                let response = try await withRateLimitRetry(label: batchLabel, status: { message in
                    progressCallback(SafeSyncProgress(current: current, total: total, status: message))
                }) {
                    try await API.createTransactions(
                        transactions: requests,
                        applyRules: settings.applyRules,
                        skipDuplicates: settings.skipDuplicates,
                        checkForRecurring: settings.checkForRecurring,
                        skipBalanceUpdate: settings.skipBalanceUpdate
                    )
                }

                let ids = response.transactionIds ?? []
                if ids.count == chunk.count {
                    for (transaction, id) in zip(chunk, ids) {
                        transaction.lm_id = String(id)
                        transaction.sync = .complete
                        transaction.addHistory(note: "Synced to LM", source: logPrefix)
                    }
                } else {
                    // LM skipped some rows (external_id dedupe), so the returned
                    // ids can't be matched back positionally. Mark the chunk
                    // synced and fill in the LM ids with one follow-up fetch below.
                    addLog(message: "\(batchLabel): LM returned \(ids.count) ids for \(chunk.count) transactions, will resolve ids after sync", level: 2)
                    for transaction in chunk {
                        transaction.sync = .complete
                        transaction.addHistory(note: "Synced to LM", source: logPrefix)
                        needIdResolution.append(transaction)
                    }
                }
                addLog(message: "\(batchLabel): inserted \(chunk.count) transactions in \(Self.elapsed(since: batchStart))", level: 2)
            } catch let error as RateLimitedError {
                // Still rate limited after waiting out Retry-After several times:
                // give up on this run. Everything unsent stays .pending and is
                // picked up by the next sync.
                throw error
            } catch {
                // The whole chunk was rejected (e.g. one row failed validation).
                // Fall back to one-at-a-time for this chunk so a single bad
                // transaction can't take down the other 499.
                addLog(message: "\(batchLabel): batch insert failed after \(Self.elapsed(since: batchStart)) (\(error.localizedDescription)), retrying chunk individually", level: 2)
                needIdResolution += try await createIndividually(chunk, label: batchLabel, settings: settings, dateFormatter: dateFormatter) { message in
                    progressCallback(SafeSyncProgress(current: current, total: total, status: message))
                }
            }

            current += chunk.count
            try? modelContext.save()
            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Completed \(current) of \(total)"
            ))
        }

        // Batch inserts that hit the external_id dedupe don't tell us which LM id
        // belongs to which transaction; one re-fetch of the window resolves them.
        if !needIdResolution.isEmpty {
            addLog(message: "resolving LM ids for \(needIdResolution.count) transactions", level: 2)
            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Resolving Lunch Money ids..."
            ))
            do {
                let refreshed = try await withRateLimitRetry(label: "id resolution", status: { message in
                    progressCallback(SafeSyncProgress(current: current, total: total, status: message))
                }) {
                    try await API.getAllTransactions(startDate: startDate, endDate: endDate)
                }
                var refreshedByExternalId: [String: LMTransaction] = [:]
                for trn in refreshed {
                    if let externalId = trn.externalId, refreshedByExternalId[externalId] == nil {
                        refreshedByExternalId[externalId] = trn
                    }
                }
                var unresolved = 0
                for transaction in needIdResolution {
                    if let remote = refreshedByExternalId[transaction.id] {
                        transaction.lm_id = String(remote.id)
                    } else {
                        unresolved += 1
                    }
                }
                addLog(message: "resolved \(needIdResolution.count - unresolved) of \(needIdResolution.count) missing LM ids", level: 2)
                if unresolved > 0 {
                    addLog(message: "\(unresolved) synced transactions have no LM id yet; they will pick one up the next time they change", level: 2)
                }
                try? modelContext.save()
            } catch {
                // Non-fatal: the transactions are in LM, we just don't know their
                // ids yet. An update pass on a later sync fills them in.
                addLog(message: "could not resolve LM ids after batch insert: \(error.localizedDescription)", level: 2)
            }
        }

        // Changed transactions that already exist in LM: v1 has no batch update,
        // so these stay one PUT each, paced by the 429 handling above.
        if !toUpdate.isEmpty {
            addLog(message: "pushing \(toUpdate.count) individual updates (LM has no batch update endpoint)", level: 2)
        }
        for (transaction, remote) in toUpdate {
            current += 1

            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Syncing \(current) of \(total) for \(transaction.payee)"
            ))

            let updateRequest = buildUpdateRequest(for: transaction, settings: settings, dateFormatter: dateFormatter)

            // retry the sync a few times, then mark the transaction failed and
            // move on so one bad transaction can't stall the rest of the batch
            let maxSyncAttempts = 3
            var attempts = 0
            while true {
                do {
                    let result = try await withRateLimitRetry(label: "update \(current) of \(total)", status: { message in
                        progressCallback(SafeSyncProgress(current: current, total: total, status: message))
                    }) {
                        try await API.updateTransaction(id: remote.id, request: updateRequest)
                    }

                    if let errors = result.errors {
                        addLog(message: "syncTransaction, Failed to send transaction to LM for \(transaction.id), \(errors.joined(separator: ", "))", level: 2)
                        // don't stop it from being re-synced this time
                    } else {
                        transaction.lm_id = String(remote.id)
                        if let assetId = remote.assetId {
                            transaction.lm_account = String(assetId)
                        } else {
                            transaction.lm_account = ""
                        }
                        transaction.sync = .complete
                        transaction.addHistory(note: "Synced to LM (updated)", source: logPrefix)
                        addLog(message: "synced \(transaction.payee), \(CurrencyFormatter.shared.format(transaction.amount))", level: 2)
                    }
                    break
                } catch let error as RateLimitedError {
                    throw error
                } catch {
                    attempts += 1
                    print("Error in syncTransaction: \(error) with \(current) of \(total), retry \(attempts)")

                    guard attempts < maxSyncAttempts else {
                        addLog(message: "syncTransaction, error \(error) for \(transaction.id), giving up after \(maxSyncAttempts) attempts", level: 2)
                        transaction.sync = .never
                        transaction.addHistory(note: "Sync failed after \(maxSyncAttempts) attempts: \(error)", source: logPrefix)

                        progressCallback(SafeSyncProgress(
                            current: current,
                            total: total,
                            status: "Failed \(current) of \(total) after \(maxSyncAttempts) attempts, skipping"
                        ))
                        break
                    }

                    addLog(message: "syncTransaction, error \(error) for \(transaction.id), retrying...", level: 2)

                    progressCallback(SafeSyncProgress(
                        current: current,
                        total: total,
                        status: "Error with \(current) of \(total), retry \(attempts)"
                    ))

                    // Wait 2 seconds before retrying
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            try? modelContext.save()
            progressCallback(SafeSyncProgress(
                current: current,
                total: total,
                status: "Completed \(current) of \(total)"
            ))
        }

        try modelContext.save()
        finished = true
    }

    /// Documented LM maximum number of transactions per insert request.
    private static let createBatchSize = 500

    private static func elapsed(since start: Date) -> String {
        String(format: "%.1fs", Date().timeIntervalSince(start))
    }

    /// Import settings snapshot, read once per sync run.
    private struct SyncSettings {
        let importAsCleared: Bool
        let putTransStatusInNotes: Bool
        let applyRules: Bool
        let skipDuplicates: Bool
        let checkForRecurring: Bool
        let skipBalanceUpdate: Bool
        let sendFinanceKitMetadata: Bool

        init() {
            let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
            importAsCleared = sharedDefaults.bool(forKey: "importTransactionsCleared")
            putTransStatusInNotes = sharedDefaults.bool(forKey: "putTransStatusInNotes")
            applyRules = sharedDefaults.bool(forKey: "apply_rules")
            skipDuplicates = sharedDefaults.bool(forKey: "skip_duplicates")
            checkForRecurring = sharedDefaults.bool(forKey: "check_for_recurring")
            skipBalanceUpdate = sharedDefaults.bool(forKey: "skip_balance_update")
            // Default to true when the key has never been written.
            sendFinanceKitMetadata = sharedDefaults.object(forKey: "send_finance_kit_metadata") == nil
                ? true
                : sharedDefaults.bool(forKey: "send_finance_kit_metadata")
        }
    }

    /// Runs `operation`, waiting out LM rate limits (HTTP 429) using the
    /// server-provided Retry-After before trying again. Rate-limit waits are
    /// deliberately separate from the error retries in the sync loops: a 429
    /// never marks a transaction as failed.
    private func withRateLimitRetry<T>(
        label: String,
        status: (String) -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        let maxWaits = 5
        var waits = 0
        while true {
            do {
                return try await operation()
            } catch let error as RateLimitedError {
                waits += 1
                guard waits <= maxWaits else { throw error }
                let seconds = Int(error.retryAfter.rounded(.up))
                addLog(message: "rate limited by LM API during \(label), waiting \(seconds)s before retrying (\(waits)/\(maxWaits))", level: 2)
                status("Rate limited by Lunch Money, waiting \(seconds)s...")
                try await Task.sleep(nanoseconds: UInt64(error.retryAfter * 1_000_000_000))
            }
        }
    }

    private func walletMetadata(for transaction: Transaction, settings: SyncSettings) -> WalletMetadata? {
        settings.sendFinanceKitMetadata ? WalletMetadata.from(jsonString: transaction.walletMetadataJSON) : nil
    }

    private func buildCreateRequest(for transaction: Transaction, settings: SyncSettings, dateFormatter: DateFormatter) -> CreateTransactionRequest {
        CreateTransactionRequest(
            date: dateFormatter.string(from: transaction.date),
            payee: transaction.payee,
            amount: String(format: "%.2f", transaction.amount),
            currency: "usd",
            categoryId: transaction.lmCategoryIdForAPI,
            assetId: Int(transaction.lm_account),
            notes: settings.putTransStatusInNotes ? (transaction.notes.isEmpty ? nil : transaction.notes) : nil,
            status: settings.importAsCleared ? "cleared" : "uncleared",
            externalId: transaction.id,
            isPending: false, //transaction.isPending
            customMetadata: walletMetadata(for: transaction, settings: settings)
        )
    }

    private func buildUpdateRequest(for transaction: Transaction, settings: SyncSettings, dateFormatter: DateFormatter) -> UpdateTransactionRequest {
        UpdateTransactionRequest(
            transaction: UpdateTransactionRequest.TransactionUpdate(
                date: dateFormatter.string(from: transaction.date),
                payee: transaction.payee,
                amount: String(format: "%.2f", transaction.amount),
                currency: "usd",
                categoryId: transaction.lmCategoryIdForAPI,
                assetId: Int(transaction.lm_account),
                notes: settings.putTransStatusInNotes ? (transaction.notes.isEmpty ? nil : transaction.notes) : nil,
                status: nil, //importAsCleared ? "cleared" : "uncleared", no need to call this for updates
                externalId: transaction.id,
                isPending: false, //transaction.isPending can't set to true b/c LM doesn't let you edit
                customMetadata: walletMetadata(for: transaction, settings: settings)
            )
        )
    }

    /// Fallback when a batch insert is rejected: create the chunk's transactions
    /// one at a time so only the genuinely bad rows get marked as failed.
    /// Returns any transactions LM deduped by external_id (created earlier but
    /// unknown to us) whose LM ids still need to be resolved.
    private func createIndividually(
        _ transactions: [Transaction],
        label: String,
        settings: SyncSettings,
        dateFormatter: DateFormatter,
        status: (String) -> Void
    ) async throws -> [Transaction] {
        var needIdResolution: [Transaction] = []
        var createdCount = 0
        var failedCount = 0
        let maxSyncAttempts = 3

        for (index, transaction) in transactions.enumerated() {
            let request = buildCreateRequest(for: transaction, settings: settings, dateFormatter: dateFormatter)
            var attempts = 0
            while true {
                do {
                    let response = try await withRateLimitRetry(label: "\(label) individual \(index + 1)/\(transactions.count)", status: status) {
                        try await API.createTransactions(
                            transactions: [request],
                            applyRules: settings.applyRules,
                            skipDuplicates: settings.skipDuplicates,
                            checkForRecurring: settings.checkForRecurring,
                            skipBalanceUpdate: settings.skipBalanceUpdate
                        )
                    }
                    if let ids = response.transactionIds, !ids.isEmpty {
                        transaction.lm_id = String(ids[0])
                        transaction.sync = .complete
                        transaction.addHistory(note: "Synced to LM", source: logPrefix)
                        createdCount += 1
                    } else {
                        // No id and no error: LM deduped it against an existing
                        // transaction with the same external_id.
                        transaction.sync = .complete
                        transaction.addHistory(note: "Synced to LM", source: logPrefix)
                        needIdResolution.append(transaction)
                    }
                    break
                } catch let error as RateLimitedError {
                    throw error
                } catch {
                    attempts += 1
                    guard attempts < maxSyncAttempts else {
                        addLog(message: "syncTransaction, error \(error) for \(transaction.id), giving up after \(maxSyncAttempts) attempts", level: 2)
                        transaction.sync = .never
                        transaction.addHistory(note: "Sync failed after \(maxSyncAttempts) attempts: \(error)", source: logPrefix)
                        failedCount += 1
                        break
                    }
                    addLog(message: "syncTransaction, error \(error) for \(transaction.id), retrying...", level: 2)
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        try? modelContext.save()
        addLog(message: "\(label) individual fallback: \(createdCount) created, \(needIdResolution.count) deduped, \(failedCount) failed", level: 2)
        return needIdResolution
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

    // MARK: - Sync Metadata (backfill custom_metadata for already-synced transactions)

    /// Backfill `walletMetadataJSON` on existing local transactions by re-fetching
    /// from FinanceKit, then push the freshly-captured metadata up to Lunch Money
    /// for any of those transactions that are already linked (`lm_id` set).
    ///
    /// `transactions` is the user-selected subset (typically a month range).
    /// `account` provides the FinanceKit account ID to query.
    ///
    /// Pinned to `@MainActor` because the body mutates SwiftData `@Model` objects
    /// and calls `modelContext.save()` after each `await`. Without this, the
    /// continuation can resume off-main, SwiftData's ModelContext detaches from
    /// the main queue, and we crash with a malloc double-free. The `await` points
    /// (FinanceKit query, API.updateTransaction) still suspend cleanly so the UI
    /// stays responsive between requests.
    @MainActor
    public func syncMetadata(
        transactions: [Transaction],
        account: Account,
        progress: @escaping (SyncMetadataProgress) -> Void
    ) async throws -> SyncMetadataResult {
        let total = transactions.count

        // Step 1: pull FinanceKit metadata for this account, bounded by the
        // date span of the user's selection. Bounding the FinanceKit query
        // by date is the safe predicate path; an unbounded fetch (or one
        // using a dynamic `contains` predicate) hangs/crashes on large
        // wallets — see the comment in `refreshWalletTransactionsForAccounts`.
        progress(SyncMetadataProgress(
            step: .fetching, current: 0, total: total,
            detail: "Querying Apple Wallet…",
            matched: 0, pushed: 0, failed: 0
        ))

        let dates = transactions.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else {
            // Empty selection — nothing to do.
            progress(SyncMetadataProgress(
                step: .done, current: 0, total: 0,
                detail: nil, matched: 0, pushed: 0, failed: 0
            ))
            return SyncMetadataResult(matched: 0, pushed: 0, failed: 0)
        }
        let cal = Calendar.current
        let startDate = cal.date(byAdding: .day, value: -1, to: earliest) ?? earliest
        let endDate = max(cal.date(byAdding: .day, value: 1, to: latest) ?? latest, Date())

        let lookups = try await appleWallet.fetchWalletMetadata(
            account: account,
            startDate: startDate,
            endDate: endDate,
            logPrefix: logPrefix
        )

        // Index by FinanceKit id (which equals our local Transaction.id since
        // we capture it at fetch time as `txn.id.uuidString`).
        var byId: [String: String] = [:]
        for entry in lookups {
            if let json = entry.metadataJSON, !json.isEmpty {
                byId[entry.financeKitId] = json
            }
        }
        addLog(message: "syncMetadata fetched \(lookups.count) wallet txns in range, \(byId.count) carry metadata", level: 2)

        // Step 2: capture metadata onto matching local transactions.
        var matched: [Transaction] = []
        for (i, local) in transactions.enumerated() {
            progress(SyncMetadataProgress(
                step: .capturing, current: i, total: total,
                detail: local.payee,
                matched: matched.count, pushed: 0, failed: 0
            ))

            guard let incoming = byId[local.id] else { continue }
            if local.walletMetadataJSON != incoming {
                let wasEmpty = (local.walletMetadataJSON ?? "").isEmpty
                local.walletMetadataJSON = incoming
                local.addHistory(
                    note: wasEmpty ? "Captured wallet metadata (Sync Metadata)" : "Refreshed wallet metadata (Sync Metadata)",
                    source: logPrefix
                )
            }
            matched.append(local)
        }
        try? modelContext.save()

        // Final tick of Step 2 so the UI can show full-bar before moving on.
        progress(SyncMetadataProgress(
            step: .capturing, current: total, total: total,
            detail: nil,
            matched: matched.count, pushed: 0, failed: 0
        ))

        // Step 3: push to Lunch Money for everything already linked.
        let toPush = matched.filter { !$0.lm_id.isEmpty && Int($0.lm_id) != nil }
        var pushed = 0
        var failed = 0

        progress(SyncMetadataProgress(
            step: .pushing, current: 0, total: toPush.count,
            detail: nil,
            matched: matched.count, pushed: pushed, failed: failed
        ))

        for (i, txn) in toPush.enumerated() {
            progress(SyncMetadataProgress(
                step: .pushing, current: i, total: toPush.count,
                detail: txn.payee,
                matched: matched.count, pushed: pushed, failed: failed
            ))

            guard let lmId = Int(txn.lm_id),
                  let metadata = WalletMetadata.from(jsonString: txn.walletMetadataJSON) else {
                failed += 1
                continue
            }

            let request = UpdateTransactionRequest(transaction: .init(
                date: nil, payee: nil, amount: nil, currency: nil,
                categoryId: nil, assetId: nil, notes: nil, status: nil,
                externalId: nil, isPending: nil,
                customMetadata: metadata
            ))

            do {
                _ = try await API.updateTransaction(id: lmId, request: request)
                pushed += 1
                txn.addHistory(note: "Pushed metadata to Lunch Money", source: logPrefix)
            } catch {
                failed += 1
                txn.addHistory(note: "Failed to push metadata: \(error.localizedDescription)", source: logPrefix)
                addLog(message: "syncMetadata push failed for \(txn.id): \(error.localizedDescription)", level: 1)
            }
        }
        try? modelContext.save()

        progress(SyncMetadataProgress(
            step: .done, current: toPush.count, total: toPush.count,
            detail: nil,
            matched: matched.count, pushed: pushed, failed: failed
        ))

        return SyncMetadataResult(matched: matched.count, pushed: pushed, failed: failed)
    }

    //MARK: utility functions
    public func countTransactionsOlderThanDays(_ days: Int) async throws -> Int {
        let transactions = try await getTransactionsOlderThanDays(days)
        return transactions.count
    }
    public func countAllTransactions() async throws -> Int {
        let fetchDescriptor = FetchDescriptor<Transaction>()
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            return transactions.count
        } catch {
            addLog(prefix: logPrefix, message: "Failed to fetch all transactions count: \(error.localizedDescription)", level: 1)
            throw error
        }
    }

    public func getTransactionsOlderThanDays(_ days: Int, andDelete: Bool = false) async throws -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: now) else {
            return []
        }
        
        let fetchDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date < cutoffDate
            }
        )
        
        do {
            let transactions = try modelContext.fetch(fetchDescriptor)
            if andDelete {
                transactions.forEach { modelContext.delete($0) }
                try modelContext.save()
            }
            return transactions
        } catch {
            addLog(prefix: logPrefix, message: "Failed to fetch transactions older than \(days) days: \(error.localizedDescription)", level: 1)
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
    
    //MARK: notifications
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
}
