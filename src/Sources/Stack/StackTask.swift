//
//  StackTask.swift
//  Stack
//
//  A stack-based todo item model
//

import Foundation
import SwiftData

@Model
final class StackTask {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var startedAt: Date?  // When this task became the active/current task
    var totalDuration: TimeInterval  // Total time spent on this task
    var order: Int  // Higher order = top of stack (for in-progress tasks)
    var completedOrder: Int  // Higher order = more recently completed

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
        self.completedAt = nil
        self.startedAt = nil
        self.totalDuration = 0
        self.order = order
        self.completedOrder = 0
    }

    /// Start tracking time for this task
    func startTimer() {
        if startedAt == nil {
            startedAt = Date()
        }
    }

    /// Stop tracking time and accumulate duration
    func stopTimer() {
        if let started = startedAt {
            totalDuration += Date().timeIntervalSince(started)
            startedAt = nil
        }
    }

    /// Get the current elapsed time (including accumulated)
    func currentDuration(at now: Date = Date()) -> TimeInterval {
        var duration = totalDuration
        if let startedAt {
            duration += now.timeIntervalSince(startedAt)
        }
        return duration
    }

    /// Format duration as human-readable string
    func formattedDuration(at now: Date = Date()) -> String {
        let duration = currentDuration(at: now)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
