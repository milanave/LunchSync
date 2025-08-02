import Foundation
import FinanceKit
import FinanceKitUI

struct MCCCode: Codable {
    let id: Int
    let mcc: String
    let description: String
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
    
    private func getMCCDescription(for mccCode: String) -> String? {
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
        var accounts: [Account] = []
        let walletAccounts: [FinanceKit.Account] = try await fetchAccounts()
        for acct in walletAccounts {
            //print("getWalletAccounts \(acct.displayName) \(acct.id)")
            
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
        return dataAvail
    }
    
    func requestAuth() async -> AuthorizationStatus {
        if isSimulator {
            return .authorized
        }
        
        do {
            let status = try await FinanceStore.shared.requestAuthorization()
            //print("Authorization granted")
            return status
        } catch {
            //print("Authorization request error: \(error.localizedDescription)")
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
     TODO: put a limit here?
     */
    func fetchhWalletTransactionsForAccounts(accounts:[Account]) async throws -> [Transaction]{
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
            let accountName = accounts.first(where: { $0.id == transaction.accountID.uuidString })?.name ?? ""
            var amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
            if transaction.creditDebitIndicator == .credit {
                amount = amount * -1
            }
            
            let isPending = transaction.status == .booked ? false : true
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
                isPending: isPending,
                sync: .pending,
                lm_category_id: "",
                lm_category_name: "",
                category_id: category_id,
                category_name: category_name
            )
            transactionsFound.append(t)
        }
        
        return transactionsFound
    }
    
    /*
     this is meant to fetch the latest transactions
     */
    func refreshWalletTransactionsForAccounts(accounts:[Account]) async throws -> [Transaction] {
        // Convert all account string IDs to UUIDs, filtering out any invalid UUIDs
        let accountUUIDs = accounts.compactMap { UUID(uuidString: $0.id) }

        // pick a date one month in the past
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
        
        let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
        let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: #Predicate<FinanceKit.Transaction>{transaction in
            accountUUIDs.contains(transaction.accountID) &&
            transaction.transactionDate >= startDate &&
            transaction.transactionDate <= endDate
        })

        let transactions = try await FinanceStore.shared.transactions(query: query)
        //print("refreshWalletTransactionsForAccounts got \(transactions.count) transactions from \(accounts.count) accounts:")
        
        var transactionsFound: [Transaction] = []
        
        for transaction in transactions {
            let accountName = accounts.first(where: { $0.id == transaction.accountID.uuidString })?.name ?? ""
            var amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
            if transaction.creditDebitIndicator == .credit {
                amount = amount * -1
            }
            //print(transaction)
            let category_id = transaction.merchantCategoryCode.map { String(describing: $0) }
            //print(" -- \(transaction.transactionDescription) \(amount) \(accountName) \(transaction.id.uuidString)")
            
            // Look up MCC description
            let category_name = category_id.flatMap { getMCCDescription(for: $0) }
            
            //print("refreshWalletTransactionsForAccounts \(payeeDescription) \(transaction.status)=\(isPending)")
            //print("refreshWalletTransactionsForAccounts \(transaction.transactionDescription) cat_id=\(category_id ?? "n/a"), cat_name=\(category_name ?? "n/a")")
            
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
                sync: .pending,
                lm_category_id: "",
                lm_category_name: "",
                category_id: category_id,
                category_name: category_name
            )
            transactionsFound.append(t)                    
        }
        //print("returning \(transactionsFound.count)")
        
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
