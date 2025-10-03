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
    
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied, .ephemeral:
                // User has disabled notifications, unregister if we have a token
                if let token = self.currentDeviceToken {
                    Task {
                        await PushAPI.registerForPushNotifications(deviceToken: token, active: false)
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
        
        let pendingCount = try await syncBroker.fetchTransactions(prefix: "SC", showAlert: true, skipSync: true) { progressMessage in
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
        
        _ = try await syncBroker.fetchTransactions(prefix: "SC", showAlert: true) { progressMessage in
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
        
        Task {
            do {
                let container = try ModelContainer(for: Transaction.self, Account.self, Log.self, Item.self, LMCategory.self, TrnCategory.self)
                let context = container.mainContext
                let syncBroker = SyncBroker(context: context, logPrefix: "BN")
                
                /*
                _ = try await syncBroker.fetchTransactions(
                    prefix: "BN",
                    showAlert: true
                ) { progressMessage in
                    print("Silent Notification Progress: \(progressMessage)")
                }
                */
                
                let appleWallet = AppleWallet()
                let preFetchedWalletData = try await appleWallet.getPreFetchedWalletData()
                _ = try await syncBroker.fetchTransactions(
                    prefix: "BN",
                    showAlert: true,
                    progress: { progressMessage in
                        //print("refreshWalletTransactions Progress: \(progressMessage)")
                    },
                    preFetchedWalletData: preFetchedWalletData
                )
                
                //completionHandler(pendingCount > 0 ? .newData : .noData)
                completionHandler(.newData) // send this all the time to try to get more executions
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
        
        // Store the device token in AppStorage
        @AppStorage("deviceToken", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) var storedDeviceToken: String = ""
        storedDeviceToken = token
        
        @AppStorage("backgroundJobFrequency", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) var backgroundJobFrequency: Int = 1
        
        //print("Device Token: \(token) freq=\(backgroundJobFrequency)")
        
        // Register the token with your server if background jobs are enabled
                        let sharedDefaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? UserDefaults.standard
                if sharedDefaults.bool(forKey: "enableBackgroundJob") {
            Task {
                await PushAPI.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
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
    @AppStorage("enableBackgroundJob", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var enableBackgroundJob = false
    @AppStorage("backgroundJobFrequency", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var backgroundJobFrequency: Int = 1
    
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
                    //print("Notification permission granted")
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
            Log.self,
            LMCategory.self,
            TrnCategory.self,
            TransactionHistory.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // One-time, minimal setup to backfill TrnCategory.lm_* from lm_category and clear link
            Task { @MainActor in
                runTrnCategorySetupOnce(context: container.mainContext)
            }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView(context: sharedModelContainer.mainContext, appDelegate: appDelegate)
                .modelContainer(sharedModelContainer)
            /*
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
             */
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

// MARK: Setup: backfill TrnCategory.lm_* and clear relationship once
@MainActor
func runTrnCategorySetupOnce(context: ModelContext) {
    let defaults = UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync") ?? .standard
    let key = "setup_trncategory_lm_fields_v1"
    if defaults.bool(forKey: key) { return }
    do {
        let fetch = FetchDescriptor<TrnCategory>()
        let all = try context.fetch(fetch)
        var cleared = 0
        for trn in all {
            // Avoid dereferencing a potentially invalid LMCategory instance; just clear the link.
            if trn.lm_category != nil {
                trn.lm_category = nil
                cleared += 1
            }
        }
        if cleared > 0 {
            try context.save()
        }
        defaults.set(true, forKey: key)
        print("Setup complete: cleared \(cleared) TrnCategory relationships")
    } catch {
        print("Setup failed: \(error)")
    }
}
