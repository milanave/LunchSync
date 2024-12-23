import SwiftUI
import SwiftData
import MessageUI

struct LogListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.date, order: .reverse) private var logs: [Log]
    @State private var searchText = ""
    @AppStorage("detailedLogging") private var detailedLogging = false
    @State private var showAllLogs = false
    let wallet: Wallet
    
    private var filteredLogs: [Log] {
        let levelFiltered = showAllLogs ? logs : logs.filter { $0.level == 1 }
        
        if searchText.isEmpty {
            return levelFiltered
        }
        return levelFiltered.filter { log in
            log.message.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var diagnosticEmailContent: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // First get the logs formatted
        let logsContent = logs.map { log in
            "[\(dateFormatter.string(from: log.date))] \(log.message)"
        }.joined(separator: "\n")
        
        // Get and format transactions
        let transactions = wallet.getTransactionsWithStatus([.complete, .never])
        let transactionsContent = transactions.map { transaction in
            """
            Transaction ID: \(transaction.id)
            Account: \(transaction.account)
            Account ID: \(transaction.accountID)
            Payee: \(transaction.payee)
            Amount: \(transaction.amount)
            Date: \(dateFormatter.string(from: transaction.date))
            LM ID: \(transaction.lm_id)
            LM Account: \(transaction.lm_account)
            Notes: \(transaction.notes)
            Category: \(transaction.category)
            Type: \(transaction.type)
            Status: \(transaction.status)
            Is Pending: \(transaction.isPending)
            Sync Status: \(transaction.syncStatus)
            """
        }.joined(separator: "\n\n")
        
        // Combine both sections
        return """
        === LOGS ===
        \(logsContent)
        
        === TRANSACTIONS ===
        \(transactionsContent)
        """
    }
    
    var body: some View {
        List {
            //Toggle("Detailed Logs", isOn: $detailedLogging)
            //   .toggleStyle(.switch)
            
            ForEach(filteredLogs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.date.formatted(.dateTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(log.message)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search logs")
        .navigationTitle("Activity Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAllLogs.toggle()
                } label: {
                    HStack {
                        Image(systemName: showAllLogs ? "list.bullet.rectangle" : "list.dash.header.rectangle")
                        Text("All")
                    }
                    .foregroundColor(showAllLogs ? .blue : .gray)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: diagnosticEmailContent,
                    subject: Text("Wallet sync diagnostic data"),
                    message: Text(""),
                    label: {
                        HStack{
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                    }
                )
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    wallet.clearLogs()
                } label: {
                    HStack{
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Log.self)
    let context = container.mainContext
    
    // Create sample wallet and logs
    let wallet = MockWallet(context: context, apiToken: "mock-token")
    
    
    NavigationStack {
        LogListView(wallet: wallet)
    }
    .modelContainer(container)
} 
