//
//  MockAppleWallet.swift
//  LMPlayground
//
//  Created by Bob Sanders on 12/7/24.
import SwiftUI
import SwiftData
import FinanceKit
import Combine

class MockWallet: Wallet {
    @Published var transactions: [Transaction] = []
    let context: ModelContext
    var apiToken: String
    
    override required init(context: ModelContext, apiToken: String) {
        self.context = context
        self.apiToken = apiToken
        super.init(context: context, apiToken: apiToken)
        // Add some mock transactions
        self.transactions = [
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Store", amount: 42.0, date: Date(), lm_id: "", lm_account: "", sync: .pending),
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Shop", amount: 24.0, date: Date(), lm_id: "", lm_account: "", sync: .skipped)
        ]
    }
    
    struct SyncProgress {
        let current: Int
        let total: Int
        let status: String
    }
    
    override func getTransactionsWithStatus(_ status: Transaction.SyncStatus) -> [Transaction] {
        return transactions.filter { $0.sync == status }
    }
    
    override func getTransactionsWithStatus(_ statuses: [Transaction.SyncStatus]) -> [Transaction] {
        return transactions.filter { statuses.contains($0.sync) }
    }
    
    override func getSyncedAccounts() -> [Account] {
        return [
            Account(id: "1", name: "Mock Account 1", balance: 1000, lm_id: "", lm_name: ""),
            Account(id: "2", name: "Mock Account 2", balance: 2000, lm_id: "", lm_name: "")
        ]
    }
    
    override func addLog(message: String, level: Int) {}
    
    override func replaceTransaction(newTrans: Transaction) {
        if let index = transactions.firstIndex(where: { $0.id == newTrans.id }) {
            transactions[index] = newTrans
        } else {
            transactions.append(newTrans)
        }
    }
    
    override func getAPIAccountName() async throws -> String {
        return "Account Holder"
    }
    override func getAPIAccount() async throws -> User {
        return User(userName: "Account Holder", userEmail: "test@test.com", userId: 1234, accountId: 1234, budgetName: "Test Budget", primaryCurrency: "usd", apiKeyLabel: "api_key_label")
    }
    
    
    /*
    override func syncTransactions(progressCallback: @escaping (MockWallet.SyncProgress) -> Void) async throws {
        // Simulate sync progress
        progressCallback(MockWallet.SyncProgress(current: 5, total: 10, status: "Syncing..."))
    }
    */
    
    //override func syncAccountBalances(accounts: [Account]) async throws {}
    
    //override func addNotification(time: Double, title: String, subtitle: String, body: String) async {}
    override func getTrnCategories() -> [TrnCategory] {
        print("MOCK getTrnCategories")
        // Create sample LMCategory objects
        /*
        let foodCategory = LMCategory(id: "1", name: "Food & Dining", descript: "Restaurants and food purchases", exclude_from_budget: false, exclude_from_totals: false)
        let gasCategory = LMCategory(id: "2", name: "Gas & Fuel", descript: "Gas stations and fuel", exclude_from_budget: false, exclude_from_totals: false)
        let shoppingCategory = LMCategory(id: "3", name: "Shopping", descript: "General merchandise", exclude_from_budget: false, exclude_from_totals: false)
        */
        var categories: [TrnCategory] = []
        let cat1 = TrnCategory(mcc: "5812", name: "Eating Places/Restaurants")
        cat1.set_lm_category(id: "1", name: "Food & Dining", descript: "Restaurants and food purchases",
            exclude_from_budget: false, exclude_from_totals: false
        )
        categories.append(cat1)

        let cat2 = TrnCategory(mcc: "5411", name: "Grocery Stores, Supermarkets")
        cat2.set_lm_category(id: "2", name: "Food & Dining", descript: "Restaurants and food purchases",
            exclude_from_budget: false, exclude_from_totals: false
        )
        categories.append(cat2)
        
        let cat3 = TrnCategory(mcc: "5311", name: "Department Stores")
        cat3.set_lm_category(id: "3", name: "Shopping", descript: "General merchandise",
            exclude_from_budget: false, exclude_from_totals: false
        )
        categories.append(cat3)

        let cat4 = TrnCategory(mcc: "5611", name: "Education")
        cat4.set_lm_category(id: "0", name: "Skip Mapping", descript: "Not mapped to Lunch Money",
            exclude_from_budget: false, exclude_from_totals: false
        )
        categories.append(cat4)
        /*
        let categories = [
            TrnCategory(mcc: "5411", name: "Grocery Stores, Supermarkets", lm_category: foodCategory),
            TrnCategory(mcc: "5311", name: "Department Stores", lm_category: nil),
            TrnCategory(mcc: "9999", name: "", lm_category: nil), // Test empty name case
            TrnCategory(mcc: "5814", name: "Fast Food Restaurants", lm_category: foodCategory),
            TrnCategory(mcc: "5999", name: "Miscellaneous and Specialty Retail Stores", lm_category: shoppingCategory)
        ]
         */
        return categories
    }
}
