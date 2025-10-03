//
//  CategoryView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/2/25.
//

import SwiftUI
import SwiftData

struct CategoryView: View {
    //@Query(sort: \TrnCategory.name) private var categories: [TrnCategory]
    @State var categories: [TrnCategory] = []
    @Environment(\.modelContext) private var modelContext
    @StateObject private var wallet: Wallet
    private let appDelegate: AppDelegate
    @State var storedCategories: [CategoryMapping] = []
    @State private var showingAlert: Bool = false
    
    init(context: ModelContext, appDelegate: AppDelegate){
        self.appDelegate = appDelegate
        
        let keychain = Keychain()
        let apiToken: String
        do {
            apiToken = try keychain.retrieveTokenFromKeychain()
        } catch {
            apiToken = ""
        }
        
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let wallet = MockWallet(context: context, apiToken: "mock-token")
            _wallet = StateObject(wrappedValue: wallet)
        } else {
            let wallet = Wallet(context: context, apiToken: apiToken)
            _wallet = StateObject(wrappedValue: wallet)
        }
        #else
        let wallet = Wallet(context: context, apiToken: apiToken)
        _wallet = StateObject(wrappedValue: wallet)
        #endif
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedCategories, id: \.mcc) { category in
                        NavigationLink(destination: CategoryMap(category: category)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayName(for: category))
                                    .font(.headline)
                                if !category.lm_id.isEmpty {
                                    Text("\(category.lm_name)")
                                        .font(.caption)
                                        .foregroundColor( category.lm_id=="0" ? .yellow : .green)
                                } else {
                                    Text("Unmapped")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                Button(role: .destructive, action: {
                    showingAlert = true
                }) {
                    Text("Restore \(storedCategories.count) Categories")
                }.alert(Text("Restore your category mappings?"),
                    isPresented: $showingAlert,
                    actions: {
                        Button("Yes", role: .destructive) {
                            wallet.restoreCategories()
                            categories = wallet.getTrnCategories()
                        }
                        Button("Cancel", role: .cancel) { }
                    }, message: {
                        if(sortedCategories.count==0){
                            Text("There are \(storedCategories.count) category mappings stored. Would you like to restore them?")
                        }else{
                            Text("There are \(storedCategories.count) category mappings stored. Delete the current \(sortedCategories.count) mappings and replace with these?")
                        }
                    }
                )
            }
            .navigationTitle("Wallet Categories")
        }.onAppear {
            wallet.backupCategories()
            categories = wallet.getTrnCategories()
            storedCategories = wallet.getStoredCategories()            
        }
    }
    
    private var sortedCategories: [TrnCategory] {
        categories.sorted { category1, category2 in
            // Sort categories with empty lm_id first
            let empty1 = category1.lm_id.isEmpty
            let empty2 = category2.lm_id.isEmpty
            if empty1 != empty2 {
                return empty1
            }
            let name1 = category1.name.isEmpty ? "Unknown Category" : category1.name
            let name2 = category2.name.isEmpty ? "Unknown Category" : category2.name
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
    
    private func displayName(for category: TrnCategory) -> String {
        return category.name.isEmpty ? "Unknown Category \(category.mcc)" : category.name
    }
    
    
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TrnCategory.self, LMCategory.self, configurations: config)
    let context = container.mainContext
    /*
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

    
    for category in categories {
        context.insert(category)
    }
    */
    return CategoryView(context: context, appDelegate: AppDelegate())
        .modelContainer(container)
}
