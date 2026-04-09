//
//  ContentView.swift
//  Stack
//
//  Main view for the stack-based todo list
//

import AppKit
import SwiftUI

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
                    GeometryReader { textGeometry in
                        Color.clear.preference(key: TextWidthPreferenceKey.self, value: textGeometry.size.width)
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

        withAnimation(.linear(duration: duration)) {
            offset = -scrollDistance
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5) {
            guard token == animationToken, isAnimating else { return }

            withAnimation(.none) {
                offset = 0
            }

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
    @State private var newTaskTitle = ""
    @State private var focusedSection: FocusSection = .inProgress
    @State private var focusedIndex = 0
    @FocusState private var isAddFieldFocused: Bool
    @State private var editingTaskID: UUID?
    @State private var editingTaskTitle = ""
    @State private var showingHelp = false
    @State private var keyboardMonitor: Any?

    enum FocusSection {
        case inProgress
        case completed
    }

    fileprivate static func inProgressListHeight(for taskCount: Int) -> CGFloat {
        let visibleTaskCount = max(0, taskCount - 1)
        return min(max(CGFloat(visibleTaskCount) * 40 + 8, visibleTaskCount > 0 ? 52 : 0), 300)
    }

    fileprivate static func completedListHeight(for taskCount: Int) -> CGFloat {
        min(max(CGFloat(taskCount) * 36 + 8, taskCount > 0 ? 48 : 0), 150)
    }

    func startEditing(task: StackTask) {
        editingTaskID = task.id
        editingTaskTitle = task.title
    }

    func confirmEdit() {
        guard let editingTaskID else {
            cancelEdit()
            return
        }

        if let task = taskManager.inProgressTasks.first(where: { $0.id == editingTaskID }) {
            taskManager.renameTask(task, to: editingTaskTitle)
        } else if let task = taskManager.completedTasks.first(where: { $0.id == editingTaskID }) {
            taskManager.renameTask(task, to: editingTaskTitle)
        }

        cancelEdit()
    }

    func cancelEdit() {
        editingTaskID = nil
        editingTaskTitle = ""
    }

    func startEditingFocused() {
        if focusedSection == .inProgress {
            guard focusedIndex < taskManager.inProgressTasks.count else { return }
            startEditing(task: taskManager.inProgressTasks[focusedIndex])
            return
        }

        guard focusedIndex < taskManager.completedTasks.count else { return }
        startEditing(task: taskManager.completedTasks[focusedIndex])
    }

    private var layoutSignature: String {
        [
            String(showingHelp),
            String(showingAddTask),
            String(taskManager.inProgressTasks.count),
            String(taskManager.completedTasks.count),
            String(taskManager.storageWarningMessage != nil),
            String(taskManager.transientErrorMessage != nil),
            editingTaskID?.uuidString ?? ""
        ].joined(separator: "|")
    }

    private var currentShortcutMode: KeyboardShortcutMode {
        if showingHelp {
            return .help
        }
        if showingAddTask {
            return .add
        }
        if editingTaskID != nil {
            return .rename
        }
        return .main
    }

    var body: some View {
        Group {
            if showingHelp {
                ShortcutsHelpView()
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

                    AddTaskSection(
                        newTaskTitle: $newTaskTitle,
                        showingAddTask: $showingAddTask,
                        isAddFieldFocused: $isAddFieldFocused,
                        onAddTask: submitAddTask
                    )

                    Divider()

                    ShortcutReferenceSection()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor).ignoresSafeArea())
        .onAppear {
            setupKeyboardMonitoring()
            resetFocusToActiveTask()
            updatePopoverHeight()
        }
        .onDisappear {
            teardownKeyboardMonitoring()
        }
        .onChange(of: layoutSignature) { _, _ in
            updatePopoverHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            resetFocusToActiveTask()
            updatePopoverHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleHelpView)) { _ in
            showingHelp.toggle()
            updatePopoverHeight()
        }
    }

    private func resetFocusToActiveTask() {
        focusedSection = .inProgress
        focusedIndex = 0
        showingHelp = false
        showingAddTask = false
        newTaskTitle = ""
        isAddFieldFocused = false
        cancelEdit()
    }

    private func updatePopoverHeight() {
        StatusItemController.shared.updatePopoverHeight()

        DispatchQueue.main.async {
            StatusItemController.shared.updatePopoverHeight()
        }
    }

    private func setupKeyboardMonitoring() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let action = KeyboardShortcutRegistry.firstMatchingAction(for: event, mode: currentShortcutMode) else {
                return event
            }

            handleShortcutAction(action, event: event)
            return nil
        }
    }

    private func teardownKeyboardMonitoring() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }

    private func handleShortcutAction(_ action: KeyboardShortcutAction, event: NSEvent) {
        switch action {
        case .togglePopover:
            break
        case .toggleHelp:
            showingHelp.toggle()
        case .closeHelp:
            showingHelp = false
        case .newTask:
            showingAddTask = true
            isAddFieldFocused = true
        case .makeActive:
            makeCurrentFocusedActive()
        case .toggleTimer:
            taskManager.toggleCurrentTaskTimer()
        case .toggleCompletion:
            toggleCurrentFocusedCompletion()
        case .deleteTask:
            deleteCurrentFocused()
        case .renameTask:
            startEditingFocused()
        case .quit:
            NSApplication.shared.terminate(nil)
        case .navigateUp:
            navigateUp()
        case .navigateDown:
            navigateDown()
        case .reorderUp:
            moveCurrentFocusedUp()
        case .reorderDown:
            moveCurrentFocusedDown()
        case .resetFocus:
            focusedSection = .inProgress
            focusedIndex = 0
        case .addTask:
            submitAddTask()
        case .addActiveTask:
            submitAddTask(makeActive: true)
        case .cancelAdd:
            cancelAddTask()
        case .confirmRename:
            confirmEdit()
        case .cancelRename:
            cancelEdit()
        }
    }

    private func submitAddTask(makeActive: Bool = false) {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isAddFieldFocused = false
        taskManager.addTask(title: title, makeActive: makeActive)
        newTaskTitle = ""

        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func cancelAddTask() {
        isAddFieldFocused = false
        newTaskTitle = ""

        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func navigateUp() {
        if focusedSection == .inProgress {
            if focusedIndex > 0 {
                focusedIndex -= 1
            }
            return
        }

        if focusedIndex > 0 {
            focusedIndex -= 1
        } else if !taskManager.inProgressTasks.isEmpty {
            focusedSection = .inProgress
            focusedIndex = taskManager.inProgressTasks.count - 1
        }
    }

    private func navigateDown() {
        if focusedSection == .inProgress {
            if focusedIndex < taskManager.inProgressTasks.count - 1 {
                focusedIndex += 1
            } else if !taskManager.completedTasks.isEmpty {
                focusedSection = .completed
                focusedIndex = 0
            }
            return
        }

        if focusedIndex < taskManager.completedTasks.count - 1 {
            focusedIndex += 1
        }
    }

    private func moveCurrentFocusedUp() {
        guard focusedSection == .inProgress, focusedIndex > 0 else { return }
        taskManager.moveInProgressTaskUp(at: focusedIndex)
        focusedIndex -= 1
    }

    private func moveCurrentFocusedDown() {
        guard focusedSection == .inProgress,
              focusedIndex < taskManager.inProgressTasks.count - 1 else { return }

        taskManager.moveInProgressTaskDown(at: focusedIndex)
        focusedIndex += 1
    }

    private func toggleCurrentFocusedCompletion() {
        if focusedSection == .inProgress {
            guard focusedIndex < taskManager.inProgressTasks.count else { return }
            taskManager.toggleInProgressTaskCompletion(at: focusedIndex)

            if focusedIndex >= taskManager.inProgressTasks.count {
                if taskManager.inProgressTasks.isEmpty {
                    focusedSection = .completed
                    focusedIndex = 0
                } else {
                    focusedIndex = taskManager.inProgressTasks.count - 1
                }
            }
            return
        }

        guard focusedIndex < taskManager.completedTasks.count else { return }
        taskManager.toggleCompletedTaskCompletion(at: focusedIndex)
        focusedSection = .inProgress
        focusedIndex = 0
    }

    private func deleteCurrentFocused() {
        if focusedSection == .inProgress {
            guard focusedIndex < taskManager.inProgressTasks.count else { return }
            taskManager.removeInProgressTask(at: focusedIndex)

            if focusedIndex >= taskManager.inProgressTasks.count && !taskManager.inProgressTasks.isEmpty {
                focusedIndex = taskManager.inProgressTasks.count - 1
            } else if taskManager.inProgressTasks.isEmpty && !taskManager.completedTasks.isEmpty {
                focusedSection = .completed
                focusedIndex = 0
            }
            return
        }

        guard focusedIndex < taskManager.completedTasks.count else { return }
        taskManager.removeCompletedTask(at: focusedIndex)

        if focusedIndex >= taskManager.completedTasks.count && !taskManager.completedTasks.isEmpty {
            focusedIndex = taskManager.completedTasks.count - 1
        } else if taskManager.completedTasks.isEmpty && !taskManager.inProgressTasks.isEmpty {
            focusedSection = .inProgress
            focusedIndex = 0
        }
    }

    private func makeCurrentFocusedActive() {
        guard focusedSection == .inProgress,
              focusedIndex > 0,
              focusedIndex < taskManager.inProgressTasks.count else { return }

        taskManager.makeInProgressTaskActive(at: focusedIndex)
        focusedIndex = 0
    }
}

struct CurrentTaskHeader: View {
    let taskManager: TaskManager
    let isFocused: Bool
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void
    @FocusState private var isEditFieldFocused: Bool

    private var isEditing: Bool {
        guard let currentTask = taskManager.currentTask else { return false }
        return editingTaskID == currentTask.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let currentTask = taskManager.currentTask {
                let isRunning = taskManager.isCurrentTaskRunning

                HStack(spacing: 12) {
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

                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            HStack(spacing: 4) {
                                Image(systemName: isRunning ? "clock" : "pause")
                                    .font(.caption2)
                                Text(currentTask.formattedDuration(at: timeline.date))

                                if !isRunning {
                                    Text("task.paused", tableName: "Localizable")
                                        .font(.caption2)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(isRunning ? Color.secondary : Color.orange)
                        }
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
                        .fill(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.32) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear, lineWidth: 2)
                )
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

struct InProgressTaskListView: View {
    let taskManager: TaskManager
    @Binding var focusedSection: ContentView.FocusSection
    @Binding var focusedIndex: Int
    @Binding var editingTaskID: UUID?
    @Binding var editingTaskTitle: String
    let onConfirmEdit: () -> Void

    private var visibleTaskCount: Int {
        max(0, taskManager.inProgressTasks.count - 1)
    }

    private var listHeight: CGFloat {
        ContentView.inProgressListHeight(for: taskManager.inProgressTasks.count)
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
            Text("\(position)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .frame(width: 20)

            Button {
                taskManager.completeTask(task)
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

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
                .fill(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

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
        ContentView.completedListHeight(for: taskManager.completedTasks.count)
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
            Button {
                taskManager.uncompleteTask(task)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

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

            Text(task.formattedDuration())
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
                .fill(isFocused ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.24) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

struct AddTaskSection: View {
    @Binding var newTaskTitle: String
    @Binding var showingAddTask: Bool
    @FocusState.Binding var isAddFieldFocused: Bool
    let onAddTask: (Bool) -> Void

    private var canAddTask: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if showingAddTask {
                HStack(spacing: 8) {
                    TextField(String(localized: "task.newTaskPlaceholder"), text: $newTaskTitle)
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
                    .disabled(!canAddTask)

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
        guard canAddTask else { return }

        isAddFieldFocused = false
        onAddTask(makeActive)

        DispatchQueue.main.async {
            showingAddTask = false
        }
    }

    private func cancelAdd() {
        isAddFieldFocused = false
        newTaskTitle = ""

        DispatchQueue.main.async {
            showingAddTask = false
        }
    }
}

struct ShortcutReferenceSection: View {
    private let items: [(titleKey: String, shortcut: String)] = [
        ("shortcut.reference.togglePopover", "⌃⌥S"),
        ("shortcut.reference.help", "⌘?"),
        ("shortcut.reference.quit", "⌘Q")
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.titleKey) { item in
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(item.titleKey), tableName: "Localizable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(item.shortcut)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct ShortcutsHelpView: View {
    private var sections: [KeyboardShortcutSection] {
        KeyboardShortcutSection.allCases.filter { !KeyboardShortcutRegistry.shortcuts(in: $0).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("help.title", tableName: "Localizable")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(section.titleKey), tableName: "Localizable")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(KeyboardShortcutRegistry.shortcuts(in: section)) { shortcut in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(shortcut.key)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                    .frame(width: 72, alignment: .leading)

                                Text(LocalizedStringKey(shortcut.descriptionKey), tableName: "Localizable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    if section != sections.last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ContentView(taskManager: TaskManager())
        .frame(width: 320, height: 500)
}
