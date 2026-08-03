/*
 updated 7/8/25, added SettingsView
 */
import SwiftUI
import SwiftData
import FinanceKit
import BackgroundTasks
import os
import StoreKit
import InAppSupport

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var wallet: Wallet
    
    @State private var apiConnected = false
    // Mirror-only mode (valid mirror URL, no LM token): the UI stays usable
    // without a Lunch Money connection. Recomputed in refreshView().
    @State private var mirrorOnlyActive = false
    @State private var showingTokenPrompt = false
    @State private var showingAccountView = false
    @State private var isShowingAccountSelectionDialog = false
    @State private var apiToken = ""
    @State private var walletsConnected = 0
    @State private var pendingCount = 0
    @State private var errorCount = 0
    @State private var completedCount = 0
    @State private var uncategorizedCount = 0
    @State private var isSyncing = false
    @State private var syncError: String?
    
    @State private var user: User?
    //@State private var userName: String = "Loading..."
    //@State private var budgetName: String = ""
    
    private let keychain = Keychain()
    @State private var appleWallet: AppleWallet
    @State private var showingPreviewTransactions = false
    @State private var transactions: [Transaction] = []
    @State private var syncProgress: SyncBroker.SafeSyncProgress?
    @State private var showingSyncProgress = false
    
    @State private var lastUpdated = Date() //.addingTimeInterval(-10*60) //(-365 * 24 * 60 * 60)

    @AppStorage("enableBackgroundJob", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var enableBackgroundJob = false
    @AppStorage("autoImportTransactions", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var autoImportTransactions = false
    @AppStorage("backgroundJobFrequency", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var backgroundJobFrequency: Int = 1
    @AppStorage("enableBackgroundDelivery", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var enableBackgroundDelivery = false
    @AppStorage("categorize_incoming", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var categorize_incoming = true
    @AppStorage("is_test_flight", store: UserDefaults(suiteName: "group.com.littlebluebug.AppleCardSync")) private var is_test_flight = false
    
    
    @State private var showingJobSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingCategorySheet = false
    @State private var showingHelpSheet = false

    @ObservedObject private var feedbackService = FeedbackService.shared

    @StateObject private var announcementStore = AnnouncementStore()
    @State private var showingAnnouncements = false

    private let appDelegate: AppDelegate

    @State private var timeUpdateTimer: Timer? = nil
    @State private var timeUpdateTrigger = Date()
    @State private var refreshTrigger = UUID()

    @State private var isVerifyingToken = false

    @State private var isSimulator = false

    @State private var registrationMessage: PushRegistrationResponse?
    var logger: Logger!
    
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
        
        if( Utility.isMockEnvironment() ){
            let wallet = MockWallet(context: context, apiToken: "mock-token")
            _wallet = StateObject(wrappedValue: wallet)
            _appleWallet = State(initialValue: MockAppleWallet())
        }else{
            let wallet = Wallet(context: context, apiToken: initialToken)
            _wallet = StateObject(wrappedValue: wallet)
            _appleWallet = State(initialValue: AppleWallet())
        }
        
        _apiToken = State(initialValue: initialToken)
        _transactions = State(initialValue: [])
        
        //print("MainView init with enable=\(enableBackgroundJob) and freq=\(backgroundJobFrequency)")
        
        #if targetEnvironment(simulator)
        _isSimulator = State(initialValue: true)
        #endif
        
        logger = Logger(subsystem: "com.littlebluebug.AppleCardSync", category: "MainView")
        
        
    }
    
    private let storage = Storage()
    
    // MARK: main view body
    var body: some View {
        NavigationStack() {
            VStack {
                List {
                    lunchMoneyApiSection()
                    if(apiConnected || mirrorOnlyActive) {
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
                    await setIsTestFlight()
                    await feedbackService.refresh()
                }

            }
            .onAppear {
                refreshView()
                refreshTrigger = UUID()
            }
            .task {
                refreshView()
                await feedbackService.refresh()
            }
            .navigationTitle("Lunch Sync")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Snapshot before the sheet covers the screen, so the
                        // composer can offer the screen the user was just on.
                        FeedbackScreenSnapshot.shared.capture()
                        showingHelpSheet = true
                    } label: {
                        // The dot is an overlay *on the symbol* rather than a
                        // sibling in a ZStack: as a sibling the toolbar's glass
                        // pass draws the symbol back over it and the dot reads
                        // as if it were behind the icon.
                        Image(systemName: "questionmark.bubble")
                            .overlay(alignment: .topTrailing) {
                                if feedbackService.unreadCount > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 9, height: 9)
                                        .offset(x: 4, y: -4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .accessibilityLabel(
                        feedbackService.unreadCount > 0
                            ? "Help & Feedback, \(feedbackService.unreadCount) unread"
                            : "Help & Feedback"
                    )
                }

                if(categorize_incoming){
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingCategorySheet = true
                        } label: {
                            // Same overlay-on-the-symbol treatment as the help
                            // badge above, for the same reason.
                            Image(systemName: "tag")
                                .overlay(alignment: .topTrailing) {
                                    if uncategorizedCount > 0 {
                                        Text("\(uncategorizedCount)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -8)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingJobSheet) {
                backgroundSyncSheet()
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView(isPresented: $showingSettingsSheet)
            }
            .sheet(isPresented: $showingCategorySheet) {
                NavigationStack {
                    CategoryView(context: modelContext, appDelegate: appDelegate)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingCategorySheet = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .onDisappear {
                    refreshTrigger = UUID()
                }
            }
            .sheet(isPresented: $showingHelpSheet) {
                NavigationStack {
                    FeedbackHomeView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingHelpSheet = false
                                }
                            }
                        }
                }
                .presentationDetents([.large])
                .onDisappear {
                    FeedbackScreenSnapshot.shared.clear()
                    // Threads read inside the sheet clear their unread flag
                    // server-side; resync so the header dot matches.
                    Task { await feedbackService.refresh() }
                }
            }
        }.navigationTitle("Lunch Sync")
        .onAppear {
            checkApiToken()
            checkAnnouncements()
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
            setBackgroundDelivery(enabled: enableBackgroundDelivery)
            checkAnnouncements()
            // Support replies land while we're backgrounded; the header dot is
            // only as fresh as the last list_conversations call, and .task
            // above runs once per view lifetime. Re-poll on every foreground.
            Task { await feedbackService.refresh() }
        }
        .onChange(of: refreshTrigger) { _, _ in
            refreshView()
        }
        .sheet(isPresented: $showingAnnouncements, onDismiss: {
            announcementStore.markUnseenAsRead()
        }) {
            AnnouncementsView(announcements: announcementStore.unseen) {
                showingAnnouncements = false
            }
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
    
    // MARK: setBackgroundDelivery
    private func setBackgroundDelivery(enabled: Bool){        
        if #available(iOS 26.0, *) {
            if enabled {
                FinanceStore.shared.enableBackgroundDelivery(for: [.transactions, .accounts, .accountBalances], frequency: .hourly)
                //wallet.addLog(message: "MV: BackgroundDelivery enabled", level: 2)
            }else{
                FinanceStore.shared.disableBackgroundDelivery(for: [.transactions, .accounts, .accountBalances])
                //wallet.addLog(message: "MV: BackgroundDelivery disabled", level: 1)
            }
        }else{
            //wallet.addLog(message: "MV: setBackgroundDelivery not available on this OS \(enabled)", level: 1)
        }
    }
    
    private func backgroundSyncSheet() -> some View {
        NavigationStack {
            List {
                
                Section {
                    
                    Toggle("Enable background sync", isOn: $enableBackgroundJob.animation())
                        .disabled(walletsConnected < 1)
                        .onChange(of: enableBackgroundJob) { _, newValue in
                            if !newValue {
                                if let token = appDelegate.notificationDelegate.currentDeviceToken {
                                    Task {
                                        let response = await PushAPI.registerForPushNotifications(deviceToken: token, active: false, frequency: backgroundJobFrequency)
                                        await MainActor.run {
                                            registrationMessage = response
                                        }
                                    }
                                } else {
                                    print("Device token not yet available (Enable background sync)")
                                    DispatchQueue.main.async {
                                        UIApplication.shared.registerForRemoteNotifications()
                                    }
                                }
                            } else {
                                if let token = appDelegate.notificationDelegate.currentDeviceToken {
                                    Task {
                                        let response = await PushAPI.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
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
                                    let response = await PushAPI.registerForPushNotifications(deviceToken: token, active: true, frequency: backgroundJobFrequency)
                                    await MainActor.run {
                                        registrationMessage = response
                                    }
                                }
                            } else {
                                print("Device token not yet available (enableBackgroundJob)")
                                DispatchQueue.main.async {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                        }
                    }
                    
                    
                
                } footer: {
                    
                    VStack{
                        Text("Background Sync sends a push notification to trigger a sync, at a frequency you select.")
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                                "Registered failed with \(message.message). \(postText)").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if #available(iOS 26.0, *) {
                    Section{
                        Toggle("Enable background delivery", isOn:$enableBackgroundDelivery.animation())
                            .onChange(of:enableBackgroundDelivery){ _, newValue in
                                if !newValue {
                                    setBackgroundDelivery(enabled: false)
                                }else{
                                    setBackgroundDelivery(enabled: true)
                                }
                            }
                    } footer: {
                        Text("Background Delivery syncs when a transaction happens in real time, up to once per hour.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Section{
                    Toggle("Import Transactions Automatically", isOn: $autoImportTransactions)
                        .disabled(walletsConnected < 1)
                }footer: {
                    Text("Send transactions to LunchMoney after a sync. Leave off to import manually.")
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .presentationDetents([.fraction(0.7), .large])
    }
    
    // MARK: checkAnnouncements
    private func checkAnnouncements() {
        announcementStore.checkForUnseen(freshInstall: apiToken.isEmpty)
        guard !announcementStore.unseen.isEmpty else { return }
        // Don't fight another sheet for the presentation slot
        if !showingJobSheet && !showingSettingsSheet && !showingCategorySheet
            && !showingSyncProgress && !showingPreviewTransactions {
            showingAnnouncements = true
        }
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
                .onDisappear {
                    handleTokenPromptDismiss()
                }
            } label: {
                HStack {
                    if isVerifyingToken {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: (apiConnected || mirrorOnlyActive) ? "checkmark.icloud.fill" : "icloud.slash.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle((apiConnected || mirrorOnlyActive) ? .green : .red)
                    }
                    VStack {
                        HStack {
                            if isVerifyingToken {
                                Text("Verifying Token...")
                            }else if(apiConnected){
                                VStack{
                                    HStack{
                                        Text("\(user?.userName ?? "Not authenticated")")
                                        Spacer()
                                    }
                                    HStack{
                                        Text("\(user?.budgetName ?? "")").font(.caption)
                                        Spacer()
                                    }
                                }

                            } else if(mirrorOnlyActive) {
                                Text("Mirror only — Lunch Money disabled")
                            } else {
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
        }
        /*header: {
            Text("Lunch Money Account")
        }*/
        /*footer: {
            if(apiConnected) {
                Text("Connected as \(userName)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
         */
    }
    
    // MARK: appleWalletSection
    private func appleWalletSection() -> some View {
        Section("Wallet Accounts") {
            NavigationLink {
                AccountSelectionView(
                    isPresented: $isShowingAccountSelectionDialog,
                    onSave: {
                        refreshView()
                        refreshTrigger = UUID()
                    },
                    allowDismissal: true,
                    wallet: wallet
                )
                .onDisappear {
                    refreshTrigger = UUID()
                }
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
            // "Pending Sync" means pending for Lunch Money; hidden in
            // mirror-only mode where nothing is ever pushed there.
            if !mirrorOnlyActive {
                NavigationLink {
                    TransactionListView(wallet: wallet, syncStatus: .pending)
                        .onDisappear {
                            refreshTrigger = UUID()
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
            }

            if(errorCount>0){
                NavigationLink {
                    TransactionListView(wallet: wallet, syncStatus: .never)
                        .onDisappear {
                            refreshTrigger = UUID()
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
                TransactionListView(wallet: wallet, syncStatuses: [.complete, .skipped])
                    .onDisappear {
                        refreshTrigger = UUID()
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
            
            // No Lunch Money pushes in mirror-only mode; the mirror POST
            // happens as part of "Get Latest Wallet Transactions".
            if !mirrorOnlyActive {
                Button {
                    Task {
                        wallet.addLog(message: "MV: importing \(pendingCount) transactions for \(walletsConnected) accounts", level: 1)
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
            }

            Button {
                showingJobSheet = true
            } label: {
                HStack {
                    Image(systemName: (enableBackgroundJob || enableBackgroundDelivery) ? "clock.badge.checkmark.fill" : "clock.badge.xmark.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle((enableBackgroundJob || enableBackgroundDelivery) ? .green : .gray)
                    Text("Background Sync")
                    Spacer()
                }
            }
        } header: {
            Text("Import Transactions")
        } footer: {
            if enableBackgroundJob {
                Text("A background task will check for new transactions every \(backgroundJobFrequencyText).").foregroundStyle(.secondary)
            }else if(enableBackgroundDelivery){
                Text("Background delivery is enabled.").foregroundStyle(.secondary)
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
                    transactions = try await appleWallet.fetchhWalletTransactionsForAccounts(accounts: accounts, logPrefix:"MV")
                    
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
                        var inserted = 0
                        var requeued = 0
                        var unchanged = 0
                        selectedTransactions.forEach { transaction in
                            switch wallet.replaceTransaction(newTrans: transaction) {
                            case .insertedNew: inserted += 1
                            case .requeued: requeued += 1
                            case .unchanged: unchanged += 1
                            }
                        }
                        wallet.addLog(message: "bulk import: staged \(inserted) new, \(requeued) changed for sync; \(unchanged) of \(selectedTransactions.count) selected already up to date", level: 1)
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
        mirrorOnlyActive = MirrorAPI.isMirrorOnly(apiTokenEmpty: apiToken.isEmpty)
        completedCount = wallet.getTransactionsWithStatus([.complete]).count
        pendingCount = wallet.getTransactionsWithStatus(.pending).count
        errorCount = wallet.getTransactionsWithStatus(.never).count
        walletsConnected = wallet.getSyncedAccounts().count
        
        // Count uncategorized TrnCategory objects
        let fetchDescriptor = FetchDescriptor<TrnCategory>(
            predicate: #Predicate<TrnCategory> { $0.lm_id == "" }
        )
        uncategorizedCount = (try? modelContext.fetch(fetchDescriptor).count) ?? 0
        
        updateBadgeCount()
        updateLastUpdated()
    }
    
    private func setIsTestFlight() async{
        
        var isTestFlight: Bool {
            get async {
                do {
                    let appTransaction = try await AppTransaction.shared
                    switch appTransaction {
                    case .verified(let transaction):
                        // TestFlight builds will have a sandbox environment
                        return transaction.environment == .sandbox
                    case .unverified:
                        return false
                    }
                } catch {
                    return false
                }
            }
        }
        is_test_flight = await isTestFlight
    }
    
    // MARK: importPendingTransactions
    private func importPendingTransactions() async {
        guard !isSyncing else { return }

        await MainActor.run {
            isSyncing = true
            syncError = nil
            showingSyncProgress = true
            syncProgress = SyncBroker.SafeSyncProgress(current: 0, total: pendingCount, status: "Starting sync...")
        }
        
        do {
            let syncBroker = SyncBroker(context: modelContext, logPrefix: "MV")
            try await withBackgroundAssertion("importPendingTransactions") {
                try await syncBroker.syncTransactions(prefix: "MV", shouldContinue: {
                    isSyncing
                }) { progress in
                    syncProgress = progress
                }
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
                try await withBackgroundAssertion("refreshWalletTransactions") {
                    let preFetchedWalletData = try await appleWallet.getPreFetchedWalletData(logPrefix: "MV")
                    _ = try await syncBroker.fetchTransactions(
                        prefix: "MV",
                        showAlert: true,
                        skipSync: true,
                        progress: { progressMessage in
                            //print("refreshWalletTransactions Progress: \(progressMessage)")
                        },
                        preFetchedWalletData: preFetchedWalletData
                    )
                }
                //print("refreshWalletTransactions Completed with \(pendingCount) pending transactions")
                refreshView()
            } catch {
                print("Error: \(error)")
            }
        }
    }

    // MARK: utility functions
    private func updateBadgeCount() {
        let finalPendingCount = wallet.getTransactionsWithStatus(.pending).count
        let fetchDescriptor = FetchDescriptor<TrnCategory>(
            predicate: #Predicate<TrnCategory> { $0.lm_id == "" }
        )
        let uncategorizedCount = (try? modelContext.fetch(fetchDescriptor).count) ?? 0
        let count = finalPendingCount + (categorize_incoming ? uncategorizedCount : 0)
        //print("MainView: Setting badge count to \(count)")
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Error setting badge count: \(error)")
            }
        }
    }
        
    private func checkForStoredToken() {
        //print("checkForStoredToken")
        if let storedToken = try? keychain.retrieveTokenFromKeychain() {
            apiToken = storedToken
        }
    }
    
    private func checkApiToken() {
        if apiConnected {
            return
        }
        // Mirror-only with no token: nothing to verify against Lunch Money.
        if apiToken.isEmpty && MirrorAPI.isMirrorOnly(apiTokenEmpty: true) {
            return
        }
        Task {
            await MainActor.run {
                isVerifyingToken = true
            }
            do {
                user = try await wallet.getAPIAccount()
                await MainActor.run {
                    apiConnected = true
                    isVerifyingToken = false
                }
            } catch {
                await MainActor.run {
                    //userName = "Not Authenticated"
                    isVerifyingToken = false
                }
            }
        }
    }
    
    private func handleTokenPromptDismiss() {
        // Re-verify token and refresh counts when returning from TokenPromptView
        let keychain = Keychain()
        var initialToken = ""
        do{
           initialToken = try keychain.retrieveTokenFromKeychain()
        } catch {
           initialToken = ""
        }        
        wallet.updateAPIToken(initialToken)
        apiConnected = false
        user = nil
        checkApiToken()
        refreshView()
        // Nudge any dependent views to refresh
        refreshTrigger = UUID()
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

// MARK: background assertions
// Sync and wallet refresh write to the CloudKit-backed store. If iOS suspends
// the app while a write is in flight, RunningBoard kills it (0xdead10cc), so
// hold a background task assertion for the duration of the work.
@MainActor
private func beginBackgroundAssertion(_ name: String) -> UIBackgroundTaskIdentifier {
    UIApplication.shared.beginBackgroundTask(withName: name)
}

@MainActor
private func endBackgroundAssertion(_ identifier: UIBackgroundTaskIdentifier) {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
}

private func withBackgroundAssertion<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
    let identifier = await beginBackgroundAssertion(name)
    do {
        let result = try await work()
        await endBackgroundAssertion(identifier)
        return result
    } catch {
        await endBackgroundAssertion(identifier)
        throw error
    }
}

// MARK: preview
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Transaction.self,
        Account.self,
        Log.self,
        Item.self,
        LMCategory.self,
        TrnCategory.self,
        TransactionHistory.self
    ])
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = container.mainContext
    
    MainView(context: context, appDelegate: AppDelegate())
        .modelContainer(container)
}

