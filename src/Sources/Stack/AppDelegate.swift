//
//  AppDelegate.swift
//  Stack
//
//  Handles app lifecycle and persistence setup
//

import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox

extension Notification.Name {
    static let toggleMenuBarPopover = Notification.Name("toggleMenuBarPopover")
    static let popoverDidShow = Notification.Name("popoverDidShow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let distributedNotificationCenter = DistributedNotificationCenter.default()
    private var hotKeyRef: EventHotKeyRef?
    private let taskManager = TaskManager()
    private var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupModelContainer()
        setupStatusItem()
        registerHotKey()

        distributedNotificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: Notification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil
        )
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
            let storeURL = try persistentStoreURL()

            do {
                try configureModelContainer(schema: schema, storeURL: storeURL)
            } catch let persistentStoreError {
                print("Failed to create persistent ModelContainer: \(persistentStoreError)")
                let warningMessage = try resetPersistentStore(at: storeURL)
                try configureModelContainer(schema: schema, storeURL: storeURL, warningMessage: warningMessage)
            }
        } catch {
            presentStartupFailure(error)
        }
    }

    private func configureModelContainer(
        schema: Schema,
        storeURL: URL,
        warningMessage: String? = nil
    ) throws {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        if let context = modelContainer?.mainContext {
            taskManager.configurePersistence(context: context, warningMessage: warningMessage)
        }
    }

    private func persistentStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let stackDirectory = appSupportDirectory.appendingPathComponent("com.erazemk.Stack", isDirectory: true)

        try fileManager.createDirectory(at: stackDirectory, withIntermediateDirectories: true)

        return stackDirectory.appendingPathComponent("Stack.store")
    }

    private func resetPersistentStore(at storeURL: URL) throws -> String {
        let fileManager = FileManager.default
        let parentDirectory = storeURL.deletingLastPathComponent()
        let archiveDirectory = parentDirectory.appendingPathComponent("ArchivedStores", isDirectory: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let storeFilePrefix = storeURL.lastPathComponent

        try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

        let siblingFiles = try fileManager.contentsOfDirectory(at: parentDirectory, includingPropertiesForKeys: nil)
        for fileURL in siblingFiles where fileURL.lastPathComponent.hasPrefix(storeFilePrefix) {
            let archivedURL = archiveDirectory.appendingPathComponent("\(timestamp)-\(fileURL.lastPathComponent)")
            try? fileManager.removeItem(at: archivedURL)
            try fileManager.moveItem(at: fileURL, to: archivedURL)
        }

        return String(localized: "error.persistenceReset")
    }

    private func presentStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "error.startupFailureTitle")
        alert.informativeText = """
        \(String(localized: "error.startupFailureMessage"))

        \(error.localizedDescription)
        """
        alert.addButton(withTitle: String(localized: "OK"))

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let contentView = ContentView(taskManager: taskManager)
            .onAppear {
                self.updateStatusButton()
            }

        StatusItemController.shared.setup(with: contentView)
        updateStatusButton()
    }

    @objc private func handleScreenLocked(_ notification: Notification) {
        taskManager.stopCurrentTaskTimer()
    }

    @objc private func updateStatusButton() {
        StatusItemController.shared.updateButton(
            title: taskManager.currentTask?.title,
            isRunning: taskManager.isCurrentTaskRunning
        )
    }

    private func registerHotKey() {
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_S)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5354_434B)
        hotKeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var eventHandlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
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
        }

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
        }
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
    }
}
