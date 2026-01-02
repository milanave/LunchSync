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

@main
struct LunchSyncBackgroundHandlerExtension: BackgroundDeliveryExtension {
    let storage: Storage
    var container: ModelContainer!
    var modelContext: ModelContext!
    var logPrefix: String = "BGD"
    
    init() {
        self.storage = Storage()
        container = (try? Persistence.makeContainer()) ?? (try! Persistence.makeLocalContainer())
        modelContext = container.mainContext
        //self.addLog(prefix: logPrefix, message: "LunchSyncBackgroundHandlerBGD init", level: 1)
    }
    
    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        self.storage.setLastCheck()
        
        do{
            self.addLog(prefix: logPrefix, message: "didReceiveData starting", level: 1)
            let syncBroker = SyncBroker(context: modelContext, logPrefix: logPrefix)
            let appleWallet = AppleWallet()
            let preFetchedWalletData = try await appleWallet.getPreFetchedWalletData(logPrefix: logPrefix)
            self.addLog(prefix: logPrefix, message: "didReceiveData syncing", level: 1)
            let syncCount = try await syncBroker.fetchTransactions(
                prefix: logPrefix,
                showAlert: false,
                progress: { progressMessage in
                    //print("refreshWalletTransactions Progress: \(progressMessage)")
                },
                preFetchedWalletData: preFetchedWalletData
            )

            storage.setWeeklySpending(Decimal(syncCount))
            
            self.addLog(prefix: logPrefix, message: "didReceiveData got \(syncCount) transactions", level: 1)

        }catch {
            self.storage.setLastError()
            self.addLog(prefix: logPrefix, message: "Error processing background delivery: \(error)", level: 1)
        }
        
        self.addLog(prefix: logPrefix, message: "didReceiveData finished", level: 1)

    }
    
    func willTerminate() async {
        self.storage.setLastTerminate()
    }
    
    //@MainActor
    public func addLog(prefix: String, message: String, level: Int = 1) {
        do {
            let log = Log(message: "\(prefix): \(message)", level: level)
            modelContext.insert(log)
            try modelContext.save()
        } catch {
            self.storage.setLastError()
            print("Failed to save log: \(error)")
        }
    }
    
}

extension Decimal {
    // Format this as the specified currency and round it at larger numbers.
    func formatCurrency(for currencyCode: String, locale: Locale = .autoupdatingCurrent, compact: Bool = false) -> String {
        // If the value is more than `10`, round to the nearest whole number for clarity.
        let shouldRound = self >= 10 && compact
        
        let currencyStyle = Decimal.FormatStyle.Currency(
            code: currencyCode,
            locale: locale
        )
        
        let formatStyle = if shouldRound {
            currencyStyle.precision(.fractionLength(0))
        } else {
            currencyStyle
        }
        
        return self.formatted(formatStyle)
    }
    
    // Use the currency from the locale to format this as a currency that rounds at larger numbers.
    func formatCompactCurrency(locale: Locale = .autoupdatingCurrent) -> String {
        // Fall back to noncurrency formatting if the current locale doesn't have a currency.
        guard let currencyCode = locale.currency?.identifier else {
            return self.formatted()
        }
        
        return formatCurrency(for: currencyCode, locale: locale, compact: true)
    }
}

extension Date {
    var formatCompactDate: String {
        // If it's today, show only the time; otherwise, show only the date.
        if Calendar.current.isDateInToday(self) {
            return self.formatted(date: .omitted, time: .shortened)
        } else {
            return self.formatted(date: .numeric, time: .omitted)
        }
    }
}
