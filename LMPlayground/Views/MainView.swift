import SwiftUI
import SwiftData
import FinanceKit
import BackgroundTasks

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var wallet: Wallet
    
    @State private var apiConnected = false
    @State private var showingTokenPrompt = false
    @State private var showingAccountView = false
    @State private var isShowingAccountSelectionDialog = false
    @State private var apiToken = ""
    @State private var walletsConnected = 0
    @State private var pendingCount = 0
    @State private var errorCount = 0
    @State private var completedCount = 0
    @State private var isSyncing = false
    @State private var syncError: String?
    
    @State private var userName: String = "Loading..."
    private let keychain = Keychain()
    @State private var appleWallet: AppleWallet
    @State private var showingPreviewTransactions = false
    @State private var transactions: [Transaction] = []
    @State private var syncProgress: Wallet.SyncProgress?
    @State private var showingSyncProgress = false
    
    @State private var lastUpdated = Date() //.addingTimeInterval(-10*60) //(-365 * 24 * 60 * 60)

    @AppStorage("enableBackgroundJob") private var enableBackgroundJob = false
    @AppStorage("autoImportTransactions") private var autoImportTransactions = false
    @AppStorage("backgroundJobFrequency") private var backgroundJobFrequency: Int = 1

    @State private var showingAboutSheet = false
    @State private var showingJobSheet = false

    private let appDelegate: AppDelegate

    @State private var timeUpdateTimer: Timer? = nil
    @State private var timeUpdateTrigger = Date()

    @State private var isVerifyingToken = false

    @State private var isSimulator = false

    @State private var registrationMessage: PushRegistrationResponse?

    private var backgroundJobFrequencyText: String {
        switch backgroundJobFrequency {
        case 1: return "hour"
        case 2: return "6 hours"
        case 3: return "12 hours"
        case 4: return "24 hours"
        case 5: return "2 hours"
        case 6: return "3 hours"
        default: return "hour"
        }
    }

    init(context: ModelContext, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        let keychain = Keychain()
        var initialToken = ""
        do{
           initialToken = try keychain.retrieveTokenFromKeychain()
        } catch {
           initialToken = ""
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let wallet = MockWallet(context: context, apiToken: "mock-token")
            _wallet = StateObject(wrappedValue: wallet)
            _appleWallet = State(initialValue: MockAppleWallet())
        } else {
            let wallet = Wallet(context: context, apiToken: initialToken)
            _wallet = StateObject(wrappedValue: wallet)
            _appleWallet = State(initialValue: MockAppleWallet())
        }
        #else
        let wallet = Wallet(context: context, apiToken: initialToken)
        _wallet = StateObject(wrappedValue: wallet)
        _appleWallet = State(initialValue: AppleWallet())
        #endif
        
        _apiToken = State(initialValue: initialToken)
        _transactions = State(initialValue: [])
        
        //print("MainView init with enable=\(enableBackgroundJob) and freq=\(backgroundJobFrequency)")
        
        #if targetEnvironment(simulator)
        _isSimulator = State(initialValue: true)
        #endif
    }
    
    // MARK: main view body
    var body: some View {
        NavigationStack() {
            VStack {
                List {
                    lunchMoneyApiSection()
                    if(apiConnected) {
                        appleWalletSection()
                        if(walletsConnected>0){
                            transactionSyncSection()
                            optionButtons()
                            //automateButtons()
                        }
                    }
                }
                .refreshable {
                    //checkApiToken()
                    refreshView()
                    //refreshWalletTransactions()
                }
                
                // Add this new button at the bottom
                /*
                if walletsConnected > 0 {
                    Button(action: {
                        Task {
                            let transactions = wallet.getTransactionsWithStatus(.complete)
                            // Take the 3 most recent transactions
                            let recentTransactions = Array(transactions.prefix(3))
                            recentTransactions.forEach { transaction in
                                print("Resync \(transaction.id)")
                                wallet.setSyncStatus(newTrans: transaction, newStatus: .pending)
                            }
                            refreshView()
                        }
                    }) {
                        Text("Mark 3 Recent Transactions as Pending")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
                 */
            }
            .onAppear {
                refreshView()
            }
            .navigationTitle("Lunch Sync")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAboutSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                NavigationStack {
                    AboutView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingAboutSheet = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showingJobSheet) {
                backgroundSyncSheet()
            }
        }.navigationTitle("Lunch Sync")
        .onAppear {
            checkApiToken()
            timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                timeUpdateTrigger = Date()
            }
        }
        .onDisappear {
            timeUpdateTimer?.invalidate()
            timeUpdateTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshView()
        }
        .sheet(isPresented: $showingSyncProgress) {
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                if let progress = syncProgress {
                    Text("\(progress.current) of \(progress.total) transactions")
                        .font(.headline)
                    
                    Text(progress.status)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .padding(.horizontal)
                }
                
                Button(role: .cancel) {
                    isSyncing = false
                    showingSyncProgress = false
                } label: {
                    Text("Cancel")
                        .foregroundColor(.red)
                }
                .padding()
            }
            .padding()
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }

    }
    
    // MARK: background sync sheet
    private func backgroundSyncSheet() -> some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Enable background sync", isOn: $enableBackgroundJob.animation())
                        .disabled(walletsConnected < 1)
                        .onChange(of: enableBackgroundJob) { _, newValue in
                            if !newValue {
                                autoImportTransactions = false
                                if let token = appDelegate.notificationDelegate.currentDeviceToken {
                                    Task {
                                        let response = await appDelegate.notificationDelegate.registerForPushNotifications(deviceToken: token, active: false, frequency: backgroundJobFrequency)
                                        await MainActor.run {
                                            registrationMessage = response
                                        }
                                    }
                                } else {
                                    print("Device token not yet available")
                                    DispatchQueue.main.async {
                                        UIApplication.shared.registerForRemoteNotifications()
                                    }
                                }
                            } else {
                                if let token = appDelegate.notificationDelegate.currentDeviceToken {
                                    Task {
                                        let response = await appDelegate.notificationDelegate.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
                                        await MainActor.run {
                                            registrationMessage = response
                                        }
                                    }
                                }else{
                                    print("couldn't get token")
                                }
                            }
                            
                        }
                    
                    if enableBackgroundJob {
                        Toggle("Import Transactions Automatically", isOn: $autoImportTransactions)
                            .disabled(walletsConnected < 1)
                        
                        Picker("Check for transactions every", selection: $backgroundJobFrequency) {
                            Text("Hour").tag(1)
                            Text("2 hours").tag(5)
                            Text("3 hours").tag(6)
                            Text("6 hours").tag(2)
                            Text("12 hours").tag(3)
                            Text("24 hours").tag(4)
                        }
                        .onChange(of: backgroundJobFrequency) { _, newValue in

                            if let token = appDelegate.notificationDelegate.currentDeviceToken {
                                Task {
                                    let response = await appDelegate.notificationDelegate.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
                                    await MainActor.run {
                                        registrationMessage = response
                                    }
                                }
                            } else {
                                print("Device token not yet available")
                                DispatchQueue.main.async {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                        }
                    }
                } footer: {
                    if let message = registrationMessage {
                        let fullToken = appDelegate.notificationDelegate.currentDeviceToken ?? "Not found"
                        let shortToken: String = String(fullToken.suffix(4))
                        #if DEBUG
                        let environment = "Test"
                        #else
                        let environment = "Production"
                        #endif

                        let postText = "Device *\(shortToken), env \(environment)"
                        Text(message.status ?
                             "Registered successfully with frequency of ^[\(message.frequency ?? 1) hour](inflect:true). \(postText)" :
                            "Registered failed with \(message.message). \(postText)").foregroundStyle(.secondary)
                    }
                }
                
            }
            .navigationTitle("Background Sync")
            
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingJobSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: lunchMoneyApiSection
    private func lunchMoneyApiSection() -> some View {
        Section {
            NavigationLink {
                TokenPromptView(
                    isPresented: $showingTokenPrompt,
                    apiToken: $apiToken,
                    onSave: {
                        apiConnected = true
                    },
                    allowDismissal: true
                )
            } label: {
                HStack {
                    if isVerifyingToken {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: apiConnected ? "checkmark.icloud.fill" : "icloud.slash.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(apiConnected ? .green : .red)
                    }
                    VStack {
                        HStack {
                            if isVerifyingToken {
                                Text("Verifying Token...")
                            } else {
                                apiConnected ?
                                Text("Connected"):
                                Text("Not Connected")
                            }
                            Spacer()
                        }
                    }
                }
            }
            /*
            if isSimulator {
                NavigationLink {
                    APITestView()
                } label: {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                        Text("API Test")
                        Spacer()
                    }
                }
            }
            */
        } header: {
            Text("Lunch Money API")
        } footer: {
            if(apiConnected) {
                Text("Connected as \(userName)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: appleWalletSection
    private func appleWalletSection() -> some View {
        Section("Apple Wallet Accounts") {
            NavigationLink {
                AccountSelectionView(
                    isPresented: $isShowingAccountSelectionDialog,
                    onSave: refreshView,
                    allowDismissal: true,
                    wallet: wallet
                )
            } label: {
                HStack {
                    Image(systemName: walletsConnected>0 ? "checkmark.rectangle.fill" : "rectangle.on.rectangle.slash.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(walletsConnected>0 ? .green : .red)
                    VStack {
                        HStack {
                            walletsConnected>0 ?
                            Text("^[\(walletsConnected) Account](inflect:true) Connected"):
                            Text("None Connected")
                            Spacer()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: transactionSyncSection
    private func transactionSyncSection() -> some View {
        Section{
            NavigationLink {
                TransactionListView(wallet: wallet, syncStatus: .pending).onAppear {
                    refreshView()
                }
            } label: {
                HStack {
                    Image(systemName: "questionmark.app.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(pendingCount>0 ? .green : .gray)
                    VStack {
                        HStack {
                            Text("^[\(pendingCount) Transaction](inflect:true) Pending Sync")
                            Spacer()
                        }
                    }
                }
            }
            .disabled(pendingCount == 0)
            
            if(errorCount>0){
                NavigationLink {
                    TransactionListView(wallet: wallet, syncStatus: .never).onAppear {
                        refreshView()
                    }
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(errorCount>0 ? .red : .gray)
                        VStack {
                            HStack {
                                Text("^[\(errorCount) Transaction Sync Errors](inflect:true) ")
                                Spacer()
                            }
                        }
                    }
                }
                .disabled(errorCount == 0)
            }

            NavigationLink {
                TransactionListView(wallet: wallet, syncStatus: .complete).onAppear {
                    refreshView()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(completedCount>0 ? .green : .gray)
                    VStack {
                        HStack {
                            Text("^[\(completedCount) Transaction](inflect:true) Completed")
                            Spacer()
                        }
                    }
                }
            }
            .disabled(completedCount == 0)
        } header: {
            Text("Transactions")
        } footer: {
            NavigationLink {
                LogListView(wallet: wallet)
            } label: {
                Text("Last updated: \(lastUpdated.formatted(.relative(presentation: .named))), \(niceDateFormat(lastUpdated))")
                    .font(.subheadline)
            }
            .id(timeUpdateTrigger)
        }
    }
    
    private func niceDateFormat(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(date: .numeric, time: .shortened)
        }
    }
    
    // MARK: optionButtons
    private func optionButtons() -> some View {
        Section{
            
            Button {
                refreshWalletTransactions()
            } label: {
                HStack {
                    Image(systemName: "wallet.bifold")
                    Text("Get Latest Wallet Transactions")
                    Spacer()
                }
            }
            .disabled(walletsConnected < 1)
            
            Button {
                Task {
                    wallet.addLog(message: "importing \(pendingCount) transactions for \(walletsConnected) accounts", level: 2)
                    await importPendingTransactions()
                    updateBadgeCount()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync \(pendingCount) Transactions to Lunch Money")
                    Spacer()
                }
            }
            .disabled(pendingCount < 1)
            
            Button {
                showingJobSheet = true
            } label: {
                HStack {
                    Image(systemName: enableBackgroundJob ? "clock.badge.checkmark.fill" : "clock.badge.xmark.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(enableBackgroundJob ? .green : .gray)
                    Text("Background Sync")
                    Spacer()
                }
            }
        } header: {
            Text("Import Transactions")
        } footer: {
            if enableBackgroundJob {
                Text("A background task will check for new transactions every \(backgroundJobFrequencyText).").foregroundStyle(.secondary)
            }else{
                Text("No background sync currently scheduled").foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: automateButtons
    private func automateButtons() -> some View {
        Section {
            Button {
                showingJobSheet = true
            } label: {
                HStack {
                    Image(systemName: enableBackgroundJob ? "clock.badge.checkmark.fill" : "clock.badge.xmark.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(enableBackgroundJob ? .green : .red)
                    VStack(alignment: .leading) {
                        Text("Background Sync Settings")

                        if enableBackgroundJob {
                            Text("Enabled - Every \(backgroundJobFrequency == 0 ? "15 minutes" : backgroundJobFrequency == 1 ? "hour" : "\(backgroundJobFrequency * 6) hours")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        
        } header: {
            Text("Background Import")
        }
    }
    
    // MARK: import buttons
    private func importButtons() -> some View {
        Section{
            
            Button {
                Task {
                    // Disable the button while loading
                    showingPreviewTransactions = false
                    let accounts = wallet.getSyncedAccounts()
                    transactions = try await appleWallet.fetchhWalletTransactionsForAccounts(accounts: accounts)
                    
                    // Show preview only after transactions are loaded
                    showingPreviewTransactions = true
                }
            } label: {
                HStack {
                    Text("Review transactions for import")
                    Spacer()
                    Image(systemName: "arrow.down.circle.fill")
                }
            }
            .disabled(walletsConnected < 1 || showingPreviewTransactions)
            .sheet(isPresented: $showingPreviewTransactions) {
                PreviewTransactionsView(
                    transactions: transactions,
                    onImport: { selectedTransactions in
                        //print("selected for import: \(selectedTransactions.count)")
                        selectedTransactions.forEach { transaction in
                            wallet.replaceTransaction(newTrans: transaction)
                        }
                        refreshView()
                    }
                )
            }
        } header: {
            Text("Import Historical Transactions")
        } footer: {
            Text("See a list of transactions by month from your Wallet to import into Lunch Money").foregroundStyle(.secondary)
        }
        
    }
    
    // MARK: refreshView
    private func refreshView(){
        //print("refreshView")
        completedCount = wallet.getTransactionsWithStatus([.complete]).count
        pendingCount = wallet.getTransactionsWithStatus(.pending).count
        errorCount = wallet.getTransactionsWithStatus(.never).count
        walletsConnected = wallet.getSyncedAccounts().count
        updateBadgeCount()
        updateLastUpdated()
    }
    
    // MARK: importPendingTransactions
    private func importPendingTransactions() async {
        guard !isSyncing else { return }

        await MainActor.run {
            isSyncing = true
            syncError = nil
            showingSyncProgress = true
            syncProgress = Wallet.SyncProgress(current: 0, total: pendingCount, status: "Starting sync...")
        }
        
        do {
            let syncBroker = SyncBroker(context: modelContext)
            try await syncBroker.syncTransactions(prefix: "MV", shouldContinue: { @MainActor in 
                isSyncing 
            }) { @MainActor progress in
                syncProgress = progress
            }
            await MainActor.run {
                refreshView()
                updateBadgeCount()
                isSyncing = false
                showingSyncProgress = false
            }
        } catch {
            await MainActor.run {
                syncError = "Failed to sync: \(error.localizedDescription)"
                isSyncing = false
                showingSyncProgress = false
            }
        }
    }
    
    // MARK: refreshWalletTransactions
    private func refreshWalletTransactions() {
        let syncBroker = SyncBroker(context: modelContext)
        Task {
            do {
                _ = try await syncBroker.fetchTransactions(prefix: "MV", andSync: false, showAlert: true) { progressMessage in
                    //print("refreshWalletTransactions Progress: \(progressMessage)")
                }
                //print("refreshWalletTransactions Completed with \(pendingCount) pending transactions")
            } catch {
                print("Error: \(error)")
            }
        }
    }

    // MARK: utility functions
    private func updateBadgeCount() {
        NotificationCenter.default.post(
            name: .pendingTransactionsChanged,
            object: pendingCount
        )
    }
        
    private func checkForStoredToken() {
        //print("checkForStoredToken")
        if let storedToken = try? keychain.retrieveTokenFromKeychain() {
            apiToken = storedToken
        }
    }
    
    private func checkApiToken() {
        //print("checkApiToken")
        if apiConnected {
            return
        }
        Task {
            await MainActor.run {
                isVerifyingToken = true
            }
            do {
                userName = try await wallet.getAPIAccountName()
                await MainActor.run {
                    apiConnected = true
                    isVerifyingToken = false
                }
            } catch {
                await MainActor.run {
                    userName = "Not Authenticated"
                    isVerifyingToken = false
                }
            }
        }
    }
    
    private func updateLastUpdated() {
        //print("updateLastUpdated()")
        var descriptor = FetchDescriptor<Log>(
            predicate: #Predicate<Log> { log in
                log.level == 1
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        if let mostRecentLog = try? modelContext.fetch(descriptor).first {
            lastUpdated = mostRecentLog.date
            //print("updateLastUpdated() got \(lastUpdated)")
        } else {
            lastUpdated = Date()
            //print("updateLastUpdated() failed")
        }
    }
    
}


// MARK: preview
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Transaction.self,
        Account.self,
        Log.self,
        Item.self
    ])
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    MainView(context: context, appDelegate: AppDelegate())
        .modelContainer(container)
}
