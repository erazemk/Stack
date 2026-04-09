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
    private var hostingController: NSHostingController<AnyView>?
    private var animationTimer: Timer?
    private var currentAnimationFrame = 0
    private var currentPopoverHeight: CGFloat = 700

    private let runningIconFrames = [
        "square.3.layers.3d.bottom.filled",
        "square.3.layers.3d.middle.filled",
        "square.3.layers.3d.top.filled"
    ]
    private let pausedIcon = "square.3.layers.3d"

    static let shared = StatusItemController()

    private init() {}

    func setup(with contentView: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: popoverWidth, height: defaultPopoverHeight)
        popover.behavior = .transient
        popover.animates = true

        let hostingController = NSHostingController(rootView: AnyView(contentView))
        popover.contentViewController = hostingController
        self.popover = popover
        self.hostingController = hostingController

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: pausedIcon,
                accessibilityDescription: String(localized: "accessibility.stack")
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleNotification),
            name: .toggleMenuBarPopover,
            object: nil
        )
    }

    func updateButton(title: String?, isRunning: Bool) {
        if isRunning {
            startAnimation()
        } else {
            stopAnimation()
            updateIcon(symbolName: pausedIcon, isRunning: false)
        }

        guard let button = statusItem?.button else { return }

        if let title {
            let truncatedTitle = String(title.prefix(128)) + (title.count > 128 ? "…" : "")
            button.title = " " + truncatedTitle
            button.imagePosition = .imageLeading
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly
    }

    func updatePopoverHeight() {
        guard let popover, let hostingController else { return }

        let fittedSize = hostingController.sizeThatFits(in: NSSize(width: popoverWidth, height: defaultPopoverHeight))
        let clampedHeight = min(max(ceil(fittedSize.height), 1), defaultPopoverHeight)
        currentPopoverHeight = clampedHeight

        let size = NSSize(width: popoverWidth, height: clampedHeight)
        popover.contentSize = size
        hostingController.preferredContentSize = size
    }

    @objc func togglePopover() {
        guard let popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover else { return }

        updatePopoverHeight()

        let size = NSSize(width: popoverWidth, height: currentPopoverHeight)
        popover.contentSize = size
        popover.contentViewController?.preferredContentSize = size

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NotificationCenter.default.post(name: .popoverDidShow, object: nil)

        DispatchQueue.main.async {
            self.updatePopoverHeight()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    @objc private func handleToggleNotification() {
        togglePopover()
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }

        currentAnimationFrame = 0
        updateIcon(symbolName: runningIconFrames[currentAnimationFrame], isRunning: true)
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
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
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRunning
                ? String(localized: "accessibility.running")
                : String(localized: "accessibility.paused")
        )
    }
}
