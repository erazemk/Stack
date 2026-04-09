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
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button(String(localized: "help.menu.keyboardShortcuts")) {
                    NotificationCenter.default.post(name: .toggleHelpView, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}
