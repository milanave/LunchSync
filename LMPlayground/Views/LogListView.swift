import SwiftUI
import SwiftData
import MessageUI

struct LogListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.date, order: .reverse) private var logs: [Log]
    @State private var searchText = ""
    @AppStorage("detailedLogging") private var detailedLogging = false
    @State private var showAllLogs = false
    @State private var sourceFilter: LogSourceFilter = .all
    let wallet: Wallet
    
    @AppStorage("enableBackgroundDelivery", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var enableBackgroundDelivery = false
    private let storage = Storage()
    
    private var filteredLogs: [Log] {
        let levelFiltered = showAllLogs ? logs : logs.filter { $0.level == 1 }

        let typeFiltered: [Log]
        switch sourceFilter {
        case .all:
            typeFiltered = levelFiltered
        case .manual, .backgroundNotice, .shortcut, .backgroundDelivery:
            typeFiltered = levelFiltered.filter { log in
                sourceType(for: log.message) == sourceFilter
            }
        }

        if searchText.isEmpty {
            return typeFiltered
        }
        return typeFiltered.filter { log in
            log.message.localizedCaseInsensitiveContains(searchText)
        }
    }

    enum LogSourceFilter: String, CaseIterable, Identifiable, Hashable {
        case all
        case manual
        case backgroundNotice
        case shortcut
        case backgroundDelivery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .manual: return "Manual"
            case .backgroundNotice: return "Background Notice"
            case .shortcut: return "Shortcut"
            case .backgroundDelivery: return "Background Delivery"
            }
        }
    }

    private func sourceType(for message: String) -> LogSourceFilter? {
        if message.hasPrefix("MV:") { return .manual }
        if message.hasPrefix("BN:") { return .backgroundNotice }
        if message.hasPrefix("SC:") { return .shortcut }
        if message.hasPrefix("BGD:") { return .backgroundDelivery }
        return nil
    }
    
    private func parseLogMessage(_ message: String) -> (cleanMessage: String, sourceLabel: String?, labelColor: Color) {
        if message.hasPrefix("MV:") {
            let cleanMessage = String(message.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Manual", .blue)
        } else if message.hasPrefix("BN:") {
            let cleanMessage = String(message.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Background Notice", .orange)
        } else if message.hasPrefix("SC:") {
            let cleanMessage = String(message.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return (cleanMessage, "Shortcut", .red)
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
            
            if sourceFilter == .backgroundDelivery{
                backgroundDeliveryDebugInfo()
            }
            
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
            // Filter button
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Log Type", selection: $sourceFilter) {
                        ForEach(LogSourceFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAllLogs.toggle()
                    } label: {
                        Label(showAllLogs ? "Hide Debug Logs" : "Show All Logs", systemImage: showAllLogs ? "list.bullet.rectangle" : "list.dash.header.rectangle")
                    }

                    ShareLink(
                        item: diagnosticEmailContent,
                        subject: Text("Wallet sync diagnostic data"),
                        message: Text("")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        wallet.clearLogs()
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        
    }
    private func backgroundDeliveryDebugInfo() -> some View {
        
        VStack{
            Text("Background Delivery is \(enableBackgroundDelivery ? "enabled":"disabled")")
                .frame(maxWidth: .infinity, alignment: .leading)
            if let lastInit = storage.getLastInit() {
                Text("Last Initialized: \(lastInit.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Last Initialized: never")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let last = storage.getLastCheck() {
                Text("Last Data received: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Last Data received: never")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Last sync count: \(niceNumber(NSDecimalNumber(decimal: storage.getWeeklySpending()).doubleValue))")
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let lastTerminate = storage.getLastTerminate() {
                Text("Last Terminated: \(lastTerminate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Last Terminated: never")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let lastError = storage.getLastError() {
                Text("Last Error: \(lastError.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Last Error: never")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        Log(date: Date().addingTimeInterval(-28800), message: "SC: Debug: Memory usage at 45MB", level: 1),
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
