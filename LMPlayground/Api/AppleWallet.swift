import Foundation
import FinanceKit
import FinanceKitUI

struct MCCCode: Codable {
    let id: Int
    let mcc: String
    let description: String
}

struct PreFetchedWalletData {
    let transactions: [Transaction]
    let accounts: [Account]
}

class AppleWallet{
 
    var authStatus: AuthorizationStatus = .notDetermined
    private var mccCodes: [MCCCode] = []
    var isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
        }()
    
    // Check if we're running in a background extension
    var isBackgroundExtension: Bool = {
        let isExtension = Bundle.main.bundleIdentifier?.contains("BackgroundHandler") == true
        //print("AppleWallet: isBackgroundExtension = \(isExtension), bundleIdentifier = \(Bundle.main.bundleIdentifier ?? "nil")")
        return isExtension
    }()
    
    // MARK: - MCC Code Loading and Lookup
    
    private func loadMCCCodes() {
        guard mccCodes.isEmpty else { return } // Only load once
        
        guard let url = Bundle.main.url(forResource: "MCC_Codes", withExtension: "json") else {
            print("Could not find MCC_Codes.json file")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            mccCodes = try JSONDecoder().decode([MCCCode].self, from: data)
            print("Loaded \(mccCodes.count) MCC codes")
        } catch {
            print("Error loading MCC codes: \(error)")
        }
    }
    
    public func getMCCDescription(for mccCode: String) -> String? {
        loadMCCCodes() // Ensure codes are loaded
        return mccCodes.first { $0.mcc == mccCode }?.description
    }
    
    func getSimulatedAccounts() -> [Account] {
        return [
                Account(
                    id: "111111111",
                    name: "Apple Card",
                    balance: 1000.00,
                    lm_id: "",
                    lm_name: "",
                    available: 10000.00,
                    currency: "USD",
                    institution_name: "Bank of America",
                    institution_id: "BOFA1234",
                    lastUpdated: Date(),
                    sync: false
                ),
                Account(
                    id: "222222222",
                    name: "Visa Card",
                    balance: 2000.00,
                    lm_id: "",
                    lm_name: "",
                    available: 120000.00,
                    currency: "USD",
                    institution_name: "Chase Bank",
                    institution_id: "CHS1234",
                    lastUpdated: Date(),
                    sync: false
                ),
                Account(
                    id: "333333333",
                    name: "Apple Cash",
                    balance: 3000.00,
                    lm_id: "",
                    lm_name: "",
                    available: 130000.00,
                    currency: "USD",
                    institution_name: "Apple Cash",
                    institution_id: "ACSH1234",
                    lastUpdated: Date(),
                    sync: false
                )
            ]
            
        /*return [
            Account(id: "123456789", name: "Apple Card", balance: 1000, lm_id: ""),
            //Account(id: "5678", name: "Savings Account", balance: 2000, lm_id: ""),
            //Account(id: "9101", name: "Credit Account", balance: 3000, lm_id: "")
        ]*/
    }
    
    func getWalletAccounts() async throws -> [Account] {
        print("getWalletAccounts starting")
        var accounts: [Account] = []
        let walletAccounts: [FinanceKit.Account] = try await fetchAccounts()
        for acct in walletAccounts {
            print("getWalletAccounts \(acct.displayName) \(acct.id)")
            
            do {
                let balance = try await fetchBalances(accountId: UUID(uuidString: acct.id.uuidString)!)
                //var balanceAmount = (balance.available?.amount.amount as NSDecimalNumber?)?.doubleValue ?? 0.0
                var balanceAmount : Decimal = 0
                var accountBalanceDate : Date?

                switch balance.currentBalance {
                case .availableAndBooked(let available, let booked):
                    balanceAmount = (available.creditDebitIndicator == FinanceKit.CreditDebitIndicator.credit) ?
                        booked.amount.amount : available.amount.amount
                    accountBalanceDate = available.asOfDate
                case .available(let available):
                    balanceAmount = available.amount.amount
                    accountBalanceDate = available.asOfDate
                case .booked(let booked):
                    balanceAmount = booked.amount.amount
                    accountBalanceDate = booked.asOfDate
                @unknown default:
                    print("got some weird balance type")
                }

                print("getWalletAccounts: \(acct.displayName) \(acct.id) \(balanceAmount)")
                let newAccount = Account(
                    id: acct.id.uuidString,
                    name: acct.displayName,
                    balance: (balanceAmount as NSDecimalNumber?)?.doubleValue ?? 0.0,
                    lm_id: "",
                    lm_name: "",
                    available: 0.0,
                    currency: "USD",
                    institution_name: acct.institutionName,
                    institution_id: acct.id.uuidString,
                    lastUpdated: accountBalanceDate ?? Date(),
                    sync: false
                )
                accounts.append(newAccount)
            } catch {
                print("Authorization request error: \(error.localizedDescription)")
            }
        }
        print("getWalletAccounts returning \(accounts.count) accounts")
        return accounts
    }
    
    func getTransactions(accountIds: Set<String>) -> [Transaction]{
        return [
            Transaction( id: "1", account: "Checking", payee: "Grocery Store", amount: 50.00, date: Date(), lm_id: "", lm_account: "", sync: .pending),
            Transaction( id: "2", account: "Savings", payee: "Online Shop", amount: 150.75, date: Date(), lm_id: "", lm_account: "", sync: .pending),
            Transaction( id: "3", account: "Credit Card", payee: "Cafe", amount: 20.00, date: Date(), lm_id: "", lm_account: "", sync: .pending)
        ]
    }
    
    func getRandomTransaction() -> Transaction {
        // Account options with corresponding IDs
        let accountOptions = [
            ("Checking", "1234"),
            ("Savings", "5678"),
            ("Credit Card", "9101")
        ]
        
        // Random account selection
        let randomAccountTuple = accountOptions.randomElement()!
        
        // Payee options
        let payeeOptions = ["Groceries", "Movie tickets", "Coffee", "Gas"]
        
        // Generate random components
        let randomId = String(format: "%04d", Int.random(in: 1...9999))
        let amount = (Double.random(in: 10...500) * 100).rounded() / 100  // Rounds to 2 decimal places
        
        // Random date in past 3 days
        //let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let randomTimeInterval = TimeInterval.random(in: 0...259200) // 3 days in seconds
        let randomDate = Date(timeInterval: -randomTimeInterval, since: Date())
        
        return Transaction(
            id: randomId,
            account: randomAccountTuple.0,
            payee: payeeOptions.randomElement()!,
            amount: amount,
            date: randomDate,
            lm_id: "",
            lm_account: "",
            notes: "",
            category: "",
            type: "",
            accountID: randomAccountTuple.1,
            status: "",
            sync: .pending
        )
    }
    
    private func dataAvailable() -> Bool{
        var dataAvail: Bool = false
        dataAvail = FinanceStore.isDataAvailable(.financialData)
        print("FinanceKit data available check: \(dataAvail), isBackgroundExtension: \(isBackgroundExtension)")
        return dataAvail
    }
    
    func requestAuth() async -> AuthorizationStatus {
        if isSimulator {
            return .authorized
        }
        
        do {
            // Check if data is available first
            if !dataAvailable() {
                print("FinanceKit data not available")
                return .denied
            }
            
            let status = try await FinanceStore.shared.requestAuthorization()
            print("FinanceKit authorization status: \(status)")
            return status
        } catch {
            print("FinanceKit authorization request error: \(error.localizedDescription)")
            return .denied
        }
    }
    
    func fetchAccounts() async throws -> [FinanceKit.Account] {
        let store = FinanceStore.shared
        let sortDescriptor = SortDescriptor(\FinanceKit.Account.displayName)
        //let predicate = #Predicate<FinanceKit.Account>{account in
        //    account.institutionName == "Apple" //.contains("Apple")
        //}
        let query = AccountQuery(sortDescriptors: [sortDescriptor], predicate: nil)
        let accounts : [FinanceKit.Account] = try await store.accounts(query: query)
        return accounts;
        /*
        for account in accounts {
            //print("Acc: \(account.displayName), \(String(describing: account.openingDate))")
            print(account)
            await fetchBalances(account:account)
        }*/
    }
    
    /*
     this fetches ALL transactions from the Wallet. Could be a lot.
     this is only used for importing transactions?
     */
    func fetchhWalletTransactionsForAccounts(accounts:[Account], logPrefix:String = "") async throws -> [Transaction]{
        var transactionsFound: [Transaction] = []
        let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
        
        
        let accountUUIDs = accounts.compactMap { UUID(uuidString: $0.id) }
        let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: #Predicate<FinanceKit.Transaction>{transaction in
            accountUUIDs.contains(transaction.accountID)
        })
        
        // this fetches all transactions.. 
        //let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: nil)

        let transactions = try await FinanceStore.shared.transactions(query: query)
        //print("Fetched \(transactions.count) transactions from \(accounts.count) accounts:")
        
        for transaction in transactions {
            //print(transaction)
            
            // Find matching account name from accounts array
            let account = accounts.first(where: { $0.id == transaction.accountID.uuidString })
            let accountName = account?.name ?? ""
            let syncBalanceOnly = account?.syncBalanceOnly ?? false
            
            var amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
            if transaction.creditDebitIndicator == .credit {
                amount = amount * -1
            }
            
            //print("fetchhWalletTransactionsForAccounts \(payeeDescription) \(transaction.status)=\(isPending)")
            
            let category_id = transaction.merchantCategoryCode.map { String(describing: $0) }
            let category_name = category_id.flatMap { getMCCDescription(for: $0) }
            
            let t = Transaction(
                id: transaction.id.uuidString,
                account: accountName,
                payee: transaction.transactionDescription,
                amount: amount,
                date: transaction.transactionDate,
                lm_id: "",
                lm_account: "",
                notes: transaction.status == .booked ? "booked" : "pending",
                category: "",
                type: String(describing: transaction.transactionType),
                accountID: transaction.accountID.uuidString,
                status: "",
                isPending: transaction.status == .booked ? false : true,
                sync: syncBalanceOnly ? .never : .pending,
                lm_category_id: "",
                lm_category_name: "",
                category_id: category_id,
                category_name: category_name
            )
            t.addHistory(note: syncBalanceOnly ? "Created from fetch, skipping sync" : "Created from fetch", source:logPrefix)
            transactionsFound.append(t)
        }
        
        return transactionsFound
    }
    
    func getPreFetchedWalletData(logPrefix: String = "") async throws -> PreFetchedWalletData{
        do{
            let transactions = try await self.getRecentTransactions(logPrefix: logPrefix)
            let accounts = try await self.getWalletAccounts()
            let pfwd: PreFetchedWalletData = .init(
                transactions: transactions,
                accounts: accounts
            )
            return pfwd
        } catch {
            print("getRecentTransactions failed to fetch transactions from FinanceStore: \(error.localizedDescription)")
            throw NSError(domain: "AppleWallet", code: -2, userInfo: [NSLocalizedDescriptionKey: "getRecentTransactions failed to fetch transactions from FinanceStore: \(error.localizedDescription)"])
        }
    }
    
    // this is a "safe" version meant to be the first thing that is called in the background extension
    // it attempts to only fetch the FinanceKit data
    func getRecentTransactions(logPrefix: String="") async throws -> [Transaction] {
        print("getRecentTransactions starting")
        
        // pick a date one month in the past
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
        let query = TransactionQuery(
            sortDescriptors: [sortDescriptor],
            predicate: #Predicate<FinanceKit.Transaction> { transaction in
                transaction.transactionDate >= startDate &&
                transaction.transactionDate <= endDate
            }
        )
        
        print("Executing FinanceStore query for date range \(startDate) to \(endDate)")
        var transactions: [FinanceKit.Transaction]
        do {
            transactions = try await FinanceStore.shared.transactions(query: query)
            print("getRecentTransactions got \(transactions.count) transactions")
        } catch {
            print("getRecentTransactions failed to fetch transactions from FinanceStore: \(error.localizedDescription)")
            throw NSError(domain: "AppleWallet", code: -2, userInfo: [NSLocalizedDescriptionKey: "getRecentTransactions failed to fetch transactions from FinanceStore: \(error.localizedDescription)"])
        }

        var transactionsFound: [Transaction] = []
        
        for transaction in transactions {
            var amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
            if transaction.creditDebitIndicator == .credit {
                amount = amount * -1
            }
            
            let category_id = transaction.merchantCategoryCode.map { String(describing: $0) }
            
            print("Recent transaction: \(transaction.transactionDescription), \(transaction.transactionAmount.amount), \(transaction.transactionDate)")
            
            let t = Transaction(
                id: transaction.id.uuidString,
                account: "",
                payee: transaction.transactionDescription,
                amount: amount,
                date: transaction.transactionDate,
                lm_id: "",
                lm_account: "",
                notes: transaction.status == .booked ? "booked" : "pending",
                category: "",
                type: String(describing: transaction.transactionType),
                accountID: transaction.accountID.uuidString,
                status: "",
                isPending: transaction.status == .booked ? false : true,
                sync: .pending,
                lm_category_id: "",
                lm_category_name: "",
                category_id: category_id,
                category_name: "" // leave this blank so we don't have to touch the MCC code file until these transactions are prepped in SyncBroker
            )
            t.addHistory(note: "Created from recent", source: logPrefix)
            transactionsFound.append(t)
        }
        print("returning \(transactionsFound.count) transactions")
        
        return transactionsFound
    }
    
    /*
     this is meant to fetch the latest transactions
     called only from SyncBroker
     */
    func refreshWalletTransactionsForAccounts(accounts:[Account], logPrefix: String="") async throws -> [Transaction] {
        print("refreshWalletTransactionsForAccounts called with \(accounts.count) accounts, isBackgroundExtension: \(isBackgroundExtension)")
        
        // Check if we have authorization to access FinanceKit data
        if !isSimulator {
            // In background extension context, we might not need to request authorization again
            // as the extension should inherit the authorization from the main app
            if !isBackgroundExtension {
                print("Requesting FinanceKit authorization in main app context")
                let currentAuthStatus = await requestAuth()
                guard currentAuthStatus == .authorized else {
                    print("FinanceKit authorization not granted. Status: \(currentAuthStatus)")
                    throw NSError(domain: "AppleWallet", code: -1, userInfo: [NSLocalizedDescriptionKey: "FinanceKit authorization not granted. Status: \(currentAuthStatus)"])
                }
            } else {
                // For background extension, just check if data is available
                print("Checking FinanceKit data availability in background extension context")
                if !dataAvailable() {
                    print("FinanceKit data not available in background extension")
                    throw NSError(domain: "AppleWallet", code: -3, userInfo: [NSLocalizedDescriptionKey: "FinanceKit data not available in background extension"])
                }
                print("FinanceKit data is available in background extension")
            }
        }
        
        // Convert all account string IDs to UUIDs, filtering out any invalid UUIDs
        let accountUUIDSet = Set(accounts.compactMap { UUID(uuidString: $0.id) })
        
        // Check if we have any valid account UUIDs
        guard !accountUUIDSet.isEmpty else {
            print("No valid account UUIDs found")
            return []
        }

        //print("Processing \(accountUUIDs.count) valid account UUIDs")

        // pick a date one month in the past
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
        // Avoid including a dynamic "IN" list in the predicate; fetch by date and filter in Swift.
        let query = TransactionQuery(
            sortDescriptors: [sortDescriptor],
            predicate: #Predicate<FinanceKit.Transaction> { transaction in
                transaction.transactionDate >= startDate &&
                transaction.transactionDate <= endDate
            }
        )

        print("Executing FinanceStore query for date range \(startDate) to \(endDate)")

        // Wrap the FinanceStore call in a try-catch to handle potential authorization issues
        var transactions: [FinanceKit.Transaction]
        do {
            transactions = try await FinanceStore.shared.transactions(query: query)
            print("refreshWalletTransactionsForAccounts got \(transactions.count) transactions (pre-filter) for date range")
        } catch {
            print("Failed to fetch transactions from FinanceStore: \(error.localizedDescription)")
            
            // If we're in a background extension and the error seems to be authorization-related, 
            // try to wait a bit and retry once
            if isBackgroundExtension {
                print("Retrying FinanceStore call in background extension context...")
                do {
                    // Wait a short time for authorization to be established
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    transactions = try await FinanceStore.shared.transactions(query: query)
                    print("Retry successful: got \(transactions.count) transactions")
                } catch {
                    print("Retry also failed: \(error.localizedDescription)")
                    throw NSError(domain: "AppleWallet", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch transactions from FinanceStore after retry: \(error.localizedDescription)"])
                }
            } else {
                throw NSError(domain: "AppleWallet", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch transactions from FinanceStore: \(error.localizedDescription)"])
            }
        }
        
        // Filter the fetched transactions by the allowed accounts
        let filteredTransactions = transactions.filter { accountUUIDSet.contains($0.accountID) }
        print("Filtered[x] to \(filteredTransactions.count) transactions for \(accountUUIDSet.count) accounts")

        var transactionsFound: [Transaction] = []
        
        for transaction in filteredTransactions {
            let account = accounts.first(where: { $0.id == transaction.accountID.uuidString })
            let accountName = account?.name ?? ""
            let syncBalanceOnly = account?.syncBalanceOnly ?? false
            print("refreshWalletTransactionsForAccounts: \(accountName) = \(syncBalanceOnly)")
            var amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
            if transaction.creditDebitIndicator == .credit {
                amount = amount * -1
            }
            //print(transaction)
            let category_id = transaction.merchantCategoryCode.map { String(describing: $0) }
            let category_name = category_id.flatMap { getMCCDescription(for: $0) }
            
            //print("refreshWalletTransactionsForAccounts \(payeeDescription) \(transaction.status)=\(isPending)")
            //print("refreshWalletTransactionsForAccounts \(transaction.transactionDescription) cat_id=\(category_id ?? "n/a"), cat_name=\(category_name ?? "n/a")")
            if(!syncBalanceOnly){
                print("Sync balance and transaction")
                let t = Transaction(
                    id: transaction.id.uuidString,
                    account: accountName,
                    payee: transaction.transactionDescription,
                    amount: amount,
                    date: transaction.transactionDate,
                    lm_id: "",
                    lm_account: "",
                    notes: transaction.status == .booked ? "booked" : "pending",
                    category: "",
                    type: String(describing: transaction.transactionType),
                    accountID: transaction.accountID.uuidString,
                    status: "",
                    isPending: transaction.status == .booked ? false : true,
                    sync: syncBalanceOnly ? .never : .pending,
                    lm_category_id: "",
                    lm_category_name: "",
                    category_id: category_id,
                    category_name: category_name
                )
                t.addHistory(note: syncBalanceOnly ? "Created from refresh, skipping sync" : "Created from refresh", source:logPrefix)
                transactionsFound.append(t)
            }else{
                print("Sync balance only")
            }
        }
        print("returning \(transactionsFound.count) transactions")
        
        return transactionsFound
    }
    
    private func fetchBalances(accountId: UUID) async throws -> AccountBalance {
        //             balance.available != nil &&
        let predicate = #Predicate<AccountBalance> { balance in
            balance.accountID == accountId
        }
        // TODO sort by the most recent?
        let query = AccountBalanceQuery(sortDescriptors: [], predicate: predicate, limit: 1000, offset: 0)
        let balances = try await FinanceStore.shared.accountBalances(query: query).reversed()
        for balance in balances {
            return balance
        }
        throw NSError(domain: "FetchBalances", code: -1, userInfo: [NSLocalizedDescriptionKey: "No balance found"])
    }
    
    private func fetchTransactions() {
        Task {
            do {
                // Create date range for the past month
                let calendar = Calendar.current
                let endDate = Date()
                let startDate = calendar.date(byAdding: .month, value: -1, to: endDate)!
                
                let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
                
                let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: #Predicate<FinanceKit.Transaction>{transaction in
                    transaction.transactionDate >= startDate &&
                    transaction.transactionDate <= endDate
                }, limit: 1000, offset: 0)
                
                _ = try await FinanceStore.shared.transactions(query: query)
                //print("Fetched \(transactions.count) from \(startDate.formatted()) to \(endDate.formatted()):")
                //for transaction in transactions {
                    //print("- \(transaction.id) / \(transaction.accountID) \(String(describing: transaction.merchantName)): \(transaction.transactionAmount.amount)")
                    //print(transaction)
                //}
            } catch {
                print("Error fetching: \(error.localizedDescription)")
            }
        }
    }
}
