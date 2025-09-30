# LunchSync

Automatically sync your Apple Wallet transactions to Lunch Money. LunchSync is an iOS app that seamlessly connects your Apple Wallet with your Lunch Money account, making personal finance management easier than ever.

Official site: https://littlebluebug.com/wallet/index.html

Lunch Sync is now available on the App Store: https://apps.apple.com/us/app/lunch-sync/id6739702427

Lunch Sync is available for testing through Test Flight here: https://testflight.apple.com/join/mF8JEHqk

## Features
- Automatic syncing of Apple Wallet transactions to Lunch Money
- Support for multiple Apple Wallet accounts
- Real-time balance updates
- Background sync with customizable frequency (1 hour to 24 hours)
- Secure API token storage using Keychain
- Native iOS app with SwiftUI interface

## Technical Overview

### How it works
- The user enters a LunchMoney API token, giving access to read and write data to LunchMoney
- The app requests authorization to access the FinanceStore (AppleWallet.requestAuth)
- The user selects Apple Wallet accounts to access
- The user selects LunchMoney Assets (accounts) to pair Apple Wallet accounts with, or creates a new Asset to pair
- The SyncBroker's fetchTransactions function checks for transactions and syncs them to LunchMoney using the LunchMoneyAPI class. 
- As new transactions are identified in the Apple Wallet, they are copied to local SwiftData Transaction objects. 
-- Transaction.SyncStatus indicates if the transaction has been synced.
- A Sync can be triggered one of three ways:
-- Manually, by tapping "Get Latest Wallet Transactions" and then "Sync [number] Transactions to Lunch Money"
-- Automatically in the background, by enabling Background Sync. This reigsters the device's notification token with https://push.littlebluebug.com/register.php. Push notifications are then sent on the desired frequency through APNS, triggering a sync.
-- Using an iOS Shortcut
- During sync, a Lunch Money transaction is created for each local Transaction. The Apple Wallet transaction id is stored in the Lunch Money Transaction.external_id. If a Lunch Money transaction with a matching external_id is found, the transaction is updated.

### Known issues
- Only Apple credit, cash and savings accounts are supported.
- Transactions are not marked "Pending". LunchMoney doesn't allow modification or deletion of pending transactions, so "pending" is stored in the transaction note.
- Duplicates are detected in a 60 day window around a transaction, as Lunch Money's API doesn't allow searching on external id.
- Background Tasks (BGTaskScheduler) were dropped in favor of Push Notifications as they were not reliable enough.

### Core Components

#### `Wallet` Class
The central manager class that handles transaction syncing and data persistence:
- Manages transaction syncing between Apple Wallet and Lunch Money
- Handles local storage of transactions using SwiftData
- Provides methods for CRUD operations on transactions and accounts
- Manages sync status and progress reporting

#### `LunchMoneyAPI` Class
Handles all communication with the Lunch Money API:
- Implements RESTful API calls to Lunch Money's endpoints
- Manages authentication using API tokens
- Handles transaction creation, updates, and deletions
- Provides methods for account management and balance updates

#### `AppleWallet` Class
Interfaces with Apple's FinanceKit framework:
- Fetches transactions from Apple Wallet
- Manages authorization and access to financial data
- Provides real-time updates for new transactions
- Handles account balance synchronization

#### `SyncBroker` Class
Orchestrates the synchronization process:
- Manages the flow of data between Apple Wallet and Lunch Money
- Handles background sync scheduling
- Provides progress updates and error handling
- Manages notification delivery for sync events

### Data Models

#### `Transaction`
Represents a financial transaction with properties:
- `id`: Unique identifier
- `account`: Associated account name
- `payee`: Transaction recipient/sender
- `amount`: Transaction amount
- `date`: Transaction date
- `lm_id`: Lunch Money transaction ID
- `sync`: Sync status (pending/complete/error)

#### `Account`
Represents a financial account with properties:
- `id`: Unique identifier
- `name`: Account name
- `balance`: Current balance
- `lm_id`: Lunch Money asset ID
- `institution_name`: Bank/institution name
- `sync`: Sync status

### Key Features Implementation

#### Background Sync (currently unused)
- Uses `BGTaskScheduler` for periodic updates
- Configurable sync intervals (1-24 hours)
- Push notification support for sync status
- Battery-efficient background processing

#### Security
- Keychain integration for secure token storage
- FinanceKit authorization for secure wallet access
- Secure HTTPS communication with Lunch Money API
- Local data persistence using SwiftData

#### User Interface
- Built with SwiftUI for modern iOS UI
- Reactive updates using Combine framework
- Progress tracking and error reporting
- Account management and sync configuration

## Requirements

- iOS device (iPhone or iPad)
- Apple Wallet with transactions
- Lunch Money account with API access
- iOS 15.0 or later

## Setup

1. Download and install LunchSync from the Test Flight link: https://testflight.apple.com/join/mF8JEHqk
2. Get your Lunch Money API token from [my.lunchmoney.app/developers](https://my.lunchmoney.app/developers)
3. Launch LunchSync and enter your API token
4. Grant access to Apple Wallet when prompted
5. Select which accounts you want to sync
6. Optional: Enable background sync for automatic updates

## Privacy & Security

- Your Lunch Money API token is securely stored in the iOS Keychain
- Apple Wallet access is handled through Apple's FinanceKit framework
- No transaction data is stored on or transmitted to external servers
- All syncing happens directly between your device and Lunch Money's servers
- Push notifications are coordinated from https://push.littlebluebug.com. Only the device's unique notification token is transmitted to this url.

## Support

For issues, feature requests, or contributions, please contact support@littlebluebug.com


