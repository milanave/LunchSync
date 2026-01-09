//
//  APIImportRulesView.swift
//  LMPlayground
//
//  Created by AI Assistant on 1/9/26.
//

import SwiftUI

struct InstructionsView: View {
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. Connect your Lunch Money account with your API token.\n2. Select Wallet accounts to sync, pair each one with a Lunch Money asset.\n3. Sync transactions manually, enable background sync, or install the shortcuts below to set your own schedule.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            Text("\nBackground delivery is now availble with iOS 26. Enable it to sync transactions in real-time, up to once per hour. ")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .navigationTitle("Instructions")
    }
}

#Preview {
    NavigationView {
        InstructionsView()
    }
}


