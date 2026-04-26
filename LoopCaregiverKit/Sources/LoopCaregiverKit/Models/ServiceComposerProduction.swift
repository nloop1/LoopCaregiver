//
//  ServiceComposerProduction.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 10/15/23.
//

import Foundation
import OSLog

public class ServiceComposerProduction: ServiceComposer {
    public let settings: CaregiverSettings
    public let accountServiceManager: AccountServiceManager
    public let watchService: WatchService
    public let deepLinkHandler: DeepLinkHandler
    public let notificationService: LocalNotificationService
    public let pendingCommandWatcher: PendingCommandWatcher
    private let defaultLog = Logger()

    public init() {
        defaultLog.log("Initializing ServiceComposerProduction for bundle: \(Bundle.main.bundlePath)")
        let userDefaults = Self.createUserDefaults()
        self.settings = Self.createCaregiverSettings(userDefaults: userDefaults)
        let notificationService = LocalNotificationService()
        self.notificationService = notificationService
        let pendingCommandWatcher = PendingCommandWatcher(notificationService: notificationService)
        self.pendingCommandWatcher = pendingCommandWatcher
        self.accountServiceManager = Self.createAccountServiceManager(settings: settings, pendingCommandWatcher: pendingCommandWatcher)
        self.watchService = Self.createWatchService(accountServiceManager: accountServiceManager)
        self.deepLinkHandler = Self.createDeepLinkHandler(accountServiceManager: accountServiceManager, settings: settings, watchService: watchService)
    }

    static func createCaregiverSettings(userDefaults: UserDefaults) -> CaregiverSettings {
        let appGroupsSupported = Self.appGroupName() != nil
        return CaregiverSettings(userDefaults: userDefaults, appGroupsSupported: appGroupsSupported)
    }

    static func createPersistentContainerFactory() -> PersistentContainerFactory {
        if let appGroupName = appGroupName() {
            return AppGroupPersisentContainerFactory(appGroupName: appGroupName)
        } else {
            return NoAppGroupsPersistentContainerFactory()
        }
    }

    static func createUserDefaults() -> UserDefaults {
        if let appGroupName = appGroupName() {
            return UserDefaults(suiteName: appGroupName)!
        } else {
            return UserDefaults.standard
        }
    }

    static func createAccountServiceManager(settings: CaregiverSettings, pendingCommandWatcher: PendingCommandWatcher) -> AccountServiceManager {
        let containerFactory = Self.createPersistentContainerFactory()
        return AccountServiceManager(accountService: CoreDataAccountService(containerFactory: containerFactory), settings: settings, pendingCommandWatcher: pendingCommandWatcher)
    }

    static func createWatchService(accountServiceManager: AccountServiceManager) -> WatchService {
        return WatchService(accountService: accountServiceManager)
    }

    static func createDeepLinkHandler(accountServiceManager: AccountServiceManager, settings: CaregiverSettings, watchService: WatchService) -> DeepLinkHandler {
#if os(iOS)
        return DeepLinkHandlerPhone(accountService: accountServiceManager, settings: settings, watchService: watchService)
#elseif os(watchOS)
        return DeepLinkHandlerWatch(accountService: accountServiceManager, settings: settings, watchService: watchService)
#else
        return DeepLinkHandlerPhone(accountService: accountServiceManager, settings: settings, watchService: watchService)
        queuedFatalError("Unsupported platform")
#endif
    }

    static func appGroupName() -> String? {
        guard let appGroupName = Bundle.main.appGroupSuiteName, FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) != nil else {
            return nil
        }

        return appGroupName
    }
}
