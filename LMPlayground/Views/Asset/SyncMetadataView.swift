//
//  SyncMetadataView.swift
//  LMPlayground
//
//  Backfill `custom_metadata` on already-synced transactions for a given
//  account. Mirrors the month-range picker UX from PreviewTransactionsView.
//

import SwiftUI
import SwiftData

struct SyncMetadataView: View {
    let account: Account
    let wallet: Wallet

    @Environment(\.modelContext) private var modelContext

    // Snapshot loaded once in `.task` and cached in @State. We deliberately
    // avoid `@Query` here: this view doesn't need live updates, and SwiftData
    // predicates over large transaction stores combined with re-computing
    // groupings on every body re-eval was freezing the UI on tap.
    @State private var allLinkedTransactions: [Transaction] = []
    @State private var transactionsByMonth: [MonthBucket] = []
    @State private var selectedMonth: String?
    @State private var selectedTransactions: [Transaction] = []
    @State private var isLoading = true

    private struct MonthBucket: Identifiable {
        let id: String        // "MMMM yyyy"
        let count: Int
        let date: Date        // first-of-month, for sort comparisons
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private func shouldHighlight(_ month: String) -> Bool {
        guard
            let selectedMonth,
            let selectedIndex = transactionsByMonth.firstIndex(where: { $0.id == selectedMonth }),
            let monthIndex = transactionsByMonth.firstIndex(where: { $0.id == month })
        else { return false }
        return monthIndex <= selectedIndex
    }

    private var selectedDateRange: String? {
        guard
            let selectedMonth,
            let selectedIndex = transactionsByMonth.firstIndex(where: { $0.id == selectedMonth })
        else { return nil }
        let slice = transactionsByMonth[0...selectedIndex]
        if slice.count == 1 { return slice.first?.id }
        return "\(slice.last?.id ?? "") – \(slice.first?.id ?? "")"
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading transactions…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if allLinkedTransactions.isEmpty {
                Section {
                    Text("No synced transactions for this account yet. Once transactions are synced to Lunch Money, you can backfill their metadata here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if selectedMonth != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Selected for sync:")
                                Spacer()
                                Text("^[\(selectedTransactions.count) transaction](inflect: true)")
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
                    ForEach(transactionsByMonth) { bucket in
                        MonthRow(
                            month: bucket.id,
                            count: bucket.count,
                            isHighlighted: shouldHighlight(bucket.id),
                            onTap: { selectedMonth = bucket.id }
                        )
                    }
                } header: {
                    Text("Select month to sync")
                } footer: {
                    Text("Metadata will be re-captured from Apple Wallet and pushed to Lunch Money for the selected month and all more recent months.")
                }
            }
        }
        .navigationTitle("Sync Metadata")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedTransactions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SyncMetadataProgressView(
                            transactions: selectedTransactions,
                            account: account,
                            wallet: wallet
                        )
                    } label: {
                        Text("Sync").bold()
                    }
                }
            }
        }
        .task { await loadTransactions() }
        .onChange(of: selectedMonth) { _, _ in
            recomputeSelected()
        }
    }

    // MARK: - Loading + selection

    @MainActor
    private func loadTransactions() async {
        // SwiftData's `ModelContext` is main-actor-bound, so the fetch has
        // to happen here. The grouping is pure Swift but cheap, so we keep
        // it inline — the perf win we need is doing this once via `.task`
        // rather than every body re-evaluation.
        let accountId = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { $0.accountID == accountId }
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        // Filter in Swift rather than the predicate to dodge SwiftData's
        // historical quirks with `!= ""` over String.
        let linked = all
            .filter { !$0.lm_id.isEmpty }
            .sorted { $0.date > $1.date }

        let cal = Calendar.current
        var counts: [String: (count: Int, date: Date)] = [:]
        for txn in linked {
            let key = Self.monthFormatter.string(from: txn.date)
            if let existing = counts[key] {
                counts[key] = (existing.count + 1, existing.date)
            } else {
                let comps = cal.dateComponents([.year, .month], from: txn.date)
                let firstOfMonth = cal.date(from: comps) ?? txn.date
                counts[key] = (1, firstOfMonth)
            }
        }
        let buckets = counts
            .map { MonthBucket(id: $0.key, count: $0.value.count, date: $0.value.date) }
            .sorted { $0.date > $1.date }

        self.allLinkedTransactions = linked
        self.transactionsByMonth = buckets
        self.isLoading = false
    }

    private func recomputeSelected() {
        guard
            let selectedMonth,
            let selectedIndex = transactionsByMonth.firstIndex(where: { $0.id == selectedMonth })
        else {
            selectedTransactions = []
            return
        }
        let cutoff = transactionsByMonth[selectedIndex].date
        // Include this month onward (i.e. transactions on or after the
        // first-of-selected-month). Newer months are already sorted above.
        selectedTransactions = allLinkedTransactions.filter { $0.date >= cutoff }
    }
}

/// Single month row — same shape as the one in `PreviewTransactionsView`,
/// duplicated here so the two flows can evolve independently.
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Transaction.self,
        Account.self,
        Log.self,
        Item.self,
        LMCategory.self,
        TrnCategory.self,
        TransactionHistory.self
    ])
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    let wallet = MockWallet(context: context, apiToken: "preview-token")
    let account = Account(
        id: "acc_123",
        name: "Apple Card",
        balance: 1234.56,
        lm_id: "456",
        lm_name: "LM Apple Card",
        available: 0,
        currency: "USD",
        institution_name: "Goldman Sachs",
        institution_id: "gs_001"
    )
    context.insert(account)

    let calendar = Calendar.current
    for i in 0..<60 {
        let daysAgo = Int.random(in: 0...150)
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let txn = Transaction(
            id: "txn_\(i)",
            account: "Apple Card",
            payee: "Sample Merchant \(i)",
            amount: Double.random(in: 5...200),
            date: date,
            lm_id: "9999\(i)",
            lm_account: "456",
            accountID: account.id,
            sync: .complete
        )
        context.insert(txn)
    }

    return NavigationStack {
        SyncMetadataView(account: account, wallet: wallet)
    }
    .modelContainer(container)
}
