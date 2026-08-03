//
//  MirrorSyncEngine.swift
//  LMPlayground
//
//  The full mirror pipeline, isolated from the host app's sync path: reads
//  FinanceKit directly (all accounts, the entire transaction history), diffs
//  against the mirror's own ledger (MirrorLedger), and POSTs what the server
//  hasn't acknowledged yet via MirrorAPI. Every failure is contained here —
//  callers get an Outcome, never a throw — so mirroring can never break the
//  Lunch Money sync.
//
import Foundation
import FinanceKit
import CryptoKit

struct MirrorSyncEngine {

    enum Outcome {
        case notConfigured
        /// Nothing was attempted (e.g. another process holds the run lock).
        case skipped(String)
        case success(sent: Int)
        case failure(sent: Int, error: Error)
    }

    /// Transactions per POST to the mirror server.
    private static let batchSize = 500
    /// Transactions per FinanceKit query page when walking the full history.
    private static let pageSize = 1000

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // Same detection AppleWallet uses: the background extension inherits the
    // main app's FinanceKit authorization, so it only checks data availability
    // instead of re-requesting authorization (which needs UI).
    private static var isBackgroundExtension: Bool {
        Bundle.main.bundleIdentifier?.contains("BackgroundHandler") == true
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Runs a full mirror pass when a mirror URL is configured. Never throws;
    /// `log` receives progress/diagnostic lines (SyncBroker pipes them into
    /// its log store).
    static func runIfConfigured(log: (String) -> Void = { print("MirrorSyncEngine: \($0)") }) async -> Outcome {
        guard let baseURL = MirrorAPI.configuredBaseURL() else {
            return .notConfigured
        }

        // Advisory cross-process lock: the app and the background extension
        // can run at the same time, and both would open the same ledger
        // store. If another engine run holds the lock, skip this one.
        let lock: RunLock?
        switch RunLock.acquire() {
        case .busy:
            log("mirror: already running in another process, skipping this run")
            return .skipped("mirror already running")
        case .unavailable:
            log("mirror: run lock unavailable, continuing without it")
            lock = nil
        case .acquired(let acquired):
            lock = acquired
        }
        defer { lock?.release() }

        // Graceful failure: no ledger, no mirror run (a run without dedupe
        // bookkeeping would re-send the whole history every time).
        guard let ledger = MirrorLedger.open() else {
            log("mirror: ledger store unavailable, skipping this run")
            return .failure(sent: 0, error: NSError(
                domain: "MirrorSyncEngine", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Mirror ledger store could not be opened"]
            ))
        }

        do {
            // FinanceKit availability/authorization, following AppleWallet's
            // pattern: FinanceKit traps (rather than throws) when its store
            // can't be opened, so bail out before querying.
            if !isSimulator {
                guard FinanceStore.isDataAvailable(.financialData) else {
                    throw NSError(domain: "MirrorSyncEngine", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "FinanceKit data not available"
                    ])
                }
                if !isBackgroundExtension {
                    let status = try await FinanceStore.shared.requestAuthorization()
                    guard status == .authorized else {
                        throw NSError(domain: "MirrorSyncEngine", code: -4, userInfo: [
                            NSLocalizedDescriptionKey: "FinanceKit not authorized (\(status))"
                        ])
                    }
                }
            }

            // ALL accounts with current balances — accounts ride along on
            // every packet so the server can always reconcile names/balances.
            let (mirrorAccounts, accountInfoById) = try await fetchAccounts(log: log)

            // The ENTIRE FinanceKit history, oldest first.
            let history = try await fetchFullHistory(log: log)
            log("mirror: \(mirrorAccounts.count) accounts, \(history.count) transactions in FinanceKit history")

            var entries: [(id: String, hash: String, packet: MirrorTransaction)] = []
            entries.reserveCapacity(history.count)
            for txn in history {
                let (packet, hash) = packetEntry(for: txn, info: accountInfoById[txn.accountID])
                entries.append((id: packet.id, hash: hash, packet: packet))
            }

            var existing = try ledger.recordsById()
            // Send anything the ledger has never seen, or whose content
            // (amount, date, status, description, merchant fields) changed
            // since the server last acknowledged it.
            let toSend = entries.filter { existing[$0.id]?.contentHash != $0.hash }
            log("mirror: \(toSend.count) of \(entries.count) transactions need sending (\(existing.count) already acknowledged)")

            let api = MirrorAPI(baseURL: baseURL)

            // Nothing new: still send one accounts-only packet so the server
            // gets fresh balances on every sync.
            if toSend.isEmpty {
                try await api.sync(packet: MirrorPacket(
                    schemaVersion: 1, accounts: mirrorAccounts, transactions: []
                ))
                log("mirror: up to date, sent accounts-only packet")
                return .success(sent: 0)
            }

            var sent = 0
            var start = 0
            while start < toSend.count {
                let batch = Array(toSend[start ..< min(start + batchSize, toSend.count)])
                start += batch.count
                do {
                    try await api.sync(packet: MirrorPacket(
                        schemaVersion: 1,
                        accounts: mirrorAccounts,
                        transactions: batch.map(\.packet)
                    ))
                } catch {
                    // Stop on first failure; everything unacknowledged is
                    // retried on the next run.
                    log("mirror: batch failed after \(sent) sent: \(error.localizedDescription)")
                    return .failure(sent: sent, error: error)
                }
                do {
                    try ledger.acknowledge(batch.map { ($0.id, $0.hash) }, existing: &existing, at: Date())
                } catch {
                    // The server did ack this batch; a lost upsert only means
                    // a harmless resend next run (the server upserts too).
                    log("mirror: ledger save failed (batch will be resent next run): \(error.localizedDescription)")
                }
                sent += batch.count
                log("mirror: sent \(sent)/\(toSend.count)")
            }
            return .success(sent: sent)
        } catch {
            log("mirror: run failed: \(error.localizedDescription)")
            return .failure(sent: 0, error: error)
        }
    }

    // MARK: - FinanceKit fetches

    private struct AccountInfo {
        let displayName: String
        let institutionName: String
    }

    /// All FinanceKit accounts plus their latest balances, using the same
    /// query/balance-selection logic as AppleWallet.getWalletAccounts (without
    /// dropping accounts whose balance lookup fails).
    private static func fetchAccounts(log: (String) -> Void) async throws -> ([MirrorAccount], [UUID: AccountInfo]) {
        let query = AccountQuery(
            sortDescriptors: [SortDescriptor(\FinanceKit.Account.displayName)],
            predicate: nil
        )
        let accounts = try await FinanceStore.shared.accounts(query: query)

        var mirrorAccounts: [MirrorAccount] = []
        var infoById: [UUID: AccountInfo] = [:]
        for acct in accounts {
            var balance = 0.0
            var currency = "USD"
            do {
                let latest = try await latestBalance(accountId: acct.id)
                var amount: CurrencyAmount?
                switch latest.currentBalance {
                case .availableAndBooked(let available, let booked):
                    amount = (available.creditDebitIndicator == .credit) ? booked.amount : available.amount
                case .available(let available):
                    amount = available.amount
                case .booked(let booked):
                    amount = booked.amount
                @unknown default:
                    log("mirror: unknown balance type for \(acct.displayName)")
                }
                if let amount {
                    balance = NSDecimalNumber(decimal: amount.amount).doubleValue
                    currency = amount.currencyCode
                }
            } catch {
                log("mirror: no balance for \(acct.displayName): \(error.localizedDescription)")
            }
            mirrorAccounts.append(MirrorAccount(
                id: acct.id.uuidString,
                name: acct.displayName,
                institution: acct.institutionName,
                balance: balance,
                currency: currency
            ))
            infoById[acct.id] = AccountInfo(
                displayName: acct.displayName,
                institutionName: acct.institutionName
            )
        }
        return (mirrorAccounts, infoById)
    }

    private static func latestBalance(accountId: UUID) async throws -> AccountBalance {
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let query = AccountBalanceQuery(
            sortDescriptors: [],
            predicate: AccountBalanceQuery.predicate(bookedSince: startDate),
            limit: 100,
            offset: 0
        )
        let balances = try await FinanceStore.shared.accountBalances(query: query)
            .filter { $0.accountID == accountId }
        guard let latest = balances.max(by: { balanceAsOfDate($0) < balanceAsOfDate($1) }) else {
            throw NSError(domain: "MirrorSyncEngine", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "No balance found"
            ])
        }
        return latest
    }

    private static func balanceAsOfDate(_ balance: AccountBalance) -> Date {
        switch balance.currentBalance {
        case .availableAndBooked(_, let booked):    return booked.asOfDate
        case .available(let available):             return available.asOfDate
        case .booked(let booked):                   return booked.asOfDate
        @unknown default:                           return Date.distantPast
        }
    }

    /// The whole transaction history: no date predicate, date ascending,
    /// paginated through TransactionQuery's limit/offset (1000 per page).
    private static func fetchFullHistory(log: (String) -> Void) async throws -> [FinanceKit.Transaction] {
        // Secondary sort on id keeps the ordering stable when many rows share
        // a timestamp, so page boundaries can't shuffle between executions.
        let sortDescriptors = [
            SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .forward),
            SortDescriptor(\FinanceKit.Transaction.id, order: .forward)
        ]
        var fetched: [FinanceKit.Transaction] = []
        var offset = 0
        while true {
            let query = TransactionQuery(
                sortDescriptors: sortDescriptors,
                predicate: nil,
                limit: pageSize,
                offset: offset
            )
            let page = try await FinanceStore.shared.transactions(query: query)
            // Loop until an EMPTY page: FinanceKit doesn't guarantee full
            // pages, so a short page isn't proof the history is exhausted.
            if page.isEmpty { break }
            fetched.append(contentsOf: page)
            offset += page.count
            log("mirror: fetched \(fetched.count) transactions so far…")
        }
        // Belt and braces: each page is a separate query execution, so ties
        // straddling a boundary could still repeat; keep the first occurrence
        // of each id.
        var seen = Set<UUID>()
        var deduped: [FinanceKit.Transaction] = []
        deduped.reserveCapacity(fetched.count)
        for txn in fetched where seen.insert(txn.id).inserted {
            deduped.append(txn)
        }
        if deduped.count != fetched.count {
            log("mirror: dropped \(fetched.count - deduped.count) duplicate rows across pages")
        }
        return deduped
    }

    // MARK: - Mapping & hashing

    /// Maps one FinanceKit transaction to a packet entry the way AppleWallet
    /// does for the Lunch Money path (sign flip for credits, posted/pending
    /// from `.booked`, payee from transactionDescription), plus the stable
    /// content hash used for change detection.
    private static func packetEntry(for txn: FinanceKit.Transaction, info: AccountInfo?) -> (MirrorTransaction, String) {
        var amount = NSDecimalNumber(decimal: txn.transactionAmount.amount).doubleValue
        if txn.creditDebitIndicator == .credit {
            amount = amount * -1
        }
        let status = txn.status == .booked ? "posted" : "pending"

        // MCC description intentionally omitted: it needs AppleWallet's MCC
        // table and the raw code already travels in the metadata.
        let metadata = WalletMetadata(
            from: txn,
            accountDisplayName: info?.displayName,
            institutionName: info?.institutionName
        )
        let wallet = metadata.wallet

        let packet = MirrorTransaction(
            id: txn.id.uuidString,
            accountId: txn.accountID.uuidString,
            date: isoFormatter.string(from: txn.transactionDate),
            amount: amount,
            currency: txn.transactionAmount.currencyCode,
            payee: txn.transactionDescription,
            status: status,
            notes: txn.status == .booked ? "booked" : "pending",
            category: wallet.merchantCategoryCode ?? "",
            metadata: metadata
        )

        // SHA256 over a canonical string of the change-relevant packet fields
        // — deliberately not Hasher/hashValue, whose seed is randomized per
        // process. Any correction that alters what the packet carries
        // (amount, dates, status, type, descriptions, merchant fields,
        // foreign amount/rate, or a move to another account) changes the hash
        // and re-queues the row. nil is encoded distinctly from empty string.
        let nilMarker = "\u{1}nil"
        let canonical = [
            wallet.accountId,
            wallet.amount.value,
            wallet.amount.currency,
            wallet.creditDebitIndicator,
            wallet.transactionDate,
            wallet.postedDate ?? nilMarker,
            status,
            wallet.transactionType,
            wallet.transactionDescription,
            wallet.originalTransactionDescription ?? nilMarker,
            wallet.merchantName ?? nilMarker,
            wallet.merchantCategoryCode ?? nilMarker,
            wallet.foreignAmount?.value ?? nilMarker,
            wallet.foreignAmount?.currency ?? nilMarker,
            wallet.foreignExchangeRate ?? nilMarker
        ].joined(separator: "|")
        let hash = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return (packet, hash)
    }

    // MARK: - Cross-process run lock

    /// Advisory lock (flock on a file in the app-group container) held for a
    /// whole engine run, so the app and the background extension never work
    /// the same ledger store concurrently. Non-blocking: a contended lock
    /// means another run is in flight and this one just skips.
    private final class RunLock {
        enum Acquisition {
            case acquired(RunLock)
            case busy
            case unavailable
        }

        private let fileDescriptor: Int32

        private init(fileDescriptor: Int32) {
            self.fileDescriptor = fileDescriptor
        }

        static func acquire() -> Acquisition {
            guard let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: MirrorLedger.appGroupIdentifier
            ) else {
                return .unavailable
            }
            let lockURL = groupURL.appendingPathComponent("mirror.lock")
            let fd = open(lockURL.path, O_CREAT | O_WRONLY, 0o644)
            guard fd >= 0 else {
                return .unavailable
            }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                return .busy
            }
            return .acquired(RunLock(fileDescriptor: fd))
        }

        func release() {
            flock(fileDescriptor, LOCK_UN)
            close(fileDescriptor)
        }
    }
}
