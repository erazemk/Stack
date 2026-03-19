//
//  StackApp.swift
//  Stack
//
//  A stack-based todo list menu bar application
//

import SwiftUI
import SwiftData

@main
struct StackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a minimal Settings scene since the main UI is in the popover
        // The actual app UI is managed by StatusItemController
        Settings {
            EmptyView()
        }
    }
}
