//
//  SettingsView.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
//  Updated 7/28/25, added new transaction settings

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Binding var isPresented: Bool
		
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        
        //let is_test_flight = sharedDefaults.bool(forKey: "is_test_flight")
        let runStateString = Utility.getRunState()?.description ?? "unknown"
        return "\(version).\(build) (\(runStateString))"
    }
    private let storage = Storage()
    
    var body: some View {
        NavigationView {
            VStack{
                List {
                   Section {
                         
                     NavigationLink {
                         InstructionsView()
                     } label: {
                         HStack {
                             Text("Instructions")
                         }
                     }
                     
                     NavigationLink {
                         ImportSettingsView()
                     } label: {
                         HStack {
                             Text("Import Settings")
                         }
                     }
                     
                     NavigationLink {
                         APIImportRulesView()
                     } label: {
                         HStack {
                             Text("API Import Rules")
                         }
                     }
                     
                     NavigationLink {
                         CleanupView()
                     } label: {
                         HStack {
                             Text("Data removal rules")
                         }
                     }
                     
                     NavigationLink {
                         ShortcutsView()
                     } label: {
                         HStack {
                             Text("Shortcuts")
                         }
                     }
                 } footer: {
                    VStack(alignment: .center, spacing: 8) {
                         Text("Version \(appVersion)")
                             .font(.body)
                         Button {
                             if let url = URL(string: "https://www.littlebluebug.com") {
                                 UIApplication.shared.open(url)
                             }
                         } label: {
                             Text("https://www.littlebluebug.com")
                                 .font(.footnote)
                         }
                         Button {
                             if let url = URL(string: "mailto:support@littlebluebug.com") {
                                 UIApplication.shared.open(url)
                             }
                         } label: {
                             Text("support@littlebluebug.com")
                                 .font(.footnote)
                         }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                 }
            }
        }
        .navigationTitle("Settings")
        .navigationBarItems(trailing: Button("Done") {
            isPresented = false
        })
        }
    }
}

// MARK: Preview
#Preview {
    SettingsView(isPresented: .constant(true)) 
}
