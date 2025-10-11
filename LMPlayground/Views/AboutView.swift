import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
        let is_test_flight = sharedDefaults.bool(forKey: "is_test_flight")
        return "\(version) (\(build))\(is_test_flight ? " Test Flight" : "")"
    }
    private let storage = Storage()
    
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
                    Text("Weekly Spending: \(niceAmount(NSDecimalNumber(decimal: storage.getWeeklySpending()).doubleValue))")
                        .font(.footnote)
                    if let last = storage.getLastCheck() {
                        Text("Last Checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                    } else {
                        Text("Last Checked: never")
                            .font(.footnote)
                    }
                    if let lastInit = storage.getLastInit() {
                        Text("Last Init: \(lastInit.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                    } else {
                        Text("Last Init: never")
                            .font(.footnote)
                    }
                    if let lastTerminate = storage.getLastTerminate() {
                        Text("Last Term: \(lastTerminate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                    } else {
                        Text("Last Term: never")
                            .font(.footnote)
                    }
                    /*
                    Button {
                        if let url = URL(string: "https://littlebluebug.com/wallet/index.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Release notes")                            
                    }
                     */
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
                    Text("Version \(appVersion)")
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
