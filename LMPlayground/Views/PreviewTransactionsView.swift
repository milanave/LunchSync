import SwiftUI

// Add this struct before PreviewTransactionsView
private struct MonthRow: View {
    let month: String
    let count: Int
    let isHighlighted: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Text(month)
            Spacer()
            Text("^[\(count) transaction](inflect: true)")
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark")
                .foregroundColor(isHighlighted ? .accentColor : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct PreviewTransactionsView: View {
    let transactions: [Transaction]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonth: String?
    let onImport: ([Transaction]) -> Void
    
    private let transactionsByMonth: [(String, Int)]
    
    init(transactions: [Transaction], onImport: @escaping ([Transaction]) -> Void) {
        self.transactions = transactions
        self.onImport = onImport
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        let grouped = Dictionary(grouping: transactions) { transaction in
            formatter.string(from: transaction.date)
        }
        
        let mapped = grouped.map { ($0.key, $0.value.count) }
        
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        
        self.transactionsByMonth = mapped.sorted { pair1, pair2 in
            let date1 = df.date(from: pair1.0)!
            let date2 = df.date(from: pair2.0)!
            return date1 > date2
        }
    }
    
    private var selectedTransactionCount: Int {
        guard let selectedMonth = selectedMonth,
              let selectedIndex = transactionsByMonth.firstIndex(where: { $0.0 == selectedMonth }) else {
            return 0
        }
        return transactionsByMonth[0...selectedIndex].reduce(0) { $0 + $1.1 }
    }
    
    private func shouldHighlight(month: String) -> Bool {
        guard let selectedMonth = selectedMonth else {
            return false
        }
        
        let selectedIndex = transactionsByMonth.firstIndex(where: { $0.0 == selectedMonth })
        guard let selectedMonthIndex = selectedIndex else {
            return false
        }
        
        let currentIndex = transactionsByMonth.firstIndex(where: { $0.0 == month })
        guard let monthIndex = currentIndex else {
            return false
        }
        
        return monthIndex <= selectedMonthIndex
    }
    
    private var selectedDateRange: String? {
        guard let selectedMonth = selectedMonth,
              let selectedIndex = transactionsByMonth.firstIndex(where: { $0.0 == selectedMonth }) else {
            return nil
        }
        
        let selectedMonths = transactionsByMonth[0...selectedIndex]
        if selectedMonths.count == 1 {
            return selectedMonths[0].0
        } else {
            return "\(selectedMonths.last?.0 ?? "") - \(selectedMonths.first?.0 ?? "")"
        }
    }
    
    private var selectedTransactions: [Transaction] {
        guard let _ = selectedMonth else { return [] }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        return transactions.filter { transaction in
            let transactionMonth = formatter.string(from: transaction.date)
            return shouldHighlight(month: transactionMonth)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                if selectedMonth != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Selected for import:")
                                Spacer()
                                Text("^[\(selectedTransactionCount) transaction](inflect: true)")
                                    .foregroundStyle(.secondary)
                            }
                            if let dateRange = selectedDateRange {
                                Text(dateRange)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    monthsList()
                } header: {
                    Text("Select Month to Import")
                } footer: {
                    Text("Transactions will be imported from the selected month and all more recent months")
                }
            }
            .navigationTitle("Preview Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if selectedMonth != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import") {
                            onImport(selectedTransactions)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func monthsList() -> some View {
        ForEach(transactionsByMonth, id: \.0) { month, count in
            MonthRow(
                month: month,
                count: count,
                isHighlighted: shouldHighlight(month: month),
                onTap: { selectedMonth = month }
            )
        }
    }
}

#Preview {
    // Create sample transactions for the last 3 months
    let calendar = Calendar.current
    let now = Date()
    
    let sampleTransactions = (0..<100).map { i -> Transaction in
        let randomDaysAgo = Int.random(in: 0...290)
        let date = calendar.date(byAdding: .day, value: -randomDaysAgo, to: now)!
        
        return Transaction(
            id: "\(i)",
            account: "Sample Account",
            payee: "Sample Payee \(i)",
            amount: Double.random(in: 10...1000),
            date: date,
            lm_id: "",
            lm_account: "",
            sync: .pending
        )
    }
    
    PreviewTransactionsView(transactions: sampleTransactions) { _ in }
} 
