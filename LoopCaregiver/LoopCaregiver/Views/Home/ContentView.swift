//
//  ContentView.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 11/12/22.
//

import LoopCaregiverKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var accountService: AccountServiceManager
    var deepLinkHandler: DeepLinkHandler
    @EnvironmentObject var settings: CaregiverSettings
    @EnvironmentObject var watchService: WatchService
    @EnvironmentObject var notificationService: LocalNotificationService

    @State private var deepLinkErrorShowing = false
    @State private var deepLinkErrorText: String = ""

    var body: some View {
        return Group {
            if let looperService = accountService.selectedLooperService {
                HomeView(
                    looperService: looperService,
                    accountService: accountService,
                    settings: settings,
                    watchService: watchService
                )
            } else {
                FirstRunView(accountService: accountService, settings: settings)
            }
        }.onOpenURL(perform: { url in
            Task {
                do {
                    try await deepLinkHandler.handleDeepLinkURL(url)
                } catch {
                    deepLinkErrorShowing = true
                    deepLinkErrorText = error.localizedDescription
                }
            }
        })
        .alert(deepLinkErrorText, isPresented: $deepLinkErrorShowing) {
            Button(role: .cancel) {
            } label: {
                Text("OK")
            }
        }
        .background(AppExpirationAlerterRepresentable())
        .task {
            if settings.remoteCommands2Enabled {
                _ = await notificationService.requestAuthorizationIfNeeded()
            }
        }
    }
}
