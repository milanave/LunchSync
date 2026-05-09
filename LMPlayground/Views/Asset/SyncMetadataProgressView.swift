//
//  SyncMetadataProgressView.swift
//  LMPlayground
//
//  Two-phase progress UI for the metadata-backfill flow:
//   1. Fetch FinanceKit transactions and capture metadata onto local rows
//   2. Push the freshly-captured metadata to Lunch Money
//

import SwiftUI
import SwiftData

struct SyncMetadataProgressView: View {
    let transactions: [Transaction]
    let account: Account
    let wallet: Wallet

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var fetchState: StepState = .pending
    @State private var captureState: StepState = .pending
    @State private var pushState: StepState = .pending
    @State private var captureCurrent: Int = 0
    @State private var captureTotal: Int = 0
    @State private var pushCurrent: Int = 0
    @State private var pushTotal: Int = 0
    @State private var currentDetail: String?
    @State private var matched: Int = 0
    @State private var pushed: Int = 0
    @State private var failed: Int = 0
    @State private var errorMessage: String?
    @State private var didStart = false
    @State private var isRunning = false

    enum StepState {
        case pending, running, done, error
    }

    private var allDone: Bool {
        fetchState == .done && captureState == .done && (pushState == .done || pushTotal == 0)
            || fetchState == .error || captureState == .error || pushState == .error
    }

    var body: some View {
        List {
            Section {
                StepRow(
                    title: "Fetch wallet transactions",
                    state: fetchState,
                    detail: fetchState == .running ? "Querying Apple Wallet…" : nil,
                    progressCurrent: nil,
                    progressTotal: nil
                )
                StepRow(
                    title: "Capture metadata locally",
                    state: captureState,
                    detail: captureState == .running ? currentDetail : nil,
                    progressCurrent: captureCurrent,
                    progressTotal: captureTotal
                )
                StepRow(
                    title: "Push to Lunch Money",
                    state: pushState,
                    detail: pushState == .running ? currentDetail : nil,
                    progressCurrent: pushCurrent,
                    progressTotal: pushTotal
                )
            } header: {
                Text("Steps")
            }

            if allDone || isRunning {
                Section {
                    SummaryRow(label: "Selected", value: "\(transactions.count)")
                    SummaryRow(label: "Matched in Wallet", value: "\(matched)")
                    SummaryRow(label: "Pushed to Lunch Money", value: "\(pushed)")
                    if failed > 0 {
                        SummaryRow(label: "Failed", value: "\(failed)")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Summary")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                } header: {
                    Text("Error")
                }
            }
        }
        .navigationTitle("Syncing Metadata")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isRunning)
        .toolbar {
            if allDone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
        .task {
            // Guard against duplicate runs if the view body re-fires.
            guard !didStart else { return }
            didStart = true
            await runSync()
        }
    }

    @MainActor
    private func runSync() async {
        isRunning = true
        defer { isRunning = false }

        let broker = SyncBroker(context: modelContext, logPrefix: "SM")
        captureTotal = transactions.count
        fetchState = .running

        do {
            let result = try await broker.syncMetadata(
                transactions: transactions,
                account: account
            ) { progress in
                Task { @MainActor in
                    apply(progress)
                }
            }
            // Final state — apply on the main actor for consistency.
            matched = result.matched
            pushed = result.pushed
            failed = result.failed

            if fetchState != .error { fetchState = .done }
            if captureState != .error { captureState = .done }
            captureCurrent = captureTotal

            if pushTotal == 0 {
                pushState = .done
            } else if failed == 0 {
                pushState = .done
            } else if pushed > 0 {
                // Partial success
                pushState = .done
            } else {
                pushState = .error
            }
        } catch {
            errorMessage = error.localizedDescription
            if fetchState == .running { fetchState = .error }
            else if captureState == .running { captureState = .error }
            else { pushState = .error }
        }
    }

    @MainActor
    private func apply(_ p: SyncBroker.SyncMetadataProgress) {
        matched = p.matched
        pushed = p.pushed
        failed = p.failed
        currentDetail = p.detail

        switch p.step {
        case .fetching:
            fetchState = .running
        case .capturing:
            // Once we're capturing, the fetch step is done.
            if fetchState != .error { fetchState = .done }
            captureState = .running
            captureCurrent = p.current
            captureTotal = p.total
        case .pushing:
            if captureState != .error { captureState = .done }
            captureCurrent = captureTotal
            pushState = p.total == 0 ? .done : .running
            pushCurrent = p.current
            pushTotal = p.total
        case .done:
            pushState = pushState == .error ? .error : .done
            currentDetail = nil
        }
    }
}

// MARK: - Row helpers

private struct StepRow: View {
    let title: String
    let state: SyncMetadataProgressView.StepState
    let detail: String?
    let progressCurrent: Int?
    let progressTotal: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                icon
                    .frame(width: 22, height: 22)
                Text(title)
                Spacer()
                if let progressCurrent, let progressTotal, progressTotal > 0 {
                    Text("\(progressCurrent)/\(progressTotal)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 34)
            }
            if state == .running, let progressCurrent, let progressTotal, progressTotal > 0 {
                ProgressView(value: Double(progressCurrent), total: Double(progressTotal))
                    .padding(.leading, 34)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
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

    return NavigationStack {
        SyncMetadataProgressView(transactions: [], account: account, wallet: wallet)
    }
    .modelContainer(container)
}
