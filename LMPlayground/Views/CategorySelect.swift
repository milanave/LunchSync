//
//  CategorySelect.swift
//  LMPlayground
//
//  Created by Bob Sanders on 8/2/25.
//

import SwiftUI
import SwiftData

struct CategorySelect: View {
    @Binding var category: TrnCategory
    @Query(sort: \LMCategory.name) private var lmCategories: [LMCategory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingCategories = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    
    private var filteredCategories: [LMCategory] {
        return lmCategories.filter { category in
            searchText.isEmpty || 
            category.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
                
                TextField("Search categories...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
            
            // Categories list
            List {
                Section {
                    if filteredCategories.isEmpty {
                        if lmCategories.isEmpty {
                            Text("No LunchMoney categories available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            Text("No categories match your search criteria")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                    } else {
                        ForEach(filteredCategories, id: \.id) { lmCategory in
                            Button(action: {
                                assignMapping(lmCategory: lmCategory)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(lmCategory.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            if lmCategory.exclude_from_budget {
                                                Image(systemName: "minus.circle")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                            if lmCategory.exclude_from_totals {
                                                Image(systemName: "sum")
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        if !lmCategory.descript.isEmpty {
                                            Text(lmCategory.descript)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if category.lm_category?.id == lmCategory.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await loadLunchMoneyCategories()
                        }
                    }) {
                        HStack {
                            if isLoadingCategories {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 8)
                            }
                            Text("Load LunchMoney Categories")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isLoadingCategories)
                    .padding(.vertical, 4)
                }
            }
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func assignMapping(lmCategory: LMCategory) {
        category.lm_category = lmCategory
        do {
            try modelContext.save()
            print("Successfully assigned mapping: \(category.name) -> \(lmCategory.name)")
            dismiss()
        } catch {
            errorMessage = "Failed to assign mapping: \(error.localizedDescription)"
            print("Error assigning mapping: \(error.localizedDescription)")
        }
    }
    
    private func loadLunchMoneyCategories() async {
        isLoadingCategories = true
        
        do {
            let keychain = Keychain()
            guard let apiToken = try? keychain.retrieveTokenFromKeychain() else {
                errorMessage = "No API token found. Please configure your LunchMoney API token first."
                print("No API token found")
                isLoadingCategories = false
                return
            }
            
            let api = LunchMoneyAPI(apiToken: apiToken, debug: false)
            let categoriesAPI = try await api.getCategories()
            
            // Clear existing categories
            let existingCategories = lmCategories
            for category in existingCategories {
                modelContext.delete(category)
            }
            
            // Convert and save new categories
            for categoryAPI in categoriesAPI {
                let lmCategory = LMCategory(
                    id: String(categoryAPI.id),
                    name: categoryAPI.name,
                    descript: categoryAPI.description ?? "",
                    exclude_from_budget: categoryAPI.excludeFromBudget,
                    exclude_from_totals: categoryAPI.excludeFromTotals
                )
                modelContext.insert(lmCategory)
            }
            
            try modelContext.save()
            print("Successfully loaded \(categoriesAPI.count) categories from LunchMoney")
            
        } catch {
            errorMessage = "Failed to load categories: \(error.localizedDescription)"
            print("Error loading LunchMoney categories: \(error.localizedDescription)")
        }
        
        isLoadingCategories = false
    }
}

#Preview {
    @Previewable @State var sampleCategory = TrnCategory(mcc: "5812", name: "Eating Places/Restaurants", lm_category: nil)
    
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TrnCategory.self, LMCategory.self, configurations: config)
    
    // Create sample LMCategory objects
    let foodCategory = LMCategory(id: "1", name: "Food & Dining", descript: "Restaurants and food purchases", exclude_from_budget: false, exclude_from_totals: false)
    let gasCategory = LMCategory(id: "2", name: "Gas & Fuel", descript: "Gas stations and fuel", exclude_from_budget: false, exclude_from_totals: false)
    let shoppingCategory = LMCategory(id: "3", name: "Shopping", descript: "General merchandise", exclude_from_budget: false, exclude_from_totals: false)
    
    // Insert mock data into the container
    let context = container.mainContext
    context.insert(foodCategory)
    context.insert(gasCategory)
    context.insert(shoppingCategory)
    context.insert(sampleCategory)
    
    return NavigationStack {
        CategorySelect(category: .constant(sampleCategory))
            .modelContainer(container)
    }
}
