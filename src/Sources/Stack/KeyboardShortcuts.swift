import AppKit
import Foundation

enum KeyboardShortcutMode: Hashable {
    case main
    case add
    case rename
    case help
}

enum KeyboardShortcutSection: String, CaseIterable, Identifiable {
    case global
    case main
    case navigation
    case addMode
    case renameMode
    case help

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .global:
            "help.section.global"
        case .main:
            "help.section.main"
        case .navigation:
            "help.section.navigation"
        case .addMode:
            "help.section.addMode"
        case .renameMode:
            "help.section.renameMode"
        case .help:
            "help.section.help"
        }
    }
}

enum KeyboardShortcutAction: String, Identifiable {
    case togglePopover
    case toggleHelp
    case closeHelp
    case newTask
    case makeActive
    case toggleTimer
    case toggleCompletion
    case deleteTask
    case renameTask
    case quit
    case navigateUp
    case navigateDown
    case reorderUp
    case reorderDown
    case resetFocus
    case quickSelect
    case addTask
    case addActiveTask
    case cancelAdd
    case confirmRename
    case cancelRename

    var id: String { rawValue }
}

struct KeyboardShortcutDefinition: Identifiable {
    let action: KeyboardShortcutAction
    let key: String
    let descriptionKey: String
    let section: KeyboardShortcutSection
    let activeModes: Set<KeyboardShortcutMode>
    let matcher: (NSEvent) -> Bool

    var id: KeyboardShortcutAction { action }
}

@MainActor
enum KeyboardShortcutRegistry {
    static let shortcuts: [KeyboardShortcutDefinition] = [
        KeyboardShortcutDefinition(
            action: .togglePopover,
            key: "⌃⌥S",
            descriptionKey: "help.shortcut.togglePopover",
            section: .global,
            activeModes: [],
            matcher: { _ in false }
        ),
        KeyboardShortcutDefinition(
            action: .toggleHelp,
            key: "⌘?",
            descriptionKey: "help.shortcut.toggleHelp",
            section: .help,
            activeModes: [],
            matcher: { _ in false }
        ),
        KeyboardShortcutDefinition(
            action: .closeHelp,
            key: "Esc",
            descriptionKey: "help.shortcut.closeHelp",
            section: .help,
            activeModes: [.help],
            matcher: exactKeyCode(53)
        ),
        KeyboardShortcutDefinition(
            action: .newTask,
            key: "⌘N",
            descriptionKey: "help.shortcut.newTask",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("n", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .makeActive,
            key: "⌘A",
            descriptionKey: "help.shortcut.makeActive",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("a", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .toggleTimer,
            key: "⌘S",
            descriptionKey: "help.shortcut.toggleTimer",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("s", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .toggleCompletion,
            key: "⌘C / Enter",
            descriptionKey: "help.shortcut.toggleCompletion",
            section: .main,
            activeModes: [.main],
            matcher: { event in
                exactCharacter("c", modifiers: [.command])(event) || exactKeyCode(36)(event)
            }
        ),
        KeyboardShortcutDefinition(
            action: .deleteTask,
            key: "⌘D",
            descriptionKey: "help.shortcut.deleteTask",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("d", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .renameTask,
            key: "⌘R",
            descriptionKey: "help.shortcut.renameTask",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("r", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .quit,
            key: "⌘Q",
            descriptionKey: "help.shortcut.quit",
            section: .main,
            activeModes: [.main],
            matcher: exactCharacter("q", modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .navigateUp,
            key: "↑",
            descriptionKey: "help.shortcut.navigateUp",
            section: .navigation,
            activeModes: [.main],
            matcher: exactKeyCode(126)
        ),
        KeyboardShortcutDefinition(
            action: .navigateDown,
            key: "↓",
            descriptionKey: "help.shortcut.navigateDown",
            section: .navigation,
            activeModes: [.main],
            matcher: exactKeyCode(125)
        ),
        KeyboardShortcutDefinition(
            action: .reorderUp,
            key: "⌘↑",
            descriptionKey: "help.shortcut.reorderUp",
            section: .navigation,
            activeModes: [.main],
            matcher: exactKeyCode(126, modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .reorderDown,
            key: "⌘↓",
            descriptionKey: "help.shortcut.reorderDown",
            section: .navigation,
            activeModes: [.main],
            matcher: exactKeyCode(125, modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .resetFocus,
            key: "Esc",
            descriptionKey: "help.shortcut.resetFocus",
            section: .navigation,
            activeModes: [.main],
            matcher: exactKeyCode(53)
        ),
        KeyboardShortcutDefinition(
            action: .quickSelect,
            key: "1-9, 0",
            descriptionKey: "help.shortcut.quickSelect",
            section: .navigation,
            activeModes: [.main],
            matcher: numberKeyMatcher
        ),
        KeyboardShortcutDefinition(
            action: .addTask,
            key: "Enter",
            descriptionKey: "help.shortcut.addTask",
            section: .addMode,
            activeModes: [.add],
            matcher: exactKeyCode(36)
        ),
        KeyboardShortcutDefinition(
            action: .addActiveTask,
            key: "⌘Enter",
            descriptionKey: "help.shortcut.addActiveTask",
            section: .addMode,
            activeModes: [.add],
            matcher: exactKeyCode(36, modifiers: [.command])
        ),
        KeyboardShortcutDefinition(
            action: .cancelAdd,
            key: "Esc",
            descriptionKey: "help.shortcut.cancelAdd",
            section: .addMode,
            activeModes: [.add],
            matcher: exactKeyCode(53)
        ),
        KeyboardShortcutDefinition(
            action: .confirmRename,
            key: "Enter",
            descriptionKey: "help.shortcut.confirmRename",
            section: .renameMode,
            activeModes: [.rename],
            matcher: exactKeyCode(36)
        ),
        KeyboardShortcutDefinition(
            action: .cancelRename,
            key: "Esc",
            descriptionKey: "help.shortcut.cancelRename",
            section: .renameMode,
            activeModes: [.rename],
            matcher: exactKeyCode(53)
        )
    ]

    static func firstMatchingAction(for event: NSEvent, mode: KeyboardShortcutMode) -> KeyboardShortcutAction? {
        shortcuts.first(where: { $0.activeModes.contains(mode) && $0.matcher(event) })?.action
    }

    static func shortcuts(in section: KeyboardShortcutSection) -> [KeyboardShortcutDefinition] {
        shortcuts.filter { $0.section == section }
    }

    private static func exactCharacter(_ character: String, modifiers expectedModifiers: NSEvent.ModifierFlags) -> (NSEvent) -> Bool {
        { event in
            normalizedModifiers(for: event) == expectedModifiers
                && event.charactersIgnoringModifiers?.lowercased() == character.lowercased()
        }
    }

    private static func exactKeyCode(_ keyCode: UInt16, modifiers expectedModifiers: NSEvent.ModifierFlags = []) -> (NSEvent) -> Bool {
        { event in
            normalizedModifiers(for: event) == expectedModifiers && event.keyCode == keyCode
        }
    }

    private static var numberKeyMatcher: (NSEvent) -> Bool {
        { event in
            normalizedModifiers(for: event).isEmpty
                && event.charactersIgnoringModifiers?.count == 1
                && event.charactersIgnoringModifiers?.first?.isNumber == true
        }
    }

    private static func normalizedModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
}
