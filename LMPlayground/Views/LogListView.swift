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
    
    private func parseLogMessage(_ message: String) -> (cleanMessage: String, sourceLabel: String?, labelColor: Color) {
        if message.hasPrefix("MV:") {
            let cleanMessage = String(message.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Manual", .blue)
        } else if message.hasPrefix("BN:") {
            let cleanMessage = String(message.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Background Notice", .orange)
        } else if message.hasPrefix("BGD:") {
            let cleanMessage = String(message.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Background Delivery", .green)
        } else {
            return (message, nil, .clear)
        }
    }
    
    private var diagnosticEmailContent: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        // First get the logs formatted (last 100 entries only)
        let logsContent = logs.prefix(100).map { log in
            "[\(dateFormatter.string(from: log.date))] \(log.message)"
        }.joined(separator: "\n")
        
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
                let (cleanMessage, sourceLabel, labelColor) = parseLogMessage(log.message)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.date.formatted(.dateTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if let label = sourceLabel {
                            Text(label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(labelColor.opacity(0.1))
                                .foregroundColor(labelColor)
                                .cornerRadius(4)
                        }
                    }
                    Text(cleanMessage)
                }
                .padding(.leading, CGFloat(max(0, log.level - 1)) * 15)
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
    
    // Create sample logs with different levels and dates
    let sampleLogs = [
        Log(date: Date().addingTimeInterval(-3600), message: "BGD: Successfully synced 5 transactions", level: 1),
        Log(date: Date().addingTimeInterval(-7200), message: "MV: API request completed", level: 2),
        Log(date: Date().addingTimeInterval(-10800), message: "BN: Started background sync", level: 1),
        Log(date: Date().addingTimeInterval(-14400), message: "BGD: Validating transaction data", level: 2),
        Log(date: Date().addingTimeInterval(-18000), message: "MV: Error: Network timeout occurred", level: 1),
        Log(date: Date().addingTimeInterval(-21600), message: "BN: Debug: Processing account ID 12345", level: 3),
        Log(date: Date().addingTimeInterval(-25200), message: "MV: Wallet initialized successfully", level: 1),
        Log(date: Date().addingTimeInterval(-28800), message: "BN: Debug: Memory usage at 45MB", level: 3),
        Log(date: Date().addingTimeInterval(-21600), message: "BN: Debug: Processing account ID 12345", level: 3),
        Log(date: Date().addingTimeInterval(-25200), message: "MV: Wallet initialized successfully", level: 1),
        Log(date: Date().addingTimeInterval(-28800), message: "BN: Debug: Memory usage at 45MB", level: 3),
    ]
    
    // Insert sample logs into the context
    for log in sampleLogs {
        context.insert(log)
    }
    
    return NavigationStack {
        LogListView(wallet: wallet)
    }
    .modelContainer(container)
} 
