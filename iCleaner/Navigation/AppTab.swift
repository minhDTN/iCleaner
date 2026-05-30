//
//  AppTab.swift
//  QRCode
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case scan
    case create
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan:     return "Scan"
        case .create:   return "Create"
        case .history:  return "History"
        case .settings: return "Setting"
        }
    }

    var iconAssetName: String {
        switch self {
        case .scan:     return "TabBar/ic_tab_scan"
        case .create:   return "TabBar/ic_tab_create"
        case .history:  return "TabBar/ic_tab_history"
        case .settings: return "TabBar/ic_tab_settings"
        }
    }
}
