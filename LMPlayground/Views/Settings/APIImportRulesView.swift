//
//  APIImportRulesView.swift
//  LMPlayground
//
//  Created by AI Assistant on 1/9/26.
//

import SwiftUI

struct APIImportRulesView: View {
	@AppStorage("apply_rules", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var applyRules = false
    @AppStorage("skip_duplicates", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipDuplicates = false
    @AppStorage("check_for_recurring", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var checkForRecurring = false
    @AppStorage("skip_balance_update", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var skipBalanceUpdate = false
    
	var body: some View {
		List {
			Section{
				Toggle(isOn: $applyRules) {
					HStack {
						Text("Apply rules")
					}
				}
				.listRowSeparator(.hidden)
			} header: {
                Text(.init("Customize how transactions are inserted using the LunchMoney API. See the [LunchMoney API](https://lunchmoney.dev/#insert-transactions) documentation for more information."))
			} footer: {
				Text("If true, will apply account’s existing rules to the inserted transactions")
					.font(.caption)
			}
            Section{
                    Toggle(isOn: $skipDuplicates) {
                        HStack {
                            Text("Skip duplicates")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, the system will automatically dedupe based on transaction date, payee and amount.")
                        .font(.caption)
                }
                Section{
                    Toggle(isOn: $checkForRecurring) {
                        HStack {
                            Text("Check for recurring")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, will check new transactions for occurrences of new monthly expenses.")
                        .font(.caption)
                }
                Section{
                    Toggle(isOn: $skipBalanceUpdate) {
                        HStack {
                            Text("Skip balance update")
                        }
                    }
                    .listRowSeparator(.hidden)
                } footer: {
                    Text("If true, will skip updating balance if an asset_id is present for any of the transactions.")
                        .font(.caption)
                }
					
                
		}
		.navigationTitle("API Import Rules")
	}
}

#Preview {
	NavigationView {
		APIImportRulesView()
	}
}


