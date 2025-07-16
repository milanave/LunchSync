//
//  LunchSyncBackgroundHandler.swift
//  LunchSyncBackgroundHandler
//
//  Created by Bob Sanders on 7/10/25.
//

import ExtensionFoundation
import FinanceKit
import Foundation

@main
class LunchSyncBackgroundHandlerExtension: BackgroundDeliveryExtension {
    required init() {
        // Set up any resources or storage used by the extension
    }

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        
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
        //if types.contains(.transactions) {}
    }

    func willTerminate() async {
        // Called just before the extension will be terminated by the system
    }
}
