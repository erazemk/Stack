//
//  StatusItemController.swift
//  Stack
//
//  Controls the menu bar status item and popover
//

import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private let popoverWidth: CGFloat = 320
    private let defaultPopoverHeight: CGFloat = 700

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var animationTimer: Timer?
    private var currentAnimationFrame = 0
    private var currentTitle: String?
    private var currentPopoverHeight: CGFloat = 700

    // Animation frames for running state
    private let runningIconFrames = [
        "square.3.layers.3d.bottom.filled",
        "square.3.layers.3d.middle.filled",
        "square.3.layers.3d.top.filled"
    ]

    // Static icon for paused/no task state
    private let pausedIcon = "square.3.layers.3d"

    var isPopoverShown = false

    static let shared = StatusItemController()

    private init() {}

    func setup(with contentView: some View) {
        // Create the status item with dynamic width
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Create the popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: popoverWidth, height: defaultPopoverHeight)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: contentView)

        // Configure the button
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: pausedIcon, accessibilityDescription: String(localized: "accessibility.stack"))
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Monitor for clicks outside the popover to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.isPopoverShown == true {
                self?.closePopover()
            }
        }

        // Listen for toggle notification from hotkey
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleNotification),
            name: .toggleMenuBarPopover,
            object: nil
        )
    }

    func updateButton(title: String?, isRunning: Bool) {
        currentTitle = title

        if isRunning {
            startAnimation()
        } else {
            stopAnimation()
            updateIcon(symbolName: pausedIcon, isRunning: false)
        }

        // Update title
        guard let button = statusItem?.button else { return }
        if let title = title {
            let truncatedTitle = String(title.prefix(128)) + (title.count > 128 ? "…" : "")
            button.title = " " + truncatedTitle
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func startAnimation() {
        // Don't start if already animating
        guard animationTimer == nil else { return }

        currentAnimationFrame = 0
        updateIcon(symbolName: runningIconFrames[currentAnimationFrame], isRunning: true)

        // Animate every 1 second (power-efficient)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.advanceAnimation()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        currentAnimationFrame = 0
    }

    private func advanceAnimation() {
        currentAnimationFrame = (currentAnimationFrame + 1) % runningIconFrames.count
        updateIcon(symbolName: runningIconFrames[currentAnimationFrame], isRunning: true)
    }

    private func updateIcon(symbolName: String, isRunning: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isRunning ? String(localized: "accessibility.running") : String(localized: "accessibility.paused"))
    }

    func updatePopoverHeight(_ height: CGFloat) {
        let clampedHeight = max(240, min(height, defaultPopoverHeight))
        currentPopoverHeight = clampedHeight

        let newSize = NSSize(width: popoverWidth, height: clampedHeight)
        popover?.contentSize = newSize
        popover?.contentViewController?.preferredContentSize = newSize
    }

    @objc private func handleToggleNotification() {
        togglePopover()
    }

    @objc func togglePopover() {
        if isPopoverShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        let size = NSSize(width: popoverWidth, height: currentPopoverHeight)
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        isPopoverShown = true

        // Notify ContentView to reset focus to the active task
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)
    }

    func closePopover() {
        popover?.performClose(nil)
        isPopoverShown = false
    }
}
