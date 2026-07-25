import Foundation

struct Announcement: Identifiable {
    let id: Int
    let date: String
    let title: String
    let body: String
}

enum AnnouncementCatalog {
    // Add new announcements at the top with the next higher id.
    // Body text supports basic markdown (bold, links, etc.).
    static let all: [Announcement] = [
        Announcement(
            id: 2,
            date: "2026-07-25",
            title: "API v2 and Problem Reporting",
            body: "LunchSync now defaults to LunchMoney API v2. You can change this in the settings if you are having issues. Also, LunchSync now has in-app problem reporting, tap the help icon in the upper right to report issues or make suggestions."
        ),
        Announcement(
            id: 1,
            date: "2026-07-25",
            title: "Announcements",
            body: "Lunch Sync will now let you know about important changes here when you open the app."
        ),
    ]

    static func recent(_ count: Int) -> [Announcement] {
        Array(all.sorted { $0.id > $1.id }.prefix(count))
    }
}

@MainActor
final class AnnouncementStore: ObservableObject {
    private static let seenKey = "seen_announcement_ids"
    private let defaults: UserDefaults

    @Published var unseen: [Announcement] = []

    init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? .standard) {
        self.defaults = defaults
    }

    private var seenIDs: Set<Int> {
        get { Set(defaults.array(forKey: Self.seenKey) as? [Int] ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Self.seenKey) }
    }

    /// Recomputes `unseen`. On a fresh install (no seen history and the user
    /// hasn't set up the app yet) everything is marked seen up front so the
    /// first launch isn't a backlog of old announcements.
    func checkForUnseen(freshInstall: Bool) {
        if freshInstall && defaults.object(forKey: Self.seenKey) == nil {
            seenIDs = Set(AnnouncementCatalog.all.map(\.id))
        }
        let seen = seenIDs
        unseen = AnnouncementCatalog.all
            .filter { !seen.contains($0.id) }
            .sorted { $0.id > $1.id }
    }

    func markUnseenAsRead() {
        seenIDs.formUnion(unseen.map(\.id))
        unseen = []
    }

    /// Marks announcements seen after browsing them (e.g. from Settings) so
    /// the launch popup doesn't re-show what the user just read.
    func markSeen(_ announcements: [Announcement]) {
        seenIDs.formUnion(announcements.map(\.id))
        let seen = seenIDs
        unseen.removeAll { seen.contains($0.id) }
    }
}
