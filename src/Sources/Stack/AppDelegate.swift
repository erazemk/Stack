//
//  AppDelegate.swift
//  Stack
//
//  Handles global keyboard shortcuts and app lifecycle
//

import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox
import ServiceManagement

// Notification for toggling the menu bar popover
extension Notification.Name {
    static let toggleMenuBarPopover = Notification.Name("toggleMenuBarPopover")
    static let popoverDidShow = Notification.Name("popoverDidShow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let distributedNotificationCenter = DistributedNotificationCenter.default()
    private var hotKeyRef: EventHotKeyRef?
    private var taskManager = TaskManager()
    private var modelContainer: ModelContainer?

    // Store reference for the event handler callback
    nonisolated(unsafe) static var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Hide dock icon for menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Ensure app launches at login
        setupLaunchAtLogin()

        // Setup model container
        setupModelContainer()

        // Setup the status item with content view
        setupStatusItem()

        // Set up global keyboard shortcut (Control + Option + S)
        registerHotKey()

        // Stop the current task timer when the screen locks
        distributedNotificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: Notification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil
        )
    }

    private func setupLaunchAtLogin() {
        let service = SMAppService.mainApp

        // Check if already enabled
        if service.status != .enabled {
            do {
                try service.register()
                print("Launch at login enabled")
            } catch {
                print("Failed to enable launch at login: \(error)")
            }
        } else {
            print("Launch at login already enabled")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskManager.prepareForTermination()

        distributedNotificationCenter.removeObserver(
            self,
            name: Notification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil
        )
        unregisterHotKey()
    }

    private func setupModelContainer() {
        let schema = Schema([StackTask.self])

        do {
            try configureModelContainer(
                schema: schema,
                configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false),
                storageMode: .persistent
            )
        } catch let persistentStoreError {
            print("Failed to create persistent ModelContainer: \(persistentStoreError)")

            do {
                try configureModelContainer(
                    schema: schema,
                    configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true),
                    storageMode: .recoveryInMemory,
                    warningMessage: String(localized: "error.persistenceRecovery")
                )
            } catch let recoveryStoreError {
                presentStartupFailure(
                    persistentStoreError: persistentStoreError,
                    recoveryStoreError: recoveryStoreError
                )
            }
        }
    }

    private func configureModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        storageMode: TaskStorageMode,
        warningMessage: String? = nil
    ) throws {
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        if let context = modelContainer?.mainContext {
            taskManager.configurePersistence(context: context, storageMode: storageMode, warningMessage: warningMessage)
        }
    }

    private func presentStartupFailure(persistentStoreError: Error, recoveryStoreError: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "error.startupFailureTitle")
        alert.informativeText = """
        \(String(localized: "error.startupFailureMessage"))

        Persistent store error: \(persistentStoreError.localizedDescription)
        Recovery store error: \(recoveryStoreError.localizedDescription)
        """
        alert.addButton(withTitle: String(localized: "OK"))

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let contentView = ContentView(taskManager: taskManager)
            .onAppear {
                // Update button when popover appears
                self.updateStatusButton()
            }

        StatusItemController.shared.setup(with: contentView)
        updateStatusButton()

        // Observe task changes to update the status button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusButton),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )

        // Observe popover show to check for auto-clear of completed tasks
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopoverDidShow),
            name: .popoverDidShow,
            object: nil
        )
    }

    @objc private func handlePopoverDidShow() {
        taskManager.checkAndClearCompletedTasksIfNeeded()
    }

    @objc private func handleScreenLocked(_ notification: Notification) {
        Task { @MainActor in
            taskManager.stopCurrentTaskTimer()
        }
    }

    @objc private func updateStatusButton() {
        let title = taskManager.currentTask?.title
        let isRunning = taskManager.isCurrentTaskRunning
        StatusItemController.shared.updateButton(title: title, isRunning: isRunning)
    }

    private func registerHotKey() {
        // Define the hotkey: Control + Option + S
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_S)

        // Create hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5354_434B) // "STCK" in hex
        hotKeyID.id = 1

        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        var eventHandlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                // Post notification to toggle popover
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .toggleMenuBarPopover, object: nil)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            print("Failed to install event handler: \(handlerStatus)")
        } else {
            print("Event handler installed successfully")
        }

        // Register the hotkey
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("Failed to register hotkey: \(registerStatus)")
        } else {
            print("Global hotkey registered successfully")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
