//
//  LunchSyncBackgroundHandler.swift
//  LunchSyncBackgroundHandler
//
//  Created by Bob Sanders on 7/10/25.
//

import ExtensionFoundation
import FinanceKit
import Foundation
import SwiftData
import SwiftUI

extension Notification.Name {
    static let pendingTransactionsChanged = Notification.Name("pendingTransactionsChanged")
}

struct PushRegistrationResponse: Codable {
    let status: Bool
    let message: String
    let frequency: Int?
}

@main
class LunchSyncBackgroundHandlerExtension: BackgroundDeliveryExtension {
    required init() {
        // Set up any resources or storage used by the extension
    }

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        /*
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .month, value: -1, to: endDate)!
        let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
        let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: #Predicate<FinanceKit.Transaction>{transaction in
            transaction.transactionDate >= startDate &&
            transaction.transactionDate <= endDate
        }, limit: 1000, offset: 0)
        
        let transactions = try? await FinanceStore.shared.transactions(query: query)
        
        print("didReceiveData \(transactions?.count ?? 0)")
        */
        do{
            let autoImportTransactions = UserDefaults.standard.bool(forKey: "autoImportTransactions")
            let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self)
            
            // Ensure ModelContext operations stay on main actor
            let syncBroker = await MainActor.run {
                let context = container.mainContext
                return SyncBroker(context: context)
            }
            
            _ = try await syncBroker.fetchTransactions(
                prefix: "BD",
                andSync: autoImportTransactions
            ) { progressMessage in
                print("Silent Notification Progress: \(progressMessage)")
            }
            
            // Call registerWalletCheck after processing is complete
            // Fetch device token from AppStorage
            
            if let storedDeviceToken = UserDefaults.standard.string(forKey: "deviceToken") {
                await registerWalletCheck(deviceToken: storedDeviceToken)
            }
        } catch {
            print("Error processing silent notification: \(error)")            
        }
        
    }

    func willTerminate() async {
        // Called just before the extension will be terminated by the system
    }
    
    func registerWalletCheck(deviceToken: String) async {
        guard let url = URL(string: "https://push.littlebluebug.com/register.php") else {
            print("Invalid URL for wallet check")
            return
        }
        
        guard let pushServiceKey = Bundle.main.infoDictionary?["PUSH_SERVICE_KEY"] as? String ??
                Bundle.main.object(forInfoDictionaryKey: "INFOPLIST_KEY_PUSH_SERVICE_KEY") as? String else{
            print("Unable to get PUSH_SERVICE_KEY")
            return
        }
        
        #if DEBUG
        let environment = "Test"
        #else
        let environment = "Production"
        #endif
        
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let versionString = "\(appVersion) (\(buildNumber))"
        
        let payload = [
            "device_token": deviceToken,
            "app_id": "WalletSync",
            "key": pushServiceKey,
            "environment": environment,
            "action_id": "push_received",
            "app_version": versionString
        ] as [String : Any]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PushRegistrationResponse.self, from: data)
            print("Wallet check registration status: \(response.status)")
        } catch {
            print("Error in wallet check registration: \(error.localizedDescription)")
        }
    }
}
