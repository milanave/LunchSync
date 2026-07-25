import SwiftUI

// Shared list body used by the launch modal and the Settings browse screen.
struct AnnouncementListView: View {
    let announcements: [Announcement]

    var body: some View {
        List(announcements) { announcement in
            VStack(alignment: .leading, spacing: 6) {
                Text(announcement.title)
                    .font(.headline)
                Text(announcement.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(.init(announcement.body))
                    .font(.body)
            }
            .padding(.vertical, 4)
        }
    }
}

// Modal presentation shown at launch when there are unseen announcements.
struct AnnouncementsView: View {
    let announcements: [Announcement]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            AnnouncementListView(announcements: announcements)
                .navigationTitle("Announcements")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Got It") {
                            onDone()
                        }
                    }
                }
        }
    }
}

#Preview {
    AnnouncementsView(
        announcements: AnnouncementCatalog.all,
        onDone: {}
    )
}
