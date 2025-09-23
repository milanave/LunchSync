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


struct PushRegistrationResponse: Codable {
    let status: Bool
    let message: String
    let frequency: Int?
}

@main
class LunchSyncBackgroundHandlerExtension: BackgroundDeliveryExtension {
    var container: ModelContainer!
    var modelContext: ModelContext!
    var logPrefix: String = "BGD"
    
    required init() {
        // Set up any resources or storage used by the extension
        print("LunchSyncBackgroundHandlerBGD Extension Initialized")
        do{
            container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
            modelContext = ModelContext(container)
            self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init", level: 1)
            
        }catch {
            //print("LunchSyncBackgroundHandlerBGD init failed: \(error)")
            self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init failed: \(error)", level: 1)
        }
    }

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        print("BGD: Received background data types: \(types)")
        do{
            container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
            modelContext = ModelContext(container)
            self.addLog(prefix: "BGD", message: "LunchSyncBackgroundHandlerBGD didReceiveData", level: 1)

            /*
            // try the sample code
            let total: Decimal = try await FinanceUtilities.calculateWeeklySpendingTotal()
            self.addLog(prefix: "BGD", message: "test total = \(total)", level: 1)
            */
            
            
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
            for transaction in transactions {
                let amount = (transaction.transactionAmount.amount as NSDecimalNumber).doubleValue
                self.addLog(prefix: logPrefix, message: "T: \(transaction.transactionDescription) \(amount) \(transaction.transactionDate)", level: 2)
            }
            
            
            /*
            // the normal code..
            let syncBroker = SafeSyncBroker(context: modelContext, logPrefix: logPrefix)
            addLog(prefix: logPrefix, message: "SyncBroker starting", level: 2)
            
            let pendingCount = try await syncBroker.fetchTransactions(
                prefix: logPrefix, showAlert: true
            ) { progressMessage in
                print("Silent Notification Progress: \(progressMessage)")
            }
            //await syncBroker.addLog(prefix: logPrefix, message: "BGD found \(pendingCount) new transactions", level: 1)
            */
            
            let pendingCount = 0
            self.addLog( prefix: logPrefix, message: "finished, found \(pendingCount) new transactions", level: 1)

        } catch {
            self.addLog( prefix: "BGD", message: "Error processing background delivery: \(error)", level: 1)
            //await addNotification(time: 0.5, title: "BDG LunchSync Error", subtitle: "", body: "Error processing background delivery: \(error)")
        }
        print(" LunchSyncBackgroundHandlerBGD finished")
    }

    func willTerminate() async {
        self.addLog( prefix: logPrefix, message: "calling willTerminate", level: 1)
    }
    
    public func addLog(prefix: String, message: String, level: Int = 1) {
        do {
            let log = Log(message: "\(prefix): \(message)", level: level)
            modelContext.insert(log)
            try modelContext.save()
        } catch {
            print("Failed to save log: \(error)")
        }
    }
        
}
