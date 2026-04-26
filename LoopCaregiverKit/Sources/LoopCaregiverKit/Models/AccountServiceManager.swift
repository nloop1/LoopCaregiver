//
//  AccountServiceManager.swift
//
//
//  Created by Bill Gestrich on 5/11/22.
//

import Foundation
import LoopKit

public class AccountServiceManager: ObservableObject, AccountServiceDelegate, AccountService {
    public typealias RemoteServicesProviderFactory = (_: Looper, _: CaregiverSettings) -> any RemoteDataServiceProvider
    public weak var delegate: AccountServiceDelegate?

    // Account Service
    @Published public var loopers: [Looper] = []
    @Published public private(set) var selectedLooper: Looper?
    @Published public var selectedLooperService: LooperService?
    @Published public var settings: CaregiverSettings
    private var accountService: AccountService
    private let remoteServicesProviderFactory: RemoteServicesProviderFactory
    public let pendingCommandWatcher: PendingCommandWatcher?

    public init(accountService: AccountService, settings: CaregiverSettings, remoteServicesProviderFactory: RemoteServicesProviderFactory? = nil, pendingCommandWatcher: PendingCommandWatcher? = nil) {
        self.accountService = accountService
        self.settings = settings
        self.pendingCommandWatcher = pendingCommandWatcher

        if let remoteServicesProviderFactory {
            self.remoteServicesProviderFactory = remoteServicesProviderFactory
        } else {
            self.remoteServicesProviderFactory = { factoryLooper, factorySettings in
                return NightscoutDataSource(looper: factoryLooper, settings: factorySettings)
            }
        }

        refreshSync()
        accountService.delegate = self
    }

    public func createLooperService(looper: Looper) -> LooperService {
        let remoteDataSource = remoteServicesProviderFactory(looper, settings)
        let manager = RemoteDataServiceManager(remoteDataProvider: remoteDataSource, pendingCommandWatcher: pendingCommandWatcher)
        manager.monitorForUpdates()
        return LooperService(looper: looper,
                             remoteDataSource: manager
        )
    }

    // MARK: Account Service

    public func getLoopers() throws -> [Looper] {
        return try accountService.getLoopers()
    }

    public func updateActiveLoopUser(_ looper: Looper) throws {
        try accountService.updateActiveLoopUser(looper)
    }

    public func addLooper(_ looper: Looper) throws {
        try accountService.addLooper(looper)
    }

    public func removeLooper(_ looper: Looper) throws {
        try accountService.removeLooper(looper)
    }

    public func removeAllLoopers() throws {
        for looper in loopers {
            try removeLooper(looper)
        }
    }

    // Helpers

    func refresh() {
        // TODO: This dispatch async is to prevent SwiftUI triggering this causes recursive updates.
        DispatchQueue.main.async {
            self.refreshSync()
        }
    }

    func refreshSync() {
        do {
            self.loopers = try accountService.getLoopers()
                .sorted(by: { $0.name < $1.name })
            self.selectedLooper = self.loopers.max(by: { $0.lastSelectedDate < $1.lastSelectedDate })
            if let selectedLooper {
                selectedLooperService = createLooperService(looper: selectedLooper)
            } else {
                selectedLooperService = nil
            }
        } catch {
            self.selectedLooper = nil
            self.loopers = []
            self.selectedLooperService = nil
            print("Error fetching loopers: \(error)")
        }
    }

    // MARK: PersistenceControllerDelegate

    public func accountServiceDataUpdated(_ service: AccountService) {
        self.refresh()
    }
}

public extension AccountServiceManager {
    // For debugging, this uses a local file on your mac to populate a user on an iPhone Simulator
    func simulatorCredentials() -> NightscoutCredentials? {
        // The NSSearchPathForDirectoriesInDomains only returns the Desktop path in the
        // app container, not the mac. So this must be hardcoded to your local file.
        let jsonFileURL = URL(filePath: "/Users/bill/Desktop/Loop/loopcaregiver-test.json")

        guard FileManager.default.fileExists(atPath: jsonFileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: jsonFileURL) else {
            return nil
        }

        guard let credentials = try? JSONDecoder().decode(NightscoutCredentials.self, from: data) else {
            return nil
        }

        return NightscoutCredentials(url: credentials.url.absoluteURL, secretKey: credentials.secretKey, otpURL: credentials.otpURL)
    }
}
