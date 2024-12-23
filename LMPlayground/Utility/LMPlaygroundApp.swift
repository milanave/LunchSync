import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import AppIntents

extension Notification.Name {
    static let pendingTransactionsChanged = Notification.Name("pendingTransactionsChanged")
}

// MARK: UNUserNotificationCenterDelegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public var currentDeviceToken: String?
    
    func registerForPushNotifications(deviceToken: String, active: Bool = true, frequency: Int = 1) async {
        print("registerForPushNotifications \(deviceToken) freq=\(frequency)")
        guard let url = URL(string: "https://push.littlebluebug.com/register.php") else { return }
        
        var frequencyHour = 1
        switch frequency {
            case 0: frequencyHour = 1
            case 1: frequencyHour = 1
            case 2: frequencyHour = 6
            case 3: frequencyHour = 12
            case 4: frequencyHour = 24
            case 5: frequencyHour = 2
            case 6: frequencyHour = 3
        default:
            frequencyHour = 1
        }
        
        let payload = [
            "device_token": deviceToken,
            "active": active,
            "app_id" : "WalletSync",
            "frequency": frequencyHour,
            "key" : "2db298626156b95ce19b45cec605e061"
        ] as [String : Any]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("Push registration status: \(httpResponse.statusCode) hour=\(frequencyHour)")
            }
        } catch {
            print("Failed to register device token: \(error)")
        }
    }
    
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied, .ephemeral:
                // User has disabled notifications, unregister if we have a token
                if let token = self.currentDeviceToken {
                    Task {
                        await self.registerForPushNotifications(deviceToken: token, active: false)
                    }
                }
            default:
                break
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // This is called when a notification arrives while app is in foreground
        // Explicitly specify we want to show the alert even in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification response when user taps notification
        completionHandler()
    }
}

// MARK: CheckTransactionsIntent: AppIntent
struct CheckTransactionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check for Transactions"
    static var description: LocalizedStringResource = "Checks Wallet for new transactions"
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self)
        let context = container.mainContext
        let syncBroker = SyncBroker(context: context)
        
        let pendingCount = try await syncBroker.fetchTransactions(prefix: "Shortcut", andSync: false) { progressMessage in
            print("Check Transactions Progress: \(progressMessage)")
        }
        
        return .result(value: "Found \(pendingCount) new transactions")
    }
}

// MARK: SyncTransactionsIntent: AppIntent
struct SyncTransactionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Sync Transactions"
    static var description: LocalizedStringResource = "Syncs pending transactions to Lunch Money"
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self)
        let context = container.mainContext
        let syncBroker = SyncBroker(context: context)
        
        _ = try await syncBroker.fetchTransactions(prefix: "Shortcut", andSync: true) { progressMessage in
            print("Check Transactions Progress: \(progressMessage)")
        }
                
        return .result(value: "Successfully synced transactions")
    }
}

// MARK: AppDelegate: NSObject, UIApplicationDelegat
class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("Received silent notification in background: \(userInfo)")
        
        // Get autoImportTransactions from UserDefaults
        let autoImportTransactions = UserDefaults.standard.bool(forKey: "autoImportTransactions")
        
        Task {
            do {
                let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self)
                let context = container.mainContext
                let syncBroker = SyncBroker(context: context)
                
                let pendingCount = try await syncBroker.fetchTransactions(
                    prefix: "BN",
                    andSync: autoImportTransactions
                ) { progressMessage in
                    print("Silent Notification Progress: \(progressMessage)")
                }
                
                completionHandler(pendingCount > 0 ? .newData : .noData)
            } catch {
                print("Error processing silent notification: \(error)")
                completionHandler(.failed)
            }
        }
    }
    
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        notificationDelegate.currentDeviceToken = token
        @AppStorage("backgroundJobFrequency") var backgroundJobFrequency: Int = 1
        print("Device Token: \(token) freq=\(backgroundJobFrequency)")
        
        // Register the token with your server if background jobs are enabled
        if UserDefaults.standard.bool(forKey: "enableBackgroundJob") {
            Task {
                await notificationDelegate.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
            }
        }
    }
     
    
    // Also add this to handle failures
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}

// MARK: LMPlaygroundApp: App
@main
struct LMPlaygroundApp: App {
    @State private var pendingCount: Int = 0
    @AppStorage("enableBackgroundJob") private var enableBackgroundJob = false
    @AppStorage("backgroundJobFrequency") private var backgroundJobFrequency: Int = 1
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Set up notifications delegate first
        UNUserNotificationCenter.current().delegate = appDelegate.notificationDelegate
        
        // Then request authorization
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                
                if granted {
                    // Only register for remote notifications if permission was granted
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                }
            } catch {
                print("Error requesting notification permission: \(error)")
            }
        }
        
        // Add notification center observer
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak appDelegate] _ in
            appDelegate?.notificationDelegate.checkNotificationStatus()
        }
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Transaction.self,
            Account.self,
            Log.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView(context: sharedModelContainer.mainContext, appDelegate: appDelegate)
                .modelContainer(sharedModelContainer)
                .onReceive(NotificationCenter.default.publisher(for: .pendingTransactionsChanged)) { notification in
                    if let count = notification.object as? Int {
                        pendingCount = count
                        UNUserNotificationCenter.current().setBadgeCount(count) { error in
                            if let error = error {
                                print("Error setting badge count: \(error)")
                            }
                        }
                    }
                }
        }
    }
}

// MARK: AppShortcuts: AppShortcutsProvider
// Register the app's shortcuts
struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            .init(
                intent: CheckTransactionsIntent(),
                phrases: ["Check for new transactions"],
                shortTitle: "Check Transactions",
                systemImageName: "arrow.clockwise"
            ),
            .init(
                intent: SyncTransactionsIntent(),
                phrases: ["Sync transactions"],
                shortTitle: "Sync",
                systemImageName: "arrow.triangle.2.circlepath"
            )
        ]
    }
}
