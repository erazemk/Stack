//
//  TaskManager.swift
//  Stack
//
//  Manages the stack of tasks
//

import Foundation
import SwiftUI
import SwiftData

/// Snapshot of a task for undo/redo operations
struct TaskSnapshot {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let createdAt: Date
    let completedAt: Date?
    let startedAt: Date?
    let totalDuration: TimeInterval
    let order: Int
    let completedOrder: Int

    init(from task: StackTask) {
        self.id = task.id
        self.title = task.title
        self.isCompleted = task.isCompleted
        self.createdAt = task.createdAt
        self.completedAt = task.completedAt
        self.startedAt = task.startedAt
        self.totalDuration = task.totalDuration
        self.order = task.order
        self.completedOrder = task.completedOrder
    }

    func createTask() -> StackTask {
        let task = StackTask(title: title, order: order)
        task.id = id
        task.isCompleted = isCompleted
        task.createdAt = createdAt
        task.completedAt = completedAt
        task.startedAt = startedAt
        task.totalDuration = totalDuration
        task.completedOrder = completedOrder
        return task
    }

    func restore(to task: StackTask) {
        task.title = title
        task.isCompleted = isCompleted
        task.completedAt = completedAt
        task.startedAt = startedAt
        task.totalDuration = totalDuration
        task.order = order
        task.completedOrder = completedOrder
    }
}

enum TaskStorageMode {
    case persistent
    case recoveryInMemory
}

@Observable
@MainActor
final class TaskManager {
    var modelContext: ModelContext?
    var storageMode: TaskStorageMode = .persistent
    var storageWarningMessage: String?
    var transientErrorMessage: String?
    var inProgressTasks: [StackTask] = []
    var completedTasks: [StackTask] = []
    var isAddingTask: Bool = false
    var newTaskTitle: String = ""
    let undoManager = UndoManager()

    // MARK: - Auto-clear completed tasks configuration

    /// Hours of inactivity required before clearing (after midnight passes)
    let inactivityHoursThreshold: Double = 3.0

    private let lastActivityDateKey = "lastActivityDate"
    private let lastCompletedTasksClearDateKey = "lastCompletedTasksClearDate"

    /// The current (top) task in the stack (first in-progress task)
    var currentTask: StackTask? {
        inProgressTasks.first
    }

    /// Check if the current task timer is running
    var isCurrentTaskRunning: Bool {
        currentTask?.startedAt != nil
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func undo() {
        undoManager.undo()
    }

    func redo() {
        undoManager.redo()
    }

    func configurePersistence(context: ModelContext, storageMode: TaskStorageMode, warningMessage: String? = nil) {
        modelContext = context
        self.storageMode = storageMode
        storageWarningMessage = warningMessage
        fetchTasks()
    }

    func dismissTransientError() {
        transientErrorMessage = nil
    }

    // MARK: - Auto-clear completed tasks

    /// Called when the app becomes active (e.g., popover opens).
    /// Clears completed tasks if midnight has passed and user has been inactive for the threshold period.
    func checkAndClearCompletedTasksIfNeeded() {
        let now = Date()
        let calendar = Calendar.current

        let lastActivity = UserDefaults.standard.object(forKey: lastActivityDateKey) as? Date ?? now
        let lastClear = UserDefaults.standard.object(forKey: lastCompletedTasksClearDateKey) as? Date ?? .distantPast

        // Calculate midnight after the last activity
        let dayAfterLastActivity = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastActivity))!

        // Check conditions:
        // 1. Current time is past midnight following last activity
        // 2. Inactive for at least the threshold hours
        // 3. Haven't already cleared today
        let midnightPassed = now >= dayAfterLastActivity
        let inactivityHours = now.timeIntervalSince(lastActivity) / 3600
        let hasEnoughInactivity = inactivityHours >= inactivityHoursThreshold
        let notClearedToday = !calendar.isDate(lastClear, inSameDayAs: now)

        if midnightPassed && hasEnoughInactivity && notClearedToday && !completedTasks.isEmpty {
            print("Auto-clearing completed tasks: midnight passed, \(String(format: "%.1f", inactivityHours))h inactive")
            removeAllCompletedTasksWithoutUndo()
            UserDefaults.standard.set(now, forKey: lastCompletedTasksClearDateKey)
        }

        // Update last activity timestamp
        recordActivity()
    }

    /// Records user activity (updates the last activity timestamp)
    func recordActivity() {
        UserDefaults.standard.set(Date(), forKey: lastActivityDateKey)
    }

    /// Removes all completed tasks without registering undo (used for auto-clear)
    private func removeAllCompletedTasksWithoutUndo() {
        guard let context = modelContext, !completedTasks.isEmpty else { return }

        for task in completedTasks {
            context.delete(task)
        }
        saveAndRefresh()
    }

    /// Fetch all tasks sorted by order
    func fetchTasks(persistRepairs: Bool = true) {
        guard let context = modelContext else { return }

        // Fetch in-progress tasks (highest order = top of stack)
        let inProgressDescriptor = FetchDescriptor<StackTask>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.order, order: .reverse)]
        )

        // Fetch completed tasks (highest completedOrder = most recent)
        let completedDescriptor = FetchDescriptor<StackTask>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.completedOrder, order: .reverse)]
        )

        do {
            inProgressTasks = try context.fetch(inProgressDescriptor)
            completedTasks = try context.fetch(completedDescriptor)

            var repairedTimerState = false

            // Ensure only the current task can have its timer running
            for (index, task) in inProgressTasks.enumerated() {
                if index != 0 && task.startedAt != nil {
                    task.stopTimer()
                    repairedTimerState = true
                }
            }

            // Ensure completed tasks have timers stopped
            for task in completedTasks {
                if task.startedAt != nil {
                    task.stopTimer()
                    repairedTimerState = true
                }
            }

            if repairedTimerState && persistRepairs {
                _ = saveContext(refreshAfterSuccess: false, reloadAfterFailure: true)
            }

            updateStatusButton()
        } catch {
            print("Failed to fetch tasks: \(error)")
            transientErrorMessage = "\(String(localized: "error.loadFailed")) \(error.localizedDescription)"
            inProgressTasks = []
            completedTasks = []
            updateStatusButton()
        }
    }

    /// Add a new task
    /// - Parameters:
    ///   - title: The task title
    ///   - makeActive: If true, makes it the active task
    ///   - insertAtBottom: If true, adds it to the bottom of the stack
    func addTask(title: String, makeActive: Bool = false, insertAtBottom: Bool = false) {
        guard let context = modelContext, !title.isEmpty else { return }

        // Capture state for undo
        let previousCurrentSnapshot = currentTask.map { TaskSnapshot(from: $0) }
        let previousOrders = inProgressTasks.map { ($0.id, $0.order) }

        var newTaskID: UUID!

        // If there's no current task or makeActive is true, the new task becomes current
        if currentTask == nil || makeActive {
            // Stop timer on current task before adding new one
            if let current = currentTask {
                current.stopTimer()
            }

            // New task gets order = max + 1 (top of stack)
            let maxOrder = inProgressTasks.map(\.order).max() ?? -1
            let newTask = StackTask(title: title, order: maxOrder + 1)
            newTask.startTimer()
            context.insert(newTask)
            newTaskID = newTask.id
        } else if insertAtBottom {
            // Add at the bottom of the stack
            let minOrder = inProgressTasks.map(\.order).min() ?? 0
            let newTask = StackTask(title: title, order: minOrder - 1)
            // Don't start timer - it's not the current task
            context.insert(newTask)
            newTaskID = newTask.id
        } else {
            // Add as first non-active task (second in the list)
            // Shift all non-current tasks' orders down by 1
            for task in inProgressTasks.dropFirst() {
                task.order -= 1
            }

            // Insert new task with order one less than current task
            let newOrder = (currentTask?.order ?? 0) - 1
            let newTask = StackTask(title: title, order: newOrder)
            // Don't start timer - it's not the current task
            context.insert(newTask)
            newTaskID = newTask.id
        }

        saveAndRefresh()

        // Register undo
        let taskTitle = title
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoAddTask(
                taskID: newTaskID,
                title: taskTitle,
                previousCurrentSnapshot: previousCurrentSnapshot,
                previousOrders: previousOrders,
                wasActive: makeActive || previousCurrentSnapshot == nil,
                wasInsertedAtBottom: insertAtBottom && previousCurrentSnapshot != nil
            )
        }
        undoManager.setActionName(String(localized: "undo.addTask"))
    }

    private func undoAddTask(taskID: UUID, title: String, previousCurrentSnapshot: TaskSnapshot?, previousOrders: [(UUID, Int)], wasActive: Bool, wasInsertedAtBottom: Bool) {
        guard let context = modelContext else { return }

        // Find and delete the added task
        if let task = findTask(by: taskID) {
            task.stopTimer()
            context.delete(task)
        }

        // Restore previous orders
        for (id, order) in previousOrders {
            if let task = findTask(by: id) {
                task.order = order
            }
        }

        // Restore previous current task's timer if needed
        if wasActive, let snapshot = previousCurrentSnapshot, let task = findTask(by: snapshot.id) {
            task.startTimer()
        }

        saveAndRefresh()

        // Register redo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.addTask(title: title, makeActive: wasActive, insertAtBottom: wasInsertedAtBottom)
        }
        undoManager.setActionName(String(localized: "undo.addTask"))
    }

    private func findTask(by id: UUID) -> StackTask? {
        inProgressTasks.first { $0.id == id } ?? completedTasks.first { $0.id == id }
    }

    /// Remove the current (top) task from the stack
    func removeCurrentTask() {
        guard !inProgressTasks.isEmpty else { return }
        removeInProgressTask(at: 0)
    }

    /// Toggle completion status of the current (top) task
    func toggleCurrentTaskCompletion() {
        guard let current = currentTask else { return }
        completeTask(current)
    }

    /// Complete a specific task
    func completeTask(_ task: StackTask) {
        // Check if this is the current task
        let wasCurrentTask = (task.id == currentTask?.id)
        let taskID = task.id
        let previousOrder = task.order

        // Stop the timer
        task.stopTimer()

        // Mark as completed
        task.isCompleted = true
        task.completedAt = Date()

        // Set completed order (highest = most recent)
        let maxCompletedOrder = completedTasks.map(\.completedOrder).max() ?? -1
        task.completedOrder = maxCompletedOrder + 1

        // If this was the current task, start timer for the next one
        if wasCurrentTask {
            let nextTask = inProgressTasks.first { $0.id != task.id }
            nextTask?.startTimer()
        }

        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoCompleteTask(taskID: taskID, previousOrder: previousOrder, wasCurrentTask: wasCurrentTask)
        }
        undoManager.setActionName(String(localized: "undo.completeTask"))
    }

    private func undoCompleteTask(taskID: UUID, previousOrder: Int, wasCurrentTask: Bool) {
        guard let task = findTask(by: taskID) else { return }

        // Stop current task's timer if this will become current
        if wasCurrentTask, let current = currentTask {
            current.stopTimer()
        }

        // Mark as not completed
        task.isCompleted = false
        task.completedAt = nil
        task.order = previousOrder

        // Start timer if it was the current task
        if wasCurrentTask {
            task.startTimer()
        }

        saveAndRefresh()

        // Register redo
        undoManager.registerUndo(withTarget: self) { manager in
            if let task = manager.findTask(by: taskID) {
                manager.completeTask(task)
            }
        }
        undoManager.setActionName(String(localized: "undo.completeTask"))
    }

    /// Uncomplete a task - moves it back to in-progress at the top
    func uncompleteTask(_ task: StackTask) {
        let taskID = task.id
        let previousCompletedOrder = task.completedOrder

        // Stop timer on current task before this one becomes current
        if let current = currentTask {
            current.stopTimer()
        }

        // Mark as not completed
        task.isCompleted = false
        task.completedAt = nil

        // Move to top of in-progress
        let maxOrder = inProgressTasks.map(\.order).max() ?? -1
        task.order = maxOrder + 1

        // Start timer as it becomes current
        task.startTimer()

        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoUncompleteTask(taskID: taskID, previousCompletedOrder: previousCompletedOrder)
        }
        undoManager.setActionName(String(localized: "undo.uncompleteTask"))
    }

    private func undoUncompleteTask(taskID: UUID, previousCompletedOrder: Int) {
        guard let task = findTask(by: taskID) else { return }

        // This task is now active, stop its timer
        task.stopTimer()

        // Mark as completed again
        task.isCompleted = true
        task.completedAt = Date()
        task.completedOrder = previousCompletedOrder

        // Start timer for the next in-progress task
        let nextTask = inProgressTasks.first { $0.id != taskID }
        nextTask?.startTimer()

        saveAndRefresh()

        // Register redo
        undoManager.registerUndo(withTarget: self) { manager in
            if let task = manager.findTask(by: taskID) {
                manager.uncompleteTask(task)
            }
        }
        undoManager.setActionName(String(localized: "undo.uncompleteTask"))
    }

    /// Toggle the timer (start/stop) for the current task
    func toggleCurrentTaskTimer() {
        guard let current = currentTask else { return }

        if current.startedAt != nil {
            // Currently running, stop it
            current.stopTimer()
        } else {
            // Currently stopped, start it
            current.startTimer()
        }

        saveAndRefresh()
    }

    /// Stop the timer for the current task if it is running
    func stopCurrentTaskTimer() {
        guard let current = currentTask, current.startedAt != nil else { return }

        current.stopTimer()
        saveAndRefresh()
    }

    /// Make a specific in-progress task the active/current task
    /// The previous active task moves to position 1 (top of "up next")
    func makeTaskActive(_ task: StackTask) {
        guard !task.isCompleted,
              let taskIndex = inProgressTasks.firstIndex(where: { $0.id == task.id }),
              taskIndex > 0 else { return }

        let previousActiveID = currentTask?.id

        // Stop current task's timer
        if let current = currentTask {
            current.stopTimer()
        }

        // Move the selected task to position 0 (make it current)
        moveInProgressTaskWithoutUndo(from: taskIndex, to: 0)

        // Register undo (separate from moveInProgressTask to have correct action name)
        let taskID = task.id
        undoManager.registerUndo(withTarget: self) { manager in
            // Find the previous active task and make it active again
            if let previousID = previousActiveID,
               let prevTask = manager.findTask(by: previousID) {
                manager.makeTaskActive(prevTask)
            } else if manager.findTask(by: taskID) != nil,
                      let index = manager.inProgressTasks.firstIndex(where: { $0.id == taskID }) {
                // Move task back to its original position
                manager.moveInProgressTask(from: 0, to: index)
            }
        }
        undoManager.setActionName(String(localized: "undo.makeActive"))
    }

    /// Internal move without undo registration (used by makeTaskActive)
    private func moveInProgressTaskWithoutUndo(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0 && sourceIndex < inProgressTasks.count,
              destinationIndex >= 0 && destinationIndex < inProgressTasks.count else { return }

        // Get all orders and reassign them after moving
        var reorderedTasks = inProgressTasks
        let movedTask = reorderedTasks.remove(at: sourceIndex)
        reorderedTasks.insert(movedTask, at: destinationIndex)

        // Reassign orders (highest order = top of stack)
        for (index, task) in reorderedTasks.enumerated() {
            task.order = reorderedTasks.count - 1 - index
        }

        // Start timer for new current task
        if destinationIndex == 0 {
            movedTask.startTimer()
        }

        saveAndRefresh()
    }

    /// Make the task at a specific index the active/current task
    func makeInProgressTaskActive(at index: Int) {
        guard index > 0 && index < inProgressTasks.count else { return }
        makeTaskActive(inProgressTasks[index])
    }

    /// Rename a task
    func renameTask(_ task: StackTask, to newTitle: String) {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let oldTitle = task.title
        let taskID = task.id
        task.title = trimmedTitle
        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            if let task = manager.findTask(by: taskID) {
                manager.renameTask(task, to: oldTitle)
            }
        }
        undoManager.setActionName(String(localized: "undo.renameTask"))
    }

    /// Remove a specific task
    func removeTask(_ task: StackTask) {
        if let index = inProgressTasks.firstIndex(where: { $0.id == task.id }) {
            removeInProgressTask(at: index)
        } else if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
            removeCompletedTask(at: index)
        }
    }

    /// Toggle completion of a specific in-progress task
    func toggleInProgressTaskCompletion(at index: Int) {
        guard index >= 0 && index < inProgressTasks.count else { return }
        completeTask(inProgressTasks[index])
    }

    /// Toggle completion of a specific completed task (uncomplete it)
    func toggleCompletedTaskCompletion(at index: Int) {
        guard index >= 0 && index < completedTasks.count else { return }
        uncompleteTask(completedTasks[index])
    }

    /// Move an in-progress task up in the stack (increase priority)
    func moveInProgressTaskUp(at index: Int) {
        guard index > 0 && index < inProgressTasks.count else { return }

        let task = inProgressTasks[index]
        let taskAbove = inProgressTasks[index - 1]

        let tempOrder = task.order
        task.order = taskAbove.order
        taskAbove.order = tempOrder

        // Handle timer: if moving to position 0, start timer; if moving from position 0, stop timer
        if index == 1 {
            // Task above (was at 0) loses current status
            taskAbove.stopTimer()
            // Task moving up becomes current
            task.startTimer()
        }

        saveAndRefresh()

        // Register undo
        let newIndex = index - 1
        undoManager.registerUndo(withTarget: self) { manager in
            manager.moveInProgressTaskDown(at: newIndex)
        }
        undoManager.setActionName(String(localized: "undo.moveTask"))
    }

    /// Move an in-progress task down in the stack (decrease priority)
    func moveInProgressTaskDown(at index: Int) {
        guard index >= 0 && index < inProgressTasks.count - 1 else { return }

        let task = inProgressTasks[index]
        let taskBelow = inProgressTasks[index + 1]

        let tempOrder = task.order
        task.order = taskBelow.order
        taskBelow.order = tempOrder

        // Handle timer: if moving from position 0, stop timer; if moving to position 0, start timer
        if index == 0 {
            // Task moving down loses current status
            task.stopTimer()
            // Task below becomes current
            taskBelow.startTimer()
        }

        saveAndRefresh()

        // Register undo
        let newIndex = index + 1
        undoManager.registerUndo(withTarget: self) { manager in
            manager.moveInProgressTaskUp(at: newIndex)
        }
        undoManager.setActionName(String(localized: "undo.moveTask"))
    }

    /// Move an in-progress task to a specific position
    func moveInProgressTask(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0 && sourceIndex < inProgressTasks.count,
              destinationIndex >= 0 && destinationIndex < inProgressTasks.count else { return }

        // Handle timer changes
        let movingTask = inProgressTasks[sourceIndex]

        if sourceIndex == 0 {
            // Moving current task down, stop its timer
            movingTask.stopTimer()
        }

        // Get all orders and reassign them after moving
        var reorderedTasks = inProgressTasks
        let movedTask = reorderedTasks.remove(at: sourceIndex)
        reorderedTasks.insert(movedTask, at: destinationIndex)

        // Reassign orders (highest order = top of stack)
        for (index, task) in reorderedTasks.enumerated() {
            task.order = reorderedTasks.count - 1 - index
        }

        // Start timer for new current task if it changed
        if destinationIndex == 0 {
            movedTask.startTimer()
        } else if sourceIndex == 0 && destinationIndex != 0 {
            // A different task is now current
            reorderedTasks.first?.startTimer()
        }

        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.moveInProgressTask(from: destinationIndex, to: sourceIndex)
        }
        undoManager.setActionName(String(localized: "undo.moveTask"))
    }

    /// Remove an in-progress task at a specific index
    func removeInProgressTask(at index: Int) {
        guard let context = modelContext, index >= 0 && index < inProgressTasks.count else { return }
        let task = inProgressTasks[index]

        // Capture snapshot for undo
        let snapshot = TaskSnapshot(from: task)
        let wasActive = index == 0

        // If removing the current task (index 0), start timer for the next one
        var nextTask: StackTask? = nil
        if index == 0 && inProgressTasks.count > 1 {
            nextTask = inProgressTasks[1]
        }

        task.stopTimer()
        context.delete(task)

        // Start timer for new current task
        nextTask?.startTimer()

        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoRemoveInProgressTask(snapshot: snapshot, wasActive: wasActive)
        }
        undoManager.setActionName(String(localized: "undo.deleteTask"))
    }

    private func undoRemoveInProgressTask(snapshot: TaskSnapshot, wasActive: Bool) {
        guard let context = modelContext else { return }

        // Stop current task's timer if we're restoring to active position
        if wasActive, let current = currentTask {
            current.stopTimer()
        }

        // Recreate the task
        let task = snapshot.createTask()
        context.insert(task)

        // Start timer if it was active
        if wasActive {
            task.startTimer()
        }

        saveAndRefresh()

        // Register redo
        let taskID = snapshot.id
        undoManager.registerUndo(withTarget: self) { manager in
            if let index = manager.inProgressTasks.firstIndex(where: { $0.id == taskID }) {
                manager.removeInProgressTask(at: index)
            }
        }
        undoManager.setActionName(String(localized: "undo.deleteTask"))
    }

    /// Remove a completed task at a specific index
    func removeCompletedTask(at index: Int) {
        guard let context = modelContext, index >= 0 && index < completedTasks.count else { return }

        // Capture snapshot for undo
        let snapshot = TaskSnapshot(from: completedTasks[index])

        context.delete(completedTasks[index])
        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoRemoveCompletedTask(snapshot: snapshot)
        }
        undoManager.setActionName(String(localized: "undo.deleteTask"))
    }

    private func undoRemoveCompletedTask(snapshot: TaskSnapshot) {
        guard let context = modelContext else { return }

        // Recreate the task
        let task = snapshot.createTask()
        context.insert(task)

        saveAndRefresh()

        // Register redo
        let taskID = snapshot.id
        undoManager.registerUndo(withTarget: self) { manager in
            if let index = manager.completedTasks.firstIndex(where: { $0.id == taskID }) {
                manager.removeCompletedTask(at: index)
            }
        }
        undoManager.setActionName(String(localized: "undo.deleteTask"))
    }

    /// Delete all in-progress tasks
    func removeAllInProgressTasks() {
        guard let context = modelContext, !inProgressTasks.isEmpty else { return }

        // Capture snapshots for undo
        let snapshots = inProgressTasks.map { TaskSnapshot(from: $0) }

        for task in inProgressTasks {
            task.stopTimer()
            context.delete(task)
        }
        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoRemoveAllInProgressTasks(snapshots: snapshots)
        }
        undoManager.setActionName(String(localized: "undo.deleteAllTasks"))
    }

    private func undoRemoveAllInProgressTasks(snapshots: [TaskSnapshot]) {
        guard let context = modelContext else { return }

        var restoredCurrentTask: StackTask?

        // Recreate all tasks
        for snapshot in snapshots {
            let task = snapshot.createTask()
            context.insert(task)

            let restoredCurrentOrder = restoredCurrentTask?.order ?? .min
            if restoredCurrentTask == nil || task.order > restoredCurrentOrder {
                restoredCurrentTask = task
            }
        }

        // Start timer for the restored current task
        restoredCurrentTask?.startTimer()

        saveAndRefresh()

        // Register redo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.removeAllInProgressTasks()
        }
        undoManager.setActionName(String(localized: "undo.deleteAllTasks"))
    }

    /// Delete all completed tasks
    func removeAllCompletedTasks() {
        guard let context = modelContext, !completedTasks.isEmpty else { return }

        // Capture snapshots for undo
        let snapshots = completedTasks.map { TaskSnapshot(from: $0) }

        for task in completedTasks {
            context.delete(task)
        }
        saveAndRefresh()

        // Register undo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.undoRemoveAllCompletedTasks(snapshots: snapshots)
        }
        undoManager.setActionName(String(localized: "undo.deleteAllTasks"))
    }

    private func undoRemoveAllCompletedTasks(snapshots: [TaskSnapshot]) {
        guard let context = modelContext else { return }

        // Recreate all tasks
        for snapshot in snapshots {
            let task = snapshot.createTask()
            context.insert(task)
        }

        saveAndRefresh()

        // Register redo
        undoManager.registerUndo(withTarget: self) { manager in
            manager.removeAllCompletedTasks()
        }
        undoManager.setActionName(String(localized: "undo.deleteAllTasks"))
    }

    func prepareForTermination() {
        var changedTasks = false

        for task in inProgressTasks where task.startedAt != nil {
            task.stopTimer()
            changedTasks = true
        }

        for task in completedTasks where task.startedAt != nil {
            task.stopTimer()
            changedTasks = true
        }

        if changedTasks {
            _ = saveContext(refreshAfterSuccess: false, reloadAfterFailure: false)
        }
    }

    private func saveAndRefresh() {
        _ = saveContext(refreshAfterSuccess: true, reloadAfterFailure: true)
    }

    @discardableResult
    private func saveContext(refreshAfterSuccess: Bool, reloadAfterFailure: Bool) -> Bool {
        guard let context = modelContext else { return false }

        do {
            try context.save()
            transientErrorMessage = nil

            if refreshAfterSuccess {
                fetchTasks()
            } else {
                updateStatusButton()
            }

            return true
        } catch {
            print("Failed to save: \(error)")
            context.rollback()
            transientErrorMessage = "\(String(localized: "error.saveFailed")) \(error.localizedDescription)"

            if reloadAfterFailure {
                fetchTasks(persistRepairs: false)
            } else {
                updateStatusButton()
            }

            return false
        }
    }

    private func updateStatusButton() {
        StatusItemController.shared.updateButton(
            title: currentTask?.title,
            isRunning: isCurrentTaskRunning
        )
    }
}
