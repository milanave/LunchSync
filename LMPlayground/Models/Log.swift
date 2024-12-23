import Foundation
import SwiftData

@Model
class Log {
    var date: Date
    var message: String
    var level: Int
    
    init(date: Date = Date(), message: String, level: Int) {
        self.date = date
        self.message = message
        self.level = level
    }
} 
