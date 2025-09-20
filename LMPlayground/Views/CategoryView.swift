//
//  CategoryView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/2/25.
//

import SwiftUI
import SwiftData

struct CategoryView: View {
    @Query(sort: \TrnCategory.name) private var categories: [TrnCategory]
    
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
            }
            .navigationTitle("Wallet Categories")
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
    
    // Create sample LMCategory objects
    let foodCategory = LMCategory(id: "1", name: "Food & Dining", descript: "Restaurants and food purchases", exclude_from_budget: false, exclude_from_totals: false)
    let gasCategory = LMCategory(id: "2", name: "Gas & Fuel", descript: "Gas stations and fuel", exclude_from_budget: false, exclude_from_totals: false)
    let shoppingCategory = LMCategory(id: "3", name: "Shopping", descript: "General merchandise", exclude_from_budget: false, exclude_from_totals: false)
    
    // Create sample TrnCategory objects
    let categories = [
        TrnCategory(mcc: "5812", name: "Eating Places/Restaurants", lm_category: foodCategory),
        TrnCategory(mcc: "5541", name: "Service Stations", lm_category: gasCategory),
        TrnCategory(mcc: "5411", name: "Grocery Stores, Supermarkets", lm_category: foodCategory),
        TrnCategory(mcc: "5311", name: "Department Stores", lm_category: nil),
        TrnCategory(mcc: "9999", name: "", lm_category: nil), // Test empty name case
        TrnCategory(mcc: "5814", name: "Fast Food Restaurants", lm_category: foodCategory),
        TrnCategory(mcc: "5999", name: "Miscellaneous and Specialty Retail Stores", lm_category: shoppingCategory)
    ]
    
    // Insert mock data into the container
    let context = container.mainContext
    context.insert(foodCategory)
    context.insert(gasCategory)
    context.insert(shoppingCategory)
    
    for category in categories {
        context.insert(category)
    }
    
    return CategoryView()
        .modelContainer(container)
}
