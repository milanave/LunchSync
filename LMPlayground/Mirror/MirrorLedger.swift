//
//  MirrorLedger.swift
//  LMPlayground
//
//  The mirror pipeline's own persistence: which FinanceKit transactions the
//  mirror server has acknowledged, and with what content. Lives in its own
//  SwiftData container ("mirror.store" in the app-group container) so it is
//  fully separate from the app's Transaction/Account store — it is NOT part
//  of the schema in either Persistence.swift, and both the app and the
//  background extension construct it on demand.
//
import Foundation
import SwiftData

/// One acknowledged FinanceKit transaction: `id` is the FinanceKit
/// transaction UUID string, `contentHash` a stable digest of the fields the
/// packet carries (so a pending→posted flip or amount correction re-queues
/// the row), `mirroredAt` when the server last 2xx'd it.
@Model
final class MirrorRecord {
    @Attribute(.unique) var id: String = ""
    var contentHash: String = ""
    var mirroredAt: Date = Date()

    init(id: String, contentHash: String, mirroredAt: Date) {
        self.id = id
        self.contentHash = contentHash
        self.mirroredAt = mirroredAt
    }
}

/// Thin wrapper around the mirror's private ModelContainer/context.
struct MirrorLedger {
    static let appGroupIdentifier = "group.com.littlebluebug.AppleCardSync"
    static let storeFileName = "mirror.store"

    let context: ModelContext

    /// Opens (creating on first use) the ledger store in the app-group
    /// container. Returns nil — mirror skips this run — when the app group
    /// or container can't be opened; never throws into the sync path.
    static func open() -> MirrorLedger? {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            print("MirrorLedger: app group container unavailable")
            return nil
        }
        let storeURL = groupURL.appendingPathComponent(storeFileName)
        do {
            let schema = Schema([MirrorRecord.self])
            // .none: this bookkeeping store is local-only; CloudKit would
            // also reject the unique constraint on `id`.
            let configuration = ModelConfiguration("MirrorLedger", schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return MirrorLedger(context: ModelContext(container))
        } catch {
            print("MirrorLedger: failed to open store: \(error)")
            return nil
        }
    }

    /// All acknowledged records, keyed by FinanceKit transaction id.
    func recordsById() throws -> [String: MirrorRecord] {
        let records = try context.fetch(FetchDescriptor<MirrorRecord>())
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Upserts an acknowledged batch and saves. Throws on save failure so
    /// the caller can log it (the server did ack; a lost upsert only means
    /// a harmless resend, since the server upserts too).
    func acknowledge(_ entries: [(id: String, contentHash: String)], existing: [String: MirrorRecord], at date: Date) throws {
        for entry in entries {
            if let record = existing[entry.id] {
                record.contentHash = entry.contentHash
                record.mirroredAt = date
            } else {
                context.insert(MirrorRecord(id: entry.id, contentHash: entry.contentHash, mirroredAt: date))
            }
        }
        try context.save()
    }
}
