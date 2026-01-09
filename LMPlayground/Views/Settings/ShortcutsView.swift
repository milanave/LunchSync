//
//  APIImportRulesView.swift
//  LMPlayground
//
//  Created by AI Assistant on 1/9/26.
//

import SwiftUI

struct ShortcutsView: View {
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You can control LunchSync from Apple's Shortcuts app.")
                .font(.headline)
            
            Button {
                if let url = URL(string: "https://www.icloud.com/shortcuts/40daca0cf7e44543a0e2ce8ea02b29dd") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Import Check for Transactions", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("The Check For Transactions shortcut checks Wallet for new transactions and adds them to the import queue. Use this if you want to review transactions before they are imported.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            
            Button {
                if let url = URL(string: "https://www.icloud.com/shortcuts/a96ad0147e024d8cbeba78260a0c106d") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Import Sync Transactions", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("The Sync Transactions shortcut checks Wallet for new transactions and syncs them to your LunchMoney account.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding()
        
        .navigationTitle("Shortcuts")
    }
}

#Preview {
    NavigationView {
        ShortcutsView()
    }
}


