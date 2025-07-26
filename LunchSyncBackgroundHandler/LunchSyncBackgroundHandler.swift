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
        do{
            let autoImportTransactions = UserDefaults.standard.bool(forKey: "autoImportTransactions")
            let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self)
            
            // Ensure ModelContext operations stay on main actor
            let syncBroker = await MainActor.run {
                let context = container.mainContext
                return SyncBroker(context: context)
            }
            
            let pendingCount = try await syncBroker.fetchTransactions(
                prefix: "BD",
                andSync: autoImportTransactions
            ) { progressMessage in
                print("Silent Notification Progress: \(progressMessage)")
            }
            await addNotification(time: 0.5, title: "Transactions Synced", subtitle: "", body: "BGD found \(pendingCount) new transactions")
            
            if let storedDeviceToken = UserDefaults.standard.string(forKey: "deviceToken") {
                await registerWalletCheck(deviceToken: storedDeviceToken)
            }
        } catch {
            print("Error processing silent notification: \(error)")
            await addNotification(time: 0.5, title: "Error", subtitle: "", body: "Error processing background delivery: \(error)")
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
    
    func addNotification(time: Double, title: String, subtitle: String, body: String) async {
        //print("addNotification \(title), \(body)")
        let center = UNUserNotificationCenter.current()
        
        // First check current authorization status
        let settings = await center.notificationSettings()
        //print("Notification settings: \(settings.authorizationStatus.rawValue)")
        
        guard settings.authorizationStatus == .authorized else {
            print("Notifications not authorized")
            return
        }
        
        // Create and add notification
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = UNNotificationSound.default
        
        // Add category identifier and increase interruption level
        //content.categoryIdentifier = "TRANSACTION_UPDATE"
        //content.interruptionLevel = .timeSensitive  // Makes notification more likely to appear
        //content.interruptionLevel = .active
        content.interruptionLevel = .timeSensitive
        
        // For debugging, use a shorter time interval
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, time), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        do {
            try await center.add(request)
            //print("Notification scheduled successfully for \(Date().addingTimeInterval(time))")
            
            // Debug: List pending notifications
            _ = await center.pendingNotificationRequests()
            //print("Pending notifications: \(pending.count)")
            
            // Debug: List delivered notifications
            _ = await center.deliveredNotifications()
            //print("Delivered notifications: \(delivered.count)")
        } catch {
            print("Error scheduling notification: \(error)")
        }
    }
}
