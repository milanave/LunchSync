//
//  Utility.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/3/25.
//
import Foundation
import UserNotifications

enum RunState: String {
    case canvas = "canvas"
    case simulator = "simulator"
    case connected = "connected"
    case testFlight = "testFlight"
    case appStore = "appStore"
}

struct Utility {
    private init() {}
    
    public static func getUserDefaults() -> UserDefaults{
        return UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
    }
    
    public static func isTestFlight() -> Bool {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
    }
    
    public static func getRunState() -> RunState? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .canvas
        } else {
            #if targetEnvironment(simulator)
            return .simulator
            #else
            return .connected
            #endif
        }
        #else
        if self.isTestFlight() {
            return .testFlight
        } else {
            return .appStore
        }
        #endif
    }
    
    public static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
                return true
        #else
                return false
        #endif
    }
    
    // states: .canvas .simulator .connected .testFlight .appStore
    public static func isMockEnvironment() -> Bool {
        let runState = self.getRunState()
        //if(runState == .canvas || runState == .simulator){
        if(runState == .canvas){
            return true
        }
        return false
    }
    
    public static func addNotification(time: Double, title: String, subtitle: String, body: String) async {
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
        content.categoryIdentifier = "TRANSACTION_UPDATE"
        content.interruptionLevel = .timeSensitive  // Makes notification more likely to appear
        
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

extension RunState: CustomStringConvertible {
    var description: String {
        switch self {
        case .canvas:     return "Debug"
        case .simulator:  return "Simulator"
        case .connected:  return "Connected"
        case .testFlight: return "TestFlight"
        case .appStore:   return "AppStore"
        }
    }
}
