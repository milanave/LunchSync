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
    
    private let defaults: UserDefaults
    
    init() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            fatalError("Couldn't initialize UserDefaults for app group")
        }
        
        self.defaults = defaults
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
}
