//
//  ContentView.swift
//  Stack
//
//  Main view for the stack-based todo list
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

// MARK: - Marquee Text View for scrolling long titles
private struct TextWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let startDelay: Double
    let strikethrough: Bool

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false
    @State private var animationToken = UUID()

    init(_ text: String, font: Font = .headline, startDelay: Double = 1.0, strikethrough: Bool = false) {
        self.text = text
        self.font = font
        self.startDelay = startDelay
        self.strikethrough = strikethrough
    }

    private var needsScroll: Bool {
        textWidth > containerWidth + 5
    }

    private var scrollDistance: CGFloat {
        max(0, textWidth - containerWidth + 15)
    }

    private var scrollDuration: Double {
        // Consistent speed: 30 points per second
        max(1.5, Double(scrollDistance) / 30.0)
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .strikethrough(strikethrough)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { textGeo in
                        Color.clear.preference(key: TextWidthPreferenceKey.self, value: textGeo.size.width)
                    }
                )
                .offset(x: offset)
                .frame(width: geometry.size.width, alignment: .leading)
                .onAppear {
                    containerWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
        }
        .clipped()
        .onPreferenceChange(TextWidthPreferenceKey.self) { width in
            if abs(textWidth - width) > 1 {
                textWidth = width
            }
        }
        .onChange(of: text) {
            // Text changed - reset everything
            stopAnimation()
            offset = 0
            animationToken = UUID()
        }
        .onChange(of: needsScroll) { _, shouldScroll in
            if shouldScroll && !isAnimating {
                scheduleAnimation()
            } else if !shouldScroll {
                stopAnimation()
            }
        }
        .onAppear {
            if needsScroll {
                scheduleAnimation()
            }
        }
    }

    private func stopAnimation() {
        isAnimating = false
        animationToken = UUID()
        withAnimation(.none) {
            offset = 0
        }
    }

    private func scheduleAnimation() {
        guard needsScroll, !isAnimating else { return }
        isAnimating = true
        let token = animationToken

        // Initial delay before scrolling starts
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard token == animationToken, isAnimating, needsScroll else {
                isAnimating = false
                return
            }
            performScrollCycle(token: token)
        }
    }

    private func performScrollCycle(token: UUID) {
        guard token == animationToken, isAnimating, needsScroll else {
            isAnimating = false
            return
        }

        let duration = scrollDuration

        // Scroll to the end
        withAnimation(.linear(duration: duration)) {
            offset = -scrollDistance
        }

        // Wait for scroll to complete, then pause at end
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
            guard token == animationToken, isAnimating else { return }

            // Reset to start (no animation)
            withAnimation(.none) {
                offset = 0
            }

            // Wait, then scroll again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard token == animationToken, isAnimating, needsScroll else {
                    isAnimating = false
                    return
                }
                performScrollCycle(token: token)
            }
        }
    }
}

struct InlineMessageView: View {
    let text: String
    let systemImage: String
    let tint: Color
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "error.dismiss"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
    }
}

struct ContentView: View {
    @Bindable var taskManager: TaskManager
    @State private var showingAddTask = false
    @State private var focusedSection: FocusSection = .inProgress
    @State private var focusedIndex: Int = 0
    @FocusState private var isAddFieldFocused: Bool
    @State private var editingTaskID: UUID? = nil
    @State private var editingTaskTitle: String = ""
    @State private var showingHelp = false
    @State private var keyboardMonitor: Any?

    enum FocusSection {
        case inProgress
        case completed
    }

    /// Start editing a task
    func startEditing(task: StackTask) {
        editingTaskID = task.id
        editingTaskTitle = task.title
    }

    /// Confirm the edit
    func confirmEdit() {
        if let taskID = editingTaskID {
            // Find the task and rename it
            if let task = taskManager.inProgressTasks.first(where: { $0.id == taskID }) {
                taskManager.renameTask(task, to: editingTaskTitle)
            } else if let task = taskManager.completedTasks.first(where: { $0.id == taskID }) {
                taskManager.renameTask(task, to: editingTaskTitle)
            }
        }
        cancelEdit()
    }

    /// Cancel editing
    func cancelEdit() {
        editingTaskID = nil
        editingTaskTitle = ""
    }

    /// Start editing the currently focused task
    func startEditingFocused() {
        if focusedSection == .inProgress {
            if focusedIndex < taskManager.inProgressTasks.count {
                startEditing(task: taskManager.inProgressTasks[focusedIndex])
            }
        } else {
            if focusedIndex < taskManager.completedTasks.count {
                startEditing(task: taskManager.completedTasks[focusedIndex])
            }
        }
    }

    private var desiredPopoverHeight: CGFloat {
        let warningCount = (taskManager.storageWarningMessage == nil ? 0 : 1) + (taskManager.transientErrorMessage == nil ? 0 : 1)
        let warningHeight = CGFloat(warningCount) * 64

        if showingHelp {
            return 700
        }

        if taskManager.inProgressTasks.isEmpty && taskManager.completedTasks.isEmpty {
            return (showingAddTask ? 360 : 320) + warningHeight
        }

        return 700
    }

    var body: some View {
        Group {
            if showingHelp {
                ShortcutsHelpView(onClose: { showingHelp = false })
            } else {
                VStack(spacing: 0) {
                    if let warningMessage = taskManager.storageWarningMessage {
                        InlineMessageView(
                            text: warningMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                        .padding(.horizontal)
                        .padding(.top)
                    }

                    if let transientErrorMessage = taskManager.transientErrorMessage {
                        InlineMessageView(
                            text: transientErrorMessage,
                            systemImage: "exclamationmark.octagon.fill",
                            tint: .red,
                            onDismiss: { taskManager.dismissTransientError() }
                        )
                        .padding(.horizontal)
                        .padding(.top, taskManager.storageWarningMessage == nil ? 16 : 8)
                    }

                    // Header with current task
                    CurrentTaskHeader(
                        taskManager: taskManager,
                        isFocused: focusedSection == .inProgress && focusedIndex == 0,
                        editingTaskID: $editingTaskID,
                        editingTaskTitle: $editingTaskTitle,
                        onConfirmEdit: confirmEdit
                    )
                    .onTapGesture {
                        focusedSection = .inProgress
                        focusedIndex = 0
                    }

                    Divider()

                    Group {
                        // In-progress task list (excluding current task shown in header)
                        if taskManager.inProgressTasks.count > 1 {
                            InProgressTaskListView(
                                taskManager: taskManager,
                                focusedSection: $focusedSection,
                                focusedIndex: $focusedIndex,
                                editingTaskID: $editingTaskID,
                                editingTaskTitle: $editingTaskTitle,
                                onConfirmEdit: confirmEdit
                            )
                            Divider()
                        } else if taskManager.inProgressTasks.isEmpty {
                            EmptyStateView()
                            Divider()
                        }

                        // Completed tasks section
                        if !taskManager.completedTasks.isEmpty {
                            CompletedTaskListView(
                                taskManager: taskManager,
                                focusedSection: $focusedSection,
                                focusedIndex: $focusedIndex,
                                editingTaskID: $editingTaskID,
                                editingTaskTitle: $editingTaskTitle,
                                onConfirmEdit: confirmEdit
                            )
                            Divider()
                        }
                    }
                    .id(
                        taskManager.inProgressTasks.map(\.id.uuidString).joined(separator: ",") + "|" +
                        taskManager.completedTasks.map(\.id.uuidString).joined(separator: ",")
                    )

                    // Add task section
                    AddTaskSection(taskManager: taskManager, showingAddTask: $showingAddTask, isAddFieldFocused: $isAddFieldFocused)

                    Divider()

                    // Footer with shortcuts and quit
                    FooterView()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupKeyboardMonitoring()
            resetFocusToActiveTask()
            updatePopoverHeight()
        }
        .onDisappear {
            teardownKeyboardMonitoring()
        }
        .onChange(of: desiredPopoverHeight) { _, _ in
            updatePopoverHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            resetFocusToActiveTask()
            updatePopoverHeight()
        }
    }

    private func resetFocusToActiveTask() {
        focusedSection = .inProgress
        focusedIndex = 0
        showingHelp = false
        isAddFieldFocused = false
    }

    private func updatePopoverHeight() {
        StatusItemController.shared.updatePopoverHeight(desiredPopoverHeight)
    }

    private func setupKeyboardMonitoring() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle ⌘/ to toggle help
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "/" {
                showingHelp.toggle()
                return nil
            }

            // When showing help, only handle Escape or ⌘? to close
            if showingHelp {
                if event.keyCode == 53 { // Escape
                    showingHelp = false
                    return nil
                }
                return event
            }

            // Handle keys when add task field is active
            if showingAddTask {
                // Escape to cancel add task mode
                if event.keyCode == 53 {
                    cancelAddTask()
                    return nil
                }
                // Cmd+Enter to add as active task
                if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                    submitAddTask(makeActive: true)
                    return nil
                }
                // Ctrl+Enter to add to the bottom of the stack
                if event.keyCode == 36 && event.modifierFlags.contains(.control) {
                    submitAddTask(insertAtBottom: true)
                    return nil
                }
                // Let all other keys pass through to the text field
                return event
            }

            // Don't intercept keys when editing a task
            if editingTaskID != nil {
                if event.keyCode == 53 { // Escape - cancel edit
                    cancelEdit()
                    return nil
                }
                if event.keyCode == 36 { // Return/Enter - confirm edit
                    confirmEdit()
                    return nil
                }
                // Let all other keys pass through to the text field
                return event
            }

            // Handle Command shortcuts
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "n":
                    showingAddTask = true
                    isAddFieldFocused = true
                    return nil
                case "a":
                    makeCurrentFocusedActive()
                    return nil
                case "d":
                    deleteCurrentFocused()
                    return nil
                case "c":
                    toggleCurrentFocusedCompletion()
                    return nil
                case "s":
                    taskManager.toggleCurrentTaskTimer()
                    return nil
                case "r":
                    startEditingFocused()
                    return nil
                case "z":
                    if event.modifierFlags.contains(.shift) {
                        taskManager.redo()
                    } else {
                        taskManager.undo()
                    }
                    return nil
                case "q":
                    NSApplication.shared.terminate(nil)
                    return nil
                default:
                    break
                }
            }

            // Handle arrow keys for navigation and reordering
            let isCommandPressed = event.modifierFlags.contains(.command)

            switch event.keyCode {
            case 126: // Up arrow
                if isCommandPressed {
                    moveCurrentFocusedUp()
                } else {
                    navigateUp()
                }
                return nil

            case 125: // Down arrow
                if isCommandPressed {
                    moveCurrentFocusedDown()
                } else {
                    navigateDown()
                }
                return nil

            case 36: // Return/Enter - toggle completion of focused task
                toggleCurrentFocusedCompletion()
                return nil

            case 53: // Escape - clear focus / reset to first
                focusedSection = .inProgress
                focusedIndex = 0
                return nil

            default:
                break
            }

            // Handle number keys 0-9 for quick task selection (in-progress only)
            if let chars = event.charactersIgnoringModifiers, chars.count == 1,
               let digit = chars.first, digit.isNumber,
               !event.modifierFlags.contains(.command) {
                let num = digit.wholeNumberValue ?? 0
                // 1 = index 0 (active task), 2-9 = index 1-8, 0 = index 9
                let targetIndex = num == 0 ? 9 : num - 1
                if targetIndex < taskManager.inProgressTasks.count {
                    focusedSection = .inProgress
                    focusedIndex = targetIndex
                    return nil
                }
            }

            return event
        }
    }

    private func teardownKeyboardMonitoring() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func submitAddTask(makeActive: Bool = false, insertAtBottom: Bool = false) {
        let title = taskManager.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isAddFieldFocused = false
        taskManager.addTask(title: title, makeActive: makeActive, insertAtBottom: insertAtBottom)
        taskManager.newTaskTitle = ""
        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func cancelAddTask() {
        isAddFieldFocused = false
        taskManager.newTaskTitle = ""
        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func navigateUp() {
        if focusedSection == .inProgress {
            if focusedIndex > 0 {
                focusedIndex -= 1
            }
        } else {
            // In completed section
            if focusedIndex > 0 {
                focusedIndex -= 1
            } else if !taskManager.inProgressTasks.isEmpty {
                // Move to in-progress section
                focusedSection = .inProgress
                focusedIndex = taskManager.inProgressTasks.count - 1
            }
        }
    }

    private func navigateDown() {
        if focusedSection == .inProgress {
            if focusedIndex < taskManager.inProgressTasks.count - 1 {
                focusedIndex += 1
            } else if !taskManager.completedTasks.isEmpty {
                // Move to completed section
                focusedSection = .completed
                focusedIndex = 0
            }
        } else {
            // In completed section
            if focusedIndex < taskManager.completedTasks.count - 1 {
                focusedIndex += 1
            }
        }
    }

    private func moveCurrentFocusedUp() {
        if focusedSection == .inProgress && focusedIndex > 0 {
            taskManager.moveInProgressTaskUp(at: focusedIndex)
            focusedIndex -= 1
        }
        // Can't reorder completed tasks
    }

    private func moveCurrentFocusedDown() {
        if focusedSection == .inProgress && focusedIndex < taskManager.inProgressTasks.count - 1 {
            taskManager.moveInProgressTaskDown(at: focusedIndex)
            focusedIndex += 1
        }
        // Can't reorder completed tasks
    }

    private func toggleCurrentFocusedCompletion() {
        if focusedSection == .inProgress {
            if focusedIndex < taskManager.inProgressTasks.count {
                taskManager.toggleInProgressTaskCompletion(at: focusedIndex)
                // After completing, stay in same position or adjust if needed
                if focusedIndex >= taskManager.inProgressTasks.count {
                    if taskManager.inProgressTasks.isEmpty {
                        focusedSection = .completed
                        focusedIndex = 0
                    } else {
                        focusedIndex = taskManager.inProgressTasks.count - 1
                    }
                }
            }
        } else {
            if focusedIndex < taskManager.completedTasks.count {
                taskManager.toggleCompletedTaskCompletion(at: focusedIndex)
                // After uncompleting, move focus to in-progress section
                focusedSection = .inProgress
                focusedIndex = 0
            }
        }
    }

    private func deleteCurrentFocused() {
        if focusedSection == .inProgress {
            if focusedIndex < taskManager.inProgressTasks.count {
                taskManager.removeInProgressTask(at: focusedIndex)
                if focusedIndex >= taskManager.inProgressTasks.count && taskManager.inProgressTasks.count > 0 {
                    focusedIndex = taskManager.inProgressTasks.count - 1
                } else if taskManager.inProgressTasks.isEmpty && !taskManager.completedTasks.isEmpty {
                    focusedSection = .completed
                    focusedIndex = 0
                }
            }
        } else {
            if focusedIndex < taskManager.completedTasks.count {
                taskManager.removeCompletedTask(at: focusedIndex)
                if focusedIndex >= taskManager.completedTasks.count && taskManager.completedTasks.count > 0 {
                    focusedIndex = taskManager.completedTasks.count - 1
                } else if taskManager.completedTasks.isEmpty && !taskManager.inProgressTasks.isEmpty {
                    focusedSection = .inProgress
                    focusedIndex = 0
                }
            }
        }
    }

    private func makeCurrentFocusedActive() {
        if focusedSection == .inProgress && focusedIndex > 0 && focusedIndex < taskManager.inProgressTasks.count {
            // Make the focused in-progress task the active task
            taskManager.makeInProgressTaskActive(at: focusedIndex)
            // Move focus to the now-active task
            focusedIndex = 0
        }
        // Do nothing if already on active task or in completed section
    }
}

// MARK: - Current Task Header

struct CurrentTaskHeader: View {
    let taskManager: TaskManager
    let isFocused: Bool
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var currentTime = Date()
    @FocusState private var isEditFieldFocused: Bool

    private var isEditing: Bool {
        if let currentTask = taskManager.currentTask {
            return editingTaskID == currentTask.id
        }
        return false
    }

    /// Format duration using currentTime to force SwiftUI updates
    private func formattedDuration(for task: StackTask) -> String {
        // Reference currentTime to establish SwiftUI dependency
        _ = currentTime

        var duration = task.totalDuration
        if let started = task.startedAt {
            duration += Date().timeIntervalSince(started)
        }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("section.currentTask", tableName: "Localizable")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let currentTask = taskManager.currentTask {
                let isRunning = taskManager.isCurrentTaskRunning

                HStack(spacing: 12) {
                    // Play/Pause button
                    VStack(spacing: 6) {
                        Button {
                            taskManager.toggleCurrentTaskTimer()
                        } label: {
                            Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title)
                                .foregroundStyle(isRunning ? .orange : .green)
                        }
                        .buttonStyle(.plain)
                        .help(isRunning ? String(localized: "hint.pause") : String(localized: "hint.resume"))

                        Text("⌘S")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if isEditing {
                            TextField(String(localized: "task.titlePlaceholder"), text: $editingTaskTitle)
                                .font(.headline)
                                .textFieldStyle(.plain)
                                .focused($isEditFieldFocused)
                                .onSubmit {
                                    onConfirmEdit()
                                }
                                .onAppear {
                                    isEditFieldFocused = true
                                }
                        } else {
                            MarqueeText(currentTask.title, font: .headline)
                                .foregroundStyle(.primary)
                                .frame(height: 20)
                                .onTapGesture(count: 2) {
                                    editingTaskID = currentTask.id
                                    editingTaskTitle = currentTask.title
                                }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: isRunning ? "clock" : "pause")
                                .font(.caption2)
                            Text(formattedDuration(for: currentTask))
                            if !isRunning {
                                Text("task.paused", tableName: "Localizable")
                                    .font(.caption2)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(isRunning ? .secondary : .orange)
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        Button {
                            taskManager.removeCurrentTask()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "hint.removeTask"))

                        Text("⌘D")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color.accentColor.opacity(0.2) : Color.accentColor.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .onReceive(timer) { newTime in
                    currentTime = newTime  // Force refresh to update duration display
                }
            } else {
                Text("emptyState.noTasks", tableName: "Localizable")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("emptyState.title", tableName: "Localizable")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("emptyState.hint", tableName: "Localizable")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 28)
    }
}

// MARK: - In-Progress Task List

struct InProgressTaskListView: View {
    let taskManager: TaskManager
    @Binding var focusedSection: ContentView.FocusSection
    @Binding var focusedIndex: Int
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void
    @State private var draggingTask: StackTask?

    private var visibleTaskCount: Int {
        max(0, taskManager.inProgressTasks.count - 1)
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(visibleTaskCount) * 40 + 8, visibleTaskCount > 0 ? 52 : 0), 300)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("section.upNext", tableName: "Localizable")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    taskManager.removeAllInProgressTasks()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "trash")
                        Text("task.deleteAll", tableName: "Localizable")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(taskManager.inProgressTasks.dropFirst().enumerated()), id: \.element.id) { index, task in
                        let actualIndex = index + 1
                        InProgressTaskRow(
                            task: task,
                            position: index + 2,
                            taskManager: taskManager,
                            isFocused: focusedSection == .inProgress && focusedIndex == actualIndex,
                            editingTaskID: $editingTaskID,
                            editingTaskTitle: $editingTaskTitle,
                            onConfirmEdit: onConfirmEdit
                        )
                        .onTapGesture {
                            focusedSection = .inProgress
                            focusedIndex = actualIndex
                        }
                        .onDrag {
                            draggingTask = task
                            return NSItemProvider(object: task.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: InProgressTaskDropDelegate(
                            task: task,
                            taskManager: taskManager,
                            draggingTask: $draggingTask
                        ))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .frame(height: listHeight)
            .clipped()
        }
    }
}

struct InProgressTaskRow: View {
    let task: StackTask
    let position: Int
    let taskManager: TaskManager
    let isFocused: Bool
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void
    @FocusState private var isEditFieldFocused: Bool

    private var isEditing: Bool {
        editingTaskID == task.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text("\(position)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            VStack(spacing: 2) {
                Button {
                    taskManager.completeTask(task)
                } label: {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextField(String(localized: "task.titlePlaceholder"), text: $editingTaskTitle)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .focused($isEditFieldFocused)
                    .onSubmit {
                        onConfirmEdit()
                    }
                    .onAppear {
                        isEditFieldFocused = true
                    }
            } else {
                MarqueeText(task.title, font: .subheadline, startDelay: 2.0)
                    .foregroundStyle(.primary)
                    .frame(height: 18)
                    .onTapGesture(count: 2) {
                        editingTaskID = task.id
                        editingTaskTitle = task.title
                    }
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Button {
                    taskManager.removeTask(task)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)

                if isFocused {
                    Text("⌘D")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

struct InProgressTaskDropDelegate: DropDelegate {
    let task: StackTask
    let taskManager: TaskManager
    @Binding var draggingTask: StackTask?

    func performDrop(info: DropInfo) -> Bool {
        draggingTask = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingTask = draggingTask,
              draggingTask.id != task.id else { return }

        guard let fromIndex = taskManager.inProgressTasks.firstIndex(where: { $0.id == draggingTask.id }),
              let toIndex = taskManager.inProgressTasks.firstIndex(where: { $0.id == task.id }) else { return }

        if fromIndex != toIndex {
            taskManager.moveInProgressTask(from: fromIndex, to: toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Completed Task List

struct CompletedTaskListView: View {
    let taskManager: TaskManager
    @Binding var focusedSection: ContentView.FocusSection
    @Binding var focusedIndex: Int
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void

    private var visibleTaskCount: Int {
        taskManager.completedTasks.count
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(visibleTaskCount) * 36 + 8, visibleTaskCount > 0 ? 48 : 0), 150)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("section.completed", tableName: "Localizable")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    taskManager.removeAllCompletedTasks()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "trash")
                        Text("task.deleteAll", tableName: "Localizable")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(taskManager.completedTasks.enumerated()), id: \.element.id) { index, task in
                        CompletedTaskRow(
                            task: task,
                            taskManager: taskManager,
                            isFocused: focusedSection == .completed && focusedIndex == index,
                            editingTaskID: $editingTaskID,
                            editingTaskTitle: $editingTaskTitle,
                            onConfirmEdit: onConfirmEdit
                        )
                        .onTapGesture {
                            focusedSection = .completed
                            focusedIndex = index
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .frame(height: listHeight)
            .clipped()
        }
    }
}

struct CompletedTaskRow: View {
    let task: StackTask
    let taskManager: TaskManager
    let isFocused: Bool
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void
    @FocusState private var isEditFieldFocused: Bool

    private var isEditing: Bool {
        editingTaskID == task.id
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Button {
                    taskManager.uncompleteTask(task)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextField(String(localized: "task.titlePlaceholder"), text: $editingTaskTitle)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .focused($isEditFieldFocused)
                    .onSubmit {
                        onConfirmEdit()
                    }
                    .onAppear {
                        isEditFieldFocused = true
                    }
            } else {
                MarqueeText(task.title, font: .subheadline, startDelay: 2.0)
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
                    .onTapGesture(count: 2) {
                        editingTaskID = task.id
                        editingTaskTitle = task.title
                    }
            }

            Spacer(minLength: 8)

            Text(task.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            VStack(spacing: 2) {
                Button {
                    taskManager.removeTask(task)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.6)

                if isFocused {
                    Text("⌘D")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.green.opacity(0.1) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.green : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Add Task Section

struct AddTaskSection: View {
    @Bindable var taskManager: TaskManager
    @Binding var showingAddTask: Bool
    @FocusState.Binding var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if showingAddTask {
                HStack(spacing: 8) {
                    TextField(String(localized: "task.newTaskPlaceholder"), text: $taskManager.newTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .focused($isAddFieldFocused)
                        .onSubmit {
                            addTask()
                        }
                        .onExitCommand {
                            cancelAdd()
                        }

                    Button(String(localized: "task.add")) {
                        addTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(taskManager.newTaskTitle.isEmpty)

                    Button(String(localized: "task.cancel")) {
                        cancelAdd()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Button {
                        showingAddTask = true
                        isAddFieldFocused = true
                    } label: {
                        Label(String(localized: "task.newTask"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("⌘N")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func addTask(makeActive: Bool = false) {
        let title = taskManager.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isAddFieldFocused = false
        taskManager.addTask(title: title, makeActive: makeActive)
        taskManager.newTaskTitle = ""
        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func cancelAdd() {
        isAddFieldFocused = false
        taskManager.newTaskTitle = ""
        DispatchQueue.main.async {
            showingAddTask = false
        }
    }
}

// MARK: - Shortcuts Help View

struct ShortcutsHelpView: View {
    let onClose: () -> Void

    private var shortcuts: [(key: String, descriptionKey: String)] {
        [
            ("⌘N", "shortcut.newTask"),
            ("⌘A", "shortcut.makeActive"),
            ("⌘S", "shortcut.startStop"),
            ("⌘C", "shortcut.complete"),
            ("⌘D", "shortcut.delete"),
            ("⌘R", "shortcut.rename"),
            ("⌘Z", "shortcut.undo"),
            ("⌘⇧Z", "shortcut.redo"),
            ("↑↓", "shortcut.navigate"),
            ("⌘↑↓", "shortcut.reorder"),
            ("⌃⌥S", "shortcut.openStack"),
            ("⌘/", "shortcut.toggleHelp"),
            ("⌘Q", "shortcut.quit"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("help.title", tableName: "Localizable")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Shortcuts list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(shortcuts, id: \.key) { shortcut in
                        HStack {
                            Text(shortcut.key)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .frame(width: 60, alignment: .leading)

                            Text(LocalizedStringKey(shortcut.descriptionKey), tableName: "Localizable")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        if shortcut.key != shortcuts.last?.key {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
            }

            Divider()

            // Footer hint
            Text("help.closeHint", tableName: "Localizable")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        HStack(spacing: 8) {
            ShortcutHint(key: "⌃⌥S", actionKey: "footer.showStack")
            ShortcutHint(key: "⌘/", actionKey: "footer.showShortcuts")
            ShortcutHint(key: "⌘Q", actionKey: "footer.quit")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct ShortcutHint: View {
    let key: String
    let actionKey: String

    var body: some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                )
            Text(LocalizedStringKey(actionKey), tableName: "Localizable")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView(taskManager: TaskManager())
        .frame(width: 320, height: 500)
}
