//
//  APIVersionView.swift
//  LMPlayground
//
//  Lets the user choose which Lunch Money API version syncs use. v1 is the
//  stable default; v2 is Lunch Money's next-generation API, currently in
//  alpha. Both versions use the same API token and operate on the same data
//  and ids, so switching back and forth is safe at any time.
//

import SwiftUI

struct APIVersionView: View {
    @AppStorage(LMAPIVersion.defaultsKey, store: UserDefaults(suiteName: LMAPIVersion.appGroupSuiteName))
    private var apiVersionRaw = LMAPIVersion.v1.rawValue

    private var selectedVersion: LMAPIVersion {
        LMAPIVersion(rawValue: apiVersionRaw) ?? .v1
    }

    var body: some View {
        List {
            Section {
                Picker("API Version", selection: $apiVersionRaw) {
                    ForEach(LMAPIVersion.allCases) { version in
                        Text(version.displayName).tag(version.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Lunch Money API")
            } footer: {
                Text("Both versions use the same API token and work on the same transactions, accounts, and categories, so you can switch back and forth at any time without losing anything.")
                    .font(.caption)
            }

            if selectedVersion == .v2 {
                Section {
                    Label {
                        Text("Lunch Money's v2 API is in alpha and may change without notice. If syncing starts failing, switch back to v1 — nothing is lost.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                } footer: {
                    Text("Differences on v2: new transactions are pushed directly and Lunch Money matches duplicates by external id (no pre-sync download), and the \u{201C}Check for recurring\u{201D} API import rule is not supported.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Lunch Money API")
    }
}

#Preview {
    NavigationView {
        APIVersionView()
    }
}
