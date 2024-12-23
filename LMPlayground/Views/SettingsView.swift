//
//  SettingsView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Binding var isShowingTokenPrompt: Bool
    @Binding var isShowingAccountSelection: Bool
    
    var body: some View {
        NavigationView {
            List {
                Button(action: {
                    isShowingTokenPrompt = true
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.blue)
                        Text("Update API Token")
                    }
                }
                
                Button(action: {
                    isShowingAccountSelection = true
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundColor(.blue)
                        Text("Select Wallet Accounts")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
}
