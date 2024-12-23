import BackgroundTasks
import SwiftUI
import SwiftData

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    static let backgroundTaskId = "com.littlebluebug.AppleCardSync.refresh"
    private var modelContext: ModelContext?
    private var lastLogTime: Date?
    private var lastTaskStatus: (date: Date?, status: String) = (nil, "Not started")
    @AppStorage("autoImportTransactions") private var autoImportTransactions = false
    @AppStorage("backgroundJobFrequency") private var backgroundJobFrequency: Int = 1
    
    private func addLog(message: String, level: Int = 1) {
        let now = Date()
        var fullMessage = message
        
        if let lastTime = lastLogTime {
            let timeDiff = now.timeIntervalSince(lastTime)
            let hours = Int(timeDiff) / 3600
            let minutes = Int(timeDiff) / 60 % 60
            let seconds = Int(timeDiff) % 60
            if(seconds>1){
                fullMessage += String(format: " (%02d:%02d:%02d)", hours, minutes, seconds)
            }
        }
        
        guard let context = modelContext else {
            print("BG ModelContext not set, cannot add log: \(fullMessage)")
            return
        }
        //print("BG ModelContext set, adding log: \(fullMessage)")
        
        
        let log = Log(message: fullMessage, level: level)
        context.insert(log)
        
        do {
            try context.save()
            lastLogTime = now
        } catch {
            print("BG Failed to save log: \(error)")
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        //addLog(message: "BG ModelContext set (3/6)")
    }
    
    func scheduleBackgroundTask(backgroundJobFrequency: Int? = 1) {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        /*
         Text("15 minutes").tag(0)
         Text("Hour").tag(1)
         Text("6 hours").tag(2)
         Text("12 hours").tag(3)
         Text("24 hours").tag(4)
         */
        addLog(message: "BG scheduleBackgroundTask for \(String(describing: backgroundJobFrequency)) (2/6)")
        print("BG scheduleBackgroundTask for \(String(describing: backgroundJobFrequency))")
        switch backgroundJobFrequency {
            case 0: request.earliestBeginDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            case 1: request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            case 2: request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
            case 3: request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
            case 4: request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())
            case .none:
                print("scheduleBackgroundTask unknown value \(String(describing: backgroundJobFrequency))")
                request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            case .some(_):
                print("scheduleBackgroundTask unknown value \(String(describing: backgroundJobFrequency))")
                request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            @unknown default:
                print("scheduleBackgroundTask unknown value \(String(describing: backgroundJobFrequency))")
                request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        }
        
        //request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        //request.earliestBeginDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())

        do {
            try BGTaskScheduler.shared.submit(request)
            print("BG Next background task scheduled")
            updateStatus("Scheduled")
            addLog(message: "BG Next background task scheduled")
        } catch {
            updateStatus("Schedule failed")
            print("BG failed to schedule next background task: \(error.localizedDescription)")
            addLog(message: "BG failed to schedule next background task: \(error.localizedDescription)")
        }
    }
    
    func cancelAllPendingTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
    
    public func handleBackgroundTask(task: BGProcessingTask) async {
        updateStatus("Running")
        addLog(message: "BG handleBackgroundTask started (1/6)")
        
        task.expirationHandler = {
            self.updateStatus("Expired")
            self.addLog(message: "BG task expired (1.1/6)")
            task.setTaskCompleted(success: false)
        }
        
        scheduleBackgroundTask(backgroundJobFrequency: backgroundJobFrequency)
                        
        do {
            // init the syncBroker
            let syncBroker: SyncBroker? = await MainActor.run {
                guard let context = self.modelContext else {
                    return nil
                }
                return SyncBroker(context: context)
            }
            guard let syncBroker = syncBroker else {
                addLog(message: "BG Failed to create syncBroker (1.1/6)")
                task.setTaskCompleted(success: false)
                return
            }
            
            let pendingCount = try await syncBroker.fetchTransactions(prefix: "Background", andSync: true) { progressMessage in
                self.addLog(message: "BG fetchTransactions \(progressMessage) (4/6)")
            }
            print("BG refreshWalletTransactions Completed with \(pendingCount) pending transactions")
            //UserDefaults.setLastUpdated(Date())
            task.setTaskCompleted(success: true)
            updateStatus("Completed")
            addLog(message: "BG task completed successfully (5/6)")
        } catch {
            updateStatus("Failed")
            addLog(message: "BG task failed: \(error.localizedDescription) (5/6)")
            task.setTaskCompleted(success: false)
        }
    }
    
    func updateBadgeCount(wallet: Wallet) async -> Int{
        let pendingCount = await wallet.getTransactionsWithStatus(.pending).count
        
        NotificationCenter.default.post(
            name: .pendingTransactionsChanged,
            object: pendingCount
        )
        
        return pendingCount
    }
    
    func getStatus() -> String {
        if let lastDate = lastTaskStatus.date {
            let timeAgo = lastDate.formatted(date: .numeric, time: .shortened)
            return "\(lastTaskStatus.status) at \(timeAgo)"
        }
        return lastTaskStatus.status
    }
    
    private func updateStatus(_ status: String) {
        lastTaskStatus = (Date(), status)
    }
} 
