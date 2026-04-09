//
//  TaskManager.swift
//  Stack
//
//  Manages the stack of tasks
//

import Foundation
import SwiftData

@Observable
@MainActor
final class TaskManager {
    var modelContext: ModelContext?
    var storageWarningMessage: String?
    var transientErrorMessage: String?
    var inProgressTasks: [StackTask] = []
    var completedTasks: [StackTask] = []

    var currentTask: StackTask? {
        inProgressTasks.first
    }

    var isCurrentTaskRunning: Bool {
        currentTask?.startedAt != nil
    }

    func configurePersistence(context: ModelContext, warningMessage: String? = nil) {
        modelContext = context
        storageWarningMessage = warningMessage
        fetchTasks()
    }

    func dismissTransientError() {
        transientErrorMessage = nil
    }

    func fetchTasks(persistRepairs: Bool = true) {
        guard let context = modelContext else { return }

        let inProgressDescriptor = FetchDescriptor<StackTask>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.order, order: .reverse)]
        )
        let completedDescriptor = FetchDescriptor<StackTask>(
            predicate: #Predicate { $0.isCompleted },
            sortBy: [SortDescriptor(\.completedOrder, order: .reverse)]
        )

        do {
            inProgressTasks = try context.fetch(inProgressDescriptor)
            completedTasks = try context.fetch(completedDescriptor)

            let repairedState = repairTaskState()
            transientErrorMessage = nil

            if repairedState && persistRepairs {
                _ = saveContext(refreshAfterSuccess: false, reloadAfterFailure: true)
                return
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

    func addTask(title: String, makeActive: Bool = false) {
        guard let context = modelContext else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let newTask = StackTask(title: trimmedTitle)
        context.insert(newTask)

        if currentTask == nil || makeActive {
            currentTask?.stopTimer()
            applyInProgressOrder([newTask] + inProgressTasks)
            newTask.startTimer()
        } else if let currentTask {
            applyInProgressOrder([currentTask, newTask] + Array(inProgressTasks.dropFirst()))
        } else {
            applyInProgressOrder([newTask])
            newTask.startTimer()
        }

        saveAndRefresh()
    }

    func removeCurrentTask() {
        guard !inProgressTasks.isEmpty else { return }
        removeInProgressTask(at: 0)
    }

    func toggleCurrentTaskCompletion() {
        guard let currentTask else { return }
        completeTask(currentTask)
    }

    func completeTask(_ task: StackTask) {
        let wasCurrentTask = task.id == currentTask?.id
        let remainingTasks = inProgressTasks.filter { $0.id != task.id }

        task.stopTimer()
        task.startedAt = nil
        task.isCompleted = true
        task.completedAt = Date()
        task.completedOrder = completedTasks.count

        applyInProgressOrder(remainingTasks)

        if wasCurrentTask {
            remainingTasks.first?.startTimer()
        }

        saveAndRefresh()
    }

    func uncompleteTask(_ task: StackTask) {
        currentTask?.stopTimer()

        task.isCompleted = false
        task.completedAt = nil
        applyCompletedOrder(completedTasks.filter { $0.id != task.id })
        applyInProgressOrder([task] + inProgressTasks)
        task.startTimer()

        saveAndRefresh()
    }

    func toggleCurrentTaskTimer() {
        guard let currentTask else { return }

        if currentTask.startedAt != nil {
            currentTask.stopTimer()
        } else {
            currentTask.startTimer()
        }

        saveAndRefresh()
    }

    func stopCurrentTaskTimer() {
        guard let currentTask, currentTask.startedAt != nil else { return }

        currentTask.stopTimer()
        saveAndRefresh()
    }

    func makeTaskActive(_ task: StackTask) {
        guard !task.isCompleted,
              let taskIndex = inProgressTasks.firstIndex(where: { $0.id == task.id }),
              taskIndex > 0 else { return }

        moveInProgressTask(from: taskIndex, to: 0)
    }

    func makeInProgressTaskActive(at index: Int) {
        guard index > 0 && index < inProgressTasks.count else { return }
        makeTaskActive(inProgressTasks[index])
    }

    func renameTask(_ task: StackTask, to newTitle: String) {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        task.title = trimmedTitle
        saveAndRefresh()
    }

    func removeTask(_ task: StackTask) {
        if let index = inProgressTasks.firstIndex(where: { $0.id == task.id }) {
            removeInProgressTask(at: index)
            return
        }

        if let index = completedTasks.firstIndex(where: { $0.id == task.id }) {
            removeCompletedTask(at: index)
        }
    }

    func toggleInProgressTaskCompletion(at index: Int) {
        guard index >= 0 && index < inProgressTasks.count else { return }
        completeTask(inProgressTasks[index])
    }

    func toggleCompletedTaskCompletion(at index: Int) {
        guard index >= 0 && index < completedTasks.count else { return }
        uncompleteTask(completedTasks[index])
    }

    func moveInProgressTaskUp(at index: Int) {
        guard index > 0 && index < inProgressTasks.count else { return }
        moveInProgressTask(from: index, to: index - 1)
    }

    func moveInProgressTaskDown(at index: Int) {
        guard index >= 0 && index < inProgressTasks.count - 1 else { return }
        moveInProgressTask(from: index, to: index + 1)
    }

    func moveInProgressTask(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0 && sourceIndex < inProgressTasks.count,
              destinationIndex >= 0 && destinationIndex < inProgressTasks.count else { return }

        currentTask?.stopTimer()

        var reorderedTasks = inProgressTasks
        let movedTask = reorderedTasks.remove(at: sourceIndex)
        reorderedTasks.insert(movedTask, at: destinationIndex)
        applyInProgressOrder(reorderedTasks)
        reorderedTasks.first?.startTimer()

        saveAndRefresh()
    }

    func removeInProgressTask(at index: Int) {
        guard let context = modelContext,
              index >= 0 && index < inProgressTasks.count else { return }

        let task = inProgressTasks[index]
        let remainingTasks = inProgressTasks.filter { $0.id != task.id }

        task.stopTimer()
        context.delete(task)
        applyInProgressOrder(remainingTasks)
        remainingTasks.first?.startTimer()

        saveAndRefresh()
    }

    func removeCompletedTask(at index: Int) {
        guard let context = modelContext,
              index >= 0 && index < completedTasks.count else { return }

        let task = completedTasks[index]
        context.delete(task)
        applyCompletedOrder(completedTasks.filter { $0.id != task.id })

        saveAndRefresh()
    }

    func removeAllInProgressTasks() {
        guard let context = modelContext, !inProgressTasks.isEmpty else { return }

        for task in inProgressTasks {
            task.stopTimer()
            context.delete(task)
        }

        saveAndRefresh()
    }

    func removeAllCompletedTasks() {
        guard let context = modelContext, !completedTasks.isEmpty else { return }

        for task in completedTasks {
            context.delete(task)
        }

        saveAndRefresh()
    }

    func prepareForTermination() {
        var changedTasks = false

        for task in inProgressTasks where task.startedAt != nil {
            task.stopTimer()
            changedTasks = true
        }

        for task in completedTasks where task.startedAt != nil {
            task.startedAt = nil
            changedTasks = true
        }

        if changedTasks {
            _ = saveContext(refreshAfterSuccess: false, reloadAfterFailure: false)
        }
    }

    private func repairTaskState() -> Bool {
        var repairedState = false

        for (index, task) in inProgressTasks.enumerated() {
            let expectedOrder = inProgressTasks.count - 1 - index
            if task.order != expectedOrder {
                task.order = expectedOrder
                repairedState = true
            }

            if index > 0, task.startedAt != nil {
                task.startedAt = nil
                repairedState = true
            }
        }

        for (index, task) in completedTasks.enumerated() {
            let expectedOrder = completedTasks.count - 1 - index
            if task.completedOrder != expectedOrder {
                task.completedOrder = expectedOrder
                repairedState = true
            }

            if task.startedAt != nil {
                task.startedAt = nil
                repairedState = true
            }
        }

        return repairedState
    }

    private func applyInProgressOrder(_ tasks: [StackTask]) {
        for (index, task) in tasks.enumerated() {
            task.order = tasks.count - 1 - index
        }
    }

    private func applyCompletedOrder(_ tasks: [StackTask]) {
        for (index, task) in tasks.enumerated() {
            task.completedOrder = tasks.count - 1 - index
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
