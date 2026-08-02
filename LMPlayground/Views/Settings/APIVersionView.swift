//
//  APIVersionView.swift
//  LMPlayground
//
//  Lets the user choose which Lunch Money API version syncs use. v2 is the
//  default; v1 remains available as a fallback. Both versions use the same
//  API token and operate on the same data and ids, so switching back and
//  forth is safe at any time.
//

import SwiftUI

struct APIVersionView: View {
    @AppStorage(LMAPIVersion.defaultsKey, store: UserDefaults(suiteName: LMAPIVersion.appGroupSuiteName))
    private var apiVersionRaw = LMAPIVersion.defaultVersion.rawValue
    @AppStorage(LMAPIBaseURL.defaultsKey, store: UserDefaults(suiteName: LMAPIVersion.appGroupSuiteName))
    private var apiBaseURLRaw = ""

    @State private var apiBaseURLInput = ""

    private var selectedVersion: LMAPIVersion {
        LMAPIVersion(rawValue: apiVersionRaw) ?? LMAPIVersion.defaultVersion
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

            Section {
                TextField("https://api.yourserver.com", text: $apiBaseURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disableAutocorrection(true)
                    .onSubmit {
                        saveCustomBaseURL()
                    }
            } header: {
                Text("API Base URL")
            } footer: {
                Text("Optional. Leave blank to use Lunch Money's default API host. Custom values are trimmed and validated; invalid URLs are ignored and default endpoints are used.")
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
        .onAppear {
            apiBaseURLInput = apiBaseURLRaw
        }
        .onDisappear {
            saveCustomBaseURL()
        }
    }

    private func saveCustomBaseURL() {
        let trimmed = apiBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apiBaseURLRaw = ""
            apiBaseURLInput = ""
            return
        }

        guard let normalized = LMAPIBaseURL.normalizedCustomBaseURL(trimmed) else {
            apiBaseURLRaw = trimmed
            return
        }
        apiBaseURLRaw = normalized
        apiBaseURLInput = normalized
    }
}

#Preview {
    NavigationView {
        APIVersionView()
    }
}
