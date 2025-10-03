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
import UserNotifications




@main
class LunchSyncBackgroundHandlerExtension: BackgroundDeliveryExtension {
    var container: ModelContainer!
    var modelContext: ModelContext!
    var logPrefix: String = "BGD"
    var bgdLogger: Logger!

    // add this when I'm ready to debug on the device
    //private let bgdLogger = Logger(subsystem: "com.your.bundleid", category: "BGD")
    //bgdLogger.info("didReceiveData types: \(String(describing: types))")
    
    required init() {
        do{
            bgdLogger = Logger(subsystem: "com.littlebluebug.AppleCardSync.LunchSyncBackgroundHandler", category: "BGD")
            bgdLogger.info("LunchSyncBackgroundHandlerBGD init")
            container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
            modelContext = ModelContext(container)
            self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init", level: 1)
        }catch {
            //print("LunchSyncBackgroundHandlerBGD init failed: \(error)")
            self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init failed: \(error)", level: 1)
        }
    }

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        //print("BGD: Received background data types: \(types)")
        bgdLogger.info("LunchSyncBackgroundHandlerBGD didReceiveData types: \(String(describing: types))")
        await self.addLog(prefix: "BGD", message: "LunchSyncBackgroundHandlerBGD didReceiveData", level: 1)
        do{
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
            let query = TransactionQuery(
                sortDescriptors: [sortDescriptor],
                predicate: #Predicate<FinanceKit.Transaction> { transaction in
                    transaction.transactionDate >= startDate &&
                    transaction.transactionDate <= endDate
                }
            )
            await self.addLog(prefix: "BGD", message: "starting query", level: 1)
            var transactions: [FinanceKit.Transaction]
            transactions = try await FinanceStore.shared.transactions(query: query)
            bgdLogger.info("LunchSyncBackgroundHandlerBGD got \(transactions.count) transactions")
            await self.addLog(prefix: "BGD", message: "got \(transactions.count) transactions", level: 1)
            /*
            // try to fetch directly
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            let sortDescriptor = SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .reverse)
            let query = TransactionQuery(sortDescriptors: [sortDescriptor], predicate: #Predicate<FinanceKit.Transaction>{transaction in
                transaction.transactionDate >= startDate &&
                transaction.transactionDate <= endDate
            })
            let transactions = try await FinanceStore.shared.transactions(query: query)
            */
            
            //container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
            //modelContext = ModelContext(container)
            //await self.addLog(prefix: "BGD", message: "LunchSyncBackgroundHandlerBGD didReceiveData", level: 1)
            
            
            /*
            for transaction in transactions {
                let amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
                await self.addLog(prefix: logPrefix, message: "T: \(transaction.transactionDescription) \(amount) \(transaction.transactionDate)", level: 2)
            }
            */
            
            /*
            // the normal code..
            let syncBroker = SyncBroker(context: modelContext, logPrefix: logPrefix)
            addLog(prefix: logPrefix, message: "SyncBroker starting", level: 2)
            
            let pendingCount = try await syncBroker.fetchTransactions(
                prefix: logPrefix, showAlert: true
            ) { progressMessage in
                print("Silent Notification Progress: \(progressMessage)")
            }
            //await syncBroker.addLog(prefix: logPrefix, message: "BGD found \(pendingCount) new transactions", level: 1)
            */
            
            //let pendingCount = 0
            //await self.addLog( prefix: logPrefix, message: "finished, found \(pendingCount) new transactions", level: 1)
            await self.addNotification(time: 0.1, title: "BGD Complete", subtitle: "", body: "finished, found \(transactions.count) new transactions")
        } catch {
            bgdLogger.info("Error processing background delivery: \(error)")
            await self.addLog( prefix: "BGD", message: "Error processing background delivery: \(error)", level: 1)
            await self.addNotification(time: 0.1, title: "BGD Sync Error", subtitle: "", body: "Error processing background delivery: \(error)")
        }
        print(" LunchSyncBackgroundHandlerBGD finished")
    }

    func willTerminate() async {
        await self.addLog( prefix: logPrefix, message: "calling willTerminate", level: 1)
    }
    
    @MainActor
    public func addLog(prefix: String, message: String, level: Int = 1) {
        do {
            let log = Log(message: "\(prefix): \(message)", level: level)
            modelContext.insert(log)
            try modelContext.save()
        } catch {
            print("Failed to save log: \(error)")
        }
    }
    
    func addNotification(time: Double, title: String, subtitle: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
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
        content.categoryIdentifier = "TRANSACTION_UPDATE"
        content.interruptionLevel = .timeSensitive  // Makes notification more likely to appear
        
        // For debugging, use a shorter time interval
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, time), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        do {
            try await center.add(request)
            _ = await center.pendingNotificationRequests()
            _ = await center.deliveredNotifications()
        } catch {
            print("Error scheduling notification: \(error)")
        }
    }
        
}
