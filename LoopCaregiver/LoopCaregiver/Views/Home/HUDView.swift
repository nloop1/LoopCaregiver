//
//  HUDView.swift
//  LoopCaregiver
//
//  Created by Bill Gestrich on 11/17/22.
//

import Combine
import HealthKit
import LoopCaregiverKit
import LoopCaregiverKitUI
import LoopKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var hudViewModel: HUDViewModel
    @ObservedObject var nightscoutDataSource: RemoteDataServiceManager
    @ObservedObject private var settings: CaregiverSettings
    @State private var looperPopoverShowing = false
    
    init(looperService: LooperService, accountService: AccountServiceManager, settings: CaregiverSettings) {
        self.hudViewModel = HUDViewModel(
            selectedLooper: looperService.looper,
            accountService: accountService,
            settings: settings
        )
        self.nightscoutDataSource = looperService.remoteDataSource
        self.settings = settings
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                CurrentGlucoseComboView(glucoseSample: nightscoutDataSource.currentGlucoseSample, lastGlucoseChange: lastGlucoseChange, displayUnits: settings.glucosePreference.unit)
                Spacer()
                HStack {
                    if nightscoutDataSource.updating {
                        ProgressView()
                            .padding([.trailing], 10.0)
                    }
                    pickerButton
                }
            }.onChange(of: hudViewModel.selectedLooper) { _ in
                looperPopoverShowing = false
            }
            LifecycleStatusView(status: nightscoutDataSource.lifecycleStatus)
            if let (activeOverride, status) = nightscoutDataSource.activeOverrideAndStatus() {
                ActiveOverrideInlineView(activeOverride: activeOverride, status: status)
            }
            if let recommendedBolus = nightscoutDataSource.recommendedBolus {
                TitleSubtitleRowView(
                    title: "Recommended Bolus",
                    subtitle: LocalizationUtils.presentableStringFromBolusAmount(recommendedBolus) + " U"
                )
            }
        }
    }
    
    var lastGlucoseChange: Double? {
        let samples = nightscoutDataSource.glucoseSamples
        return samples.getLastGlucoseChange(displayUnits: settings.glucosePreference.unit)
    }
    
    var pickerButton: some View {
        Button {
            looperPopoverShowing = true
        } label: {
            HStack {
                Text(hudViewModel.selectedLooper.name)
                Image(systemName: "person.crop.circle")
                    .accessibilityLabel(Text("select looper"))
            }
        }
        .popover(isPresented: $looperPopoverShowing) {
            NavigationStack {
                Form {
                    Picker("", selection: $hudViewModel.selectedLooper) {
                        ForEach(hudViewModel.loopers()) { looper in
                            Text(looper.name).tag(looper)
                        }
                    }
                    .pickerStyle(.inline)
                }
                .toolbar(content: {
                    ToolbarItem {
                        Button {
                            looperPopoverShowing = false
                        } label: {
                            Text("Done")
                        }
                    }
                })
            }
            .presentationDetents([.medium])
        }
    }
    
    enum EGVTrend: Int {
        case doubleUp = 1
        case singleUp = 2
        case fortyFiveUp = 3
        case flat = 4
        case fortyFiveDown = 5
        case singleDown = 6
        case doubleDown = 7
        case nonComputable = 8
        case outOfRange = 9
    }
}

class HUDViewModel: ObservableObject {
    @Published var glucoseDisplayUnits: HKUnit
    /*
     TODO: This property both reflects
     the selectedLooper of the AccountServiceManager
     and the selection state of the HUD view. This may be a problem
     as it can lead to recursive updates since updating the active
     loop user, updates the lastSelectedDate, which sends a new
     selectedLooper to the initializer of this view.
     See note == method of Looper.
     See also the refresh() method of AccountServiceManager which
     may be working around some of this.
     Note we could probably make selectedLooper optional. See
     WatchSettingsView for example of how this was done.
     */
    @Published var selectedLooper: Looper {
        didSet {
            do {
                try accountService.updateActiveLoopUser(selectedLooper)
            } catch {
                print(error)
            }
        }
    }
    @ObservedObject var accountService: AccountServiceManager
    private var settings: CaregiverSettings
    private var subscribers: Set<AnyCancellable> = []
    
    init(selectedLooper: Looper, accountService: AccountServiceManager, settings: CaregiverSettings) {
        self.selectedLooper = selectedLooper
        self.accountService = accountService
        self.settings = settings
        self.glucoseDisplayUnits = self.settings.glucosePreference.unit
        
        // TODO: This is a hack to support: accountService.selectedLooper = looper
        // Move this logic to accountService.
        self.accountService.$selectedLooper.sink { _ in
        } receiveValue: { [weak self] updatedUser in
            if let self, let updatedUser, self.selectedLooper != updatedUser {
                self.selectedLooper = updatedUser
            }
        }.store(in: &subscribers)
    }
    
    func loopers() -> [Looper] {
        return accountService.loopers
    }
    
    @objc
    func defaultsChanged(notication: Notification) {
        if self.glucoseDisplayUnits != settings.glucosePreference.unit {
            self.glucoseDisplayUnits = settings.glucosePreference.unit
        }
    }
}
