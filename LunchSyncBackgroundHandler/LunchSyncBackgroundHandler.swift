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
import os


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
    var logger: Logger!
    var container: ModelContainer!
    var modelContext: ModelContext!
    var logPrefix: String = "BGD"
    
    required init() {
        // Set up any resources or storage used by the extension
        print("LunchSyncBackgroundHandlerBGD Extension Initialized")
        do{
            logger = Logger(subsystem: "com.littlebluebug.AppleCardSync", category: "BackgroundDelivery")
            logger.error(" LunchSyncBackgroundHandlerBGD init started")
            container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
            modelContext = ModelContext(container)
            self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init", level: 1)
            logger.error(" LunchSyncBackgroundHandlerBGD init complete")
        }catch {
            print("LunchSyncBackgroundHandlerBGD init failed: \(error)")
            logger.error(" LunchSyncBackgroundHandlerBGD init failed \(error)")
        }
    }

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        do{

            addLog( prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD didReceiveData", level: 1)
            
            let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
            let autoImportTransactions = sharedDefaults.bool(forKey: "autoImportTransactions")
            let syncBroker = SafeSyncBroker(context: modelContext, logPrefix: logPrefix)
            addLog(prefix: logPrefix, message: "SyncBroker starting, auto=\(autoImportTransactions)", level: 2)
            
            let pendingCount = try await syncBroker.fetchTransactions(
                prefix: logPrefix, showAlert: true
            ) { progressMessage in
                print("Silent Notification Progress: \(progressMessage)")
            }
            
            //await syncBroker.addLog(prefix: logPrefix, message: "BGD found \(pendingCount) new transactions", level: 1)
            addLog( prefix: logPrefix, message: "BGD found \(pendingCount) new transactions", level: 1)
            
            await addNotification(time: 0.5, title: "BGD LunchSync Transactions Synced", subtitle: "", body: "BGD found \(pendingCount) new transactions")

            if let storedDeviceToken = sharedDefaults.string(forKey: "deviceToken") {
                await registerWalletCheck(deviceToken: storedDeviceToken)
            }else{
                addLog( prefix: logPrefix, message: "registerWalletCheck failed, no deviceToken", level: 1)
            }
            
        } catch {
            print("LunchSyncBackgroundHandlerBGD Error processing silent notification: \(error)")
            logger.error(" LunchSyncBackgroundHandlerBGD Error processing background delivery: \(error)")
            addLog( prefix: logPrefix, message: "BGD complete", level: 1)
            await addNotification(time: 0.5, title: "BDG LunchSync Error", subtitle: "", body: "Error processing background delivery: \(error)")
        }
        logger.error(" LunchSyncBackgroundHandlerBGD finished")
    }

    func willTerminate() async {
        // Called just before the extension will be terminated by the system
        logger.error(" LunchSyncBackgroundHandlerBGD willTerminate")
        addLog( prefix: logPrefix, message: "calling willTerminate", level: 1)
        await addNotification(time: 0.5, title: "BDG terminating", subtitle: "", body: "BDG terminating")
    }
    
    public func addLog(prefix: String, message: String, level: Int = 1) {
        let log = Log(message: "\(prefix): \(message)", level: level)
        modelContext.insert(log)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save log: \(error)")
        }
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
            "action_id": "bgd_complete",
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
