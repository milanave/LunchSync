import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 5) {
                HStack{
                    Image("IconApp") // Changed from systemName to use AppIcon asset
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(22) // Added to match iOS app icon style
                    
                    Text("Wallet Sync")
                        .font(.title)
                        .bold()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instructions")
                        .font(.headline)
                    
                    Text("1. Connect your Lunch Money account with your API token.\n2. Select Wallet accounts to sync, pair each one with a Lunch Money asset.\n3. Sync transactions manually, enable background sync, or install the shortcuts below to set your own schedule.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: "https://littlebluebug.com/wallet.php") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Release notes")
                            
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shortcuts")
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
                }
                .padding()
                .frame(maxWidth: .infinity)
                Spacer()
                VStack(spacing: 8) {
                    Text("Version 1.1")
                        .font(.body)
                    Button {
                        if let url = URL(string: "https://www.littlebluebug.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("https://www.littlebluebug.com")
                            .font(.footnote)
                    }
                    Button {
                        if let url = URL(string: "mailto:support@littlebluebug.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("support@littlebluebug.com")
                            .font(.footnote)
                    }
                }

            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium])
    }
}

#Preview {
    AboutView()
} 
