//
//  RootView.swift
//  QRCode
//

import SwiftUI
import LibEarnMoneyIOS

struct RootView: View {
    @State private var selection: AppTab = .create
    @State private var scanViewModel = ScanViewModel()
    @State private var preferences = AppPreferences()
    @State private var createPath = NavigationPath()
    @State private var historyPath = NavigationPath()
    @State private var historySelectionMode: Bool = false
    @State private var showLaunchPaywall: Bool = false
    @State private var didTriggerLaunchPaywall: Bool = false

    /// Hide tab bar when nav stack is pushed (detail has its own bottom UI)
    /// OR when History is in selection mode (replaced by Delete Selected button).
    private var hideTabBar: Bool {
        switch selection {
        case .create:  return createPath.count > 0
        case .history: return historyPath.count > 0 || historySelectionMode
        default:       return false
        }
    }

    /// Banner stays visible on tab roots — even in History selection mode (per ads spec).
    /// Only hidden when navigating to a detail screen (which has its own banner inside).
    private var hideBanner: Bool {
        switch selection {
        case .create:  return createPath.count > 0
        case .history: return historyPath.count > 0
        default:       return false
        }
    }

    init() {
        UITabBar.appearance().isHidden = true
        // Globally hide UINavigationBar — every screen uses a custom header.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().isTranslucent = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                ScanView(viewModel: scanViewModel, preferences: preferences)
                    .tag(AppTab.scan)
                    .toolbar(.hidden, for: .tabBar)
                CreateView(path: $createPath, preferences: preferences)
                    .tag(AppTab.create)
                    .toolbar(.hidden, for: .tabBar)
                HistoryView(path: $historyPath, selectionMode: $historySelectionMode) { tab in
                    selection = tab
                }
                .tag(AppTab.history)
                .toolbar(.hidden, for: .tabBar)
                SettingsView(preferences: preferences)
                    .tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }

            VStack(spacing: 0) {
                if !hideTabBar {
                    CustomTabBar(selection: $selection, transparent: selection == .scan)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Scan tab is camera-only — no ads there. Scan Result + Batch Result
                // get their own banner inside their detail views.
                if !hideBanner, let bannerID = bannerAdUnitID {
                    BannerAdView(adUnitID: bannerID)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: hideTabBar)
        .animation(.easeInOut(duration: 0.22), value: hideBanner)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $showLaunchPaywall) {
            PaywallView()
        }
        .task {
            // Show paywall once after lib splash + cold-start ad finish routing here.
            // `.task` can re-fire when UIKit modals (interstitials) come and go on top
            // of the SwiftUI hosting controller; guard against re-trigger so we don't
            // race the scan-result sheet and accidentally show the paywall mid-session.
            guard !didTriggerLaunchPaywall else { return }
            didTriggerLaunchPaywall = true
            guard !PermissionManager.shared.isPremium else { return }
            try? await Task.sleep(for: .milliseconds(400))
            showLaunchPaywall = true
        }
    }

    private var bannerAdUnitID: String? {
        switch selection {
        case .scan:     return nil
        case .create:   return AdUnits.bannerCreate
        case .history:  return AdUnits.bannerHistory
        case .settings: return AdUnits.bannerSetting
        }
    }
}

#Preview {
    RootView()
}
