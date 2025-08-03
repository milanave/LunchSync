//
//  CategoryMap.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/2/25.
//

import SwiftUI
import SwiftData

struct CategoryMap: View {
    @State var category: TrnCategory
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @Query private var allTransactions: [Transaction]
    
    var body: some View {
        VStack(spacing: 0) {
            // Category details section
            List {
                Section {
                    Text(displayName(for: category))
                        .font(.headline)
                        .fontWeight(.semibold)
                } header: {
                    Text("Wallet Category")
                }
                Section{
                    NavigationLink(destination: CategorySelect(category: $category)) {
                        HStack {
                            if let lmCategory = category.lm_category {
                                Text(lmCategory.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }else{
                                Text("Unmapped")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                            
                        }
                    }
                } header: {
                    Text("Lunch Money Category")
                }
                
                Section{
                    if recentTransactions.isEmpty {
                        Text("No transactions found for this category")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(recentTransactions, id: \.id) { transaction in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(transaction.payee)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("$\(transaction.amount, specifier: "%.2f")")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(transaction.amount < 0 ? .red : .primary)
                                }
                                HStack {
                                    Text(transaction.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(transaction.account)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                                } header:{
                    Text("Recent transactions")
                }
                
                Section{
                    Text("Remove mapping")
                        .foregroundColor(.red)                        
                }
                .onTapGesture {
                    removeMapping()
                }
            }

        }
        .navigationTitle("Category Mapping")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: category.lm_category) { oldValue, newValue in
            // Only trigger if we're actually assigning a new category (not removing)
            if newValue != nil {
                assignTransactionsAndResync()
            }
        }
        .alert(errorMessage != nil ? "Error" : "Success", isPresented: Binding<Bool>(
            get: { errorMessage != nil || successMessage != nil },
            set: { _ in 
                errorMessage = nil
                successMessage = nil
            }
        )) {
            Button("OK") {
                errorMessage = nil
                successMessage = nil
            }
        } message: {
            Text(errorMessage ?? successMessage ?? "")
        }
    }
    
    private func displayName(for category: TrnCategory) -> String {
        let name = category.name.isEmpty ? "Unknown Category" : category.name
        return "\(name) (\(category.mcc))"
    }
    
    private var recentTransactions: [Transaction] {
        return allTransactions
            .filter { $0.category_id == category.mcc }
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { $0 }
    }
    
    private var allMatchingTransactions: [Transaction] {
        return allTransactions
            .filter { $0.category_id == category.mcc }
    }
    
    private func removeMapping() {
        category.lm_category = nil
        do {
            try modelContext.save()
            print("Successfully removed mapping for category: \(category.name)")
        } catch {
            errorMessage = "Failed to remove mapping: \(error.localizedDescription)"
            print("Error removing mapping: \(error.localizedDescription)")
        }
    }
    
    private func assignTransactionsAndResync() {
        guard let lmCategory = category.lm_category else {
            errorMessage = "No LunchMoney category assigned to this category"
            return
        }
        
        // Create wallet instance like SyncBroker does
        let keychain = Keychain()
        let apiToken: String
        do {
            apiToken = try keychain.retrieveTokenFromKeychain()
        } catch {
            apiToken = ""
        }
        
        #if DEBUG
        let wallet: Wallet
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            wallet = MockWallet(context: modelContext, apiToken: "mock-token")
        } else {
            wallet = Wallet(context: modelContext, apiToken: apiToken)
        }
        #else
        let wallet = Wallet(context: modelContext, apiToken: apiToken)
        #endif
        
        // Iterate through each matching transaction and update it
        for transaction in allMatchingTransactions {
            transaction.lm_category_id = lmCategory.id
            transaction.lm_category_name = lmCategory.name
            wallet.setSyncStatus(newTrans: transaction, newStatus: .pending)
        }
        
        do {
            try modelContext.save()
            successMessage = "\(allMatchingTransactions.count) transactions categorized"
            print("Successfully assigned \(allMatchingTransactions.count) transactions to category: \(lmCategory.name)")
        } catch {
            errorMessage = "Failed to assign transactions: \(error.localizedDescription)"
            print("Error assigning transactions: \(error.localizedDescription)")
        }
    }
    

}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TrnCategory.self, LMCategory.self, Transaction.self, configurations: config)
    
    // Create sample LMCategory objects
    let foodCategory = LMCategory(id: "1", name: "Food & Dining", descript: "Restaurants and food purchases", exclude_from_budget: false, exclude_from_totals: false)
    let gasCategory = LMCategory(id: "2", name: "Gas & Fuel", descript: "Gas stations and fuel", exclude_from_budget: false, exclude_from_totals: false)
    let shoppingCategory = LMCategory(id: "3", name: "Shopping", descript: "General merchandise", exclude_from_budget: false, exclude_from_totals: false)
    let transportCategory = LMCategory(id: "4", name: "Transportation", descript: "Public transport and ride sharing", exclude_from_budget: false, exclude_from_totals: false)
    let entertainmentCategory = LMCategory(id: "5", name: "Entertainment", descript: "Movies, games, and fun activities", exclude_from_budget: false, exclude_from_totals: false)
    
    // Create sample TrnCategory with LM category
    let mappedCategory = TrnCategory(mcc: "5812", name: "Eating Places/Restaurants", lm_category: foodCategory)
    
    // Create sample transactions for this category
    let transactions = [
        Transaction(id: "1", account: "Apple Card", payee: "McDonald's", amount: -12.45, date: Date().addingTimeInterval(-86400), lm_id: "", lm_account: "", category_id: "5812"),
        Transaction(id: "2", account: "Apple Card", payee: "Starbucks", amount: -5.67, date: Date().addingTimeInterval(-172800), lm_id: "", lm_account: "", category_id: "5812"),
        Transaction(id: "3", account: "Apple Card", payee: "Pizza Hut", amount: -24.99, date: Date().addingTimeInterval(-259200), lm_id: "", lm_account: "", category_id: "5812"),
        Transaction(id: "4", account: "Apple Card", payee: "Burger King", amount: -8.50, date: Date().addingTimeInterval(-345600), lm_id: "", lm_account: "", category_id: "5812")
    ]
    
    // Insert mock data into the container
    let context = container.mainContext
    context.insert(foodCategory)
    context.insert(gasCategory)
    context.insert(shoppingCategory)
    context.insert(transportCategory)
    context.insert(entertainmentCategory)
    context.insert(mappedCategory)
    
    for transaction in transactions {
        context.insert(transaction)
    }
    
    return NavigationStack {
        CategoryMap(category: mappedCategory)
            .modelContainer(container)
    }
}

