/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The persistent storage utility type.
 
 
*/

import Foundation

struct Storage {
    // This is the identifier of the app group in the project settings.
    private static var appGroupIdentifier = "group.com.littlebluebug.AppleCardSync"
    private static var weeklySpendingKey = "WeeklySpending"
    private static var lastCheckKey = "lastCheck"
    private static var lastInitKey = "lastInit"
    private static var lastTerminateKey = "lastTerminate"
    private static var lastErrorKey = "lastError"
    
    private let defaults: UserDefaults
    
    init() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            fatalError("Couldn't initialize UserDefaults for app group")
        }
        
        self.defaults = defaults
        defaults.set(Date(), forKey: Self.lastInitKey)
    }
    
    var weeklySpending: Decimal {
        // Read the value as a `String` and convert it to a `Decimal` if it's not `nil`.
        if let amount = defaults.string(forKey: Self.weeklySpendingKey).flatMap({ Decimal(string: $0) }) {
            return amount
        } else {
            return 0
        }
    }
    
    func setWeeklySpending(_ amount: Decimal) {
        // Convert the `Decimal` value into a `String` before storing it.
        defaults.set(String(describing: amount), forKey: Self.weeklySpendingKey)
        // Record the date and time this value was updated.
        defaults.set(Date(), forKey: Self.lastCheckKey)
    }
    
    func getWeeklySpending() -> Decimal {
        // Return the stored weekly spending as a Decimal.
        weeklySpending
    }

    func getLastCheck() -> Date? {
        // Return the last time weekly spending was updated.
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }
    func setLastCheck()  {
        // Return the last time weekly spending was updated.
        defaults.set(Date(), forKey: Self.lastCheckKey)
    }
    func getLastError() -> Date? {
        // Return the last time weekly spending was updated.
        defaults.object(forKey: Self.lastErrorKey) as? Date
    }
    func setLastError()  {
        // Return the last time weekly spending was updated.
        defaults.set(Date(), forKey: Self.lastErrorKey)
    }

    func getLastInit() -> Date? {
        // Return the last time weekly spending was updated.
        defaults.object(forKey: Self.lastInitKey) as? Date
    }
    func getLastTerminate() -> Date? {
        // Return the last time weekly spending was updated.
        defaults.object(forKey: Self.lastTerminateKey) as? Date
    }
    func setLastTerminate() {
        // Return the last time weekly spending was updated.
        defaults.set(Date(), forKey: Self.lastTerminateKey)
    }
}
