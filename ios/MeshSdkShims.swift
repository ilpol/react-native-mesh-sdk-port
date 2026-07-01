//
//  MeshSdkShims.swift
//  react-native-mesh-sdk (Native SDK, iOS)
//
//  Compatibility shims for symbols that live in bitchat-ios's `BitchatApp.swift`
//  (the SwiftUI @main app entry), which we do NOT vendor because the React
//  Native host provides the app entry point. Only the pieces the rest of the
//  Core still references are reproduced here — currently just NotificationDelegate,
//  used by AppRuntime. This is wrapper code in the app-target module, so it can
//  satisfy the Core's `internal` references without editing any Core file.
//

import Foundation

/// Minimal stand-in for bitchat's NotificationDelegate. The Core only sets
/// `NotificationDelegate.shared.runtime`; the RN app owns notifications itself,
/// so no UNUserNotificationCenterDelegate behavior is needed here.
final class NotificationDelegate: NSObject {
    static let shared = NotificationDelegate()
    weak var runtime: AppRuntime?
}

/// The removed SwiftUI @main `BitchatApp` also exposed these identifiers, which
/// KeychainManager (and the App Group config) rely on. Reproduced verbatim.
enum BitchatApp {
    static let bundleID = Bundle.main.bundleIdentifier ?? "chat.bitchat"
    static let groupID = "group.\(bundleID)"
}
