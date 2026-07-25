import Foundation
import SwiftUI
import SwiftData
import InAppSupport

/// Bridges LunchSync's SwiftData `Log` table to Help & Feedback: the composer's
/// "App log" attachment and the Logs browser reachable from the feedback home.
/// The package owns formatting, the diagnostic header, the size cap and gzip —
/// all this decides is which rows to hand it.
enum SupportLogs {
    /// Set from `LMPlaygroundApp.init()` right after `InAppSupport.configure`,
    /// so both entry points reuse the app's one container rather than standing
    /// up a second one.
    static var container: ModelContainer?

    /// How far back an attached log reaches.
    private static let window: TimeInterval = 30 * 24 * 60 * 60
    /// Backstop for a pathological table: the window alone doesn't bound row
    /// count, and this store is CloudKit-synced with the background extension
    /// writing to it too, so it grows while the app is closed.
    private static let maxRows = 20_000

    @MainActor
    static func attachment() async -> PendingAttachment? {
        guard let context = container?.mainContext else { return nil }

        // Windowing belongs in the query: fetching every row to then discard
        // most of them would materialize the whole table for a single tap.
        let cutoff = Date().addingTimeInterval(-window)
        var descriptor = FetchDescriptor<Log>(
            predicate: #Predicate<Log> { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = maxRows
        guard let rows = try? context.fetch(descriptor) else { return nil }

        return await SupportLogAttachment.make(
            lines: rows.map { log in
                // `level` is nesting depth here (1 = headline, 2+ = detail), not
                // severity, so it travels as a plain label rather than pretending
                // to be a status.
                SupportLogLine(date: log.date, label: "L\(log.level)", text: log.message)
            }
        )
    }

    @MainActor
    static func logsView() -> AnyView {
        guard let context = container?.mainContext else { return AnyView(EmptyView()) }
        let token = (try? Keychain().retrieveTokenFromKeychain()) ?? ""
        return AnyView(LogListView(wallet: Wallet(context: context, apiToken: token)))
    }
}
