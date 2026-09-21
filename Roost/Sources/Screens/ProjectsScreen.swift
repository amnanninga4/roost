// Projects page: bigger jobs broken into steps. Hosted by ListsScreen, which owns the NavigationStack and chrome. Each
// project is a card that opens on tap — a progress
// bar, the steps with check-off, and a composer for the next one. Steps can be dragged into a new
// order; the card that runs out of steps gets a DONE chip and can be archived. Swipe a step away with
// five seconds to take it back. Writes go to the store first, then kick a sync.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct ProjectsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<ProjectRecord> { !$0.removed }, sort: \ProjectRecord.createdAt, order: .reverse)
    private var projects: [ProjectRecord]
    @Query(
        filter: #Predicate<SubtaskRecord> { !$0.removed },
        sort: [SortDescriptor(\SubtaskRecord.sortOrder), SortDescriptor(\SubtaskRecord.createdAt)]
    )
    private var subtasks: [SubtaskRecord]
    @Query private var syncStates: [SyncState]

    @State private var title = ""
    @State private var steps = ""
    @FocusState private var titleFocused: Bool
    @State private var open: Set<String> = []
    @State private var editingDue: ProjectRecord?
    @State private var openedFirst = false
    @State private var undo = ListUndo()
    /// Counters the taps bump, so nothing buzzes for a step the other phone ticked.
    @State private var added = 0
    @State private var checkedOff = 0
    @State private var uncheckedOff = 0
    @State private var milestones = 0

    private var person: String? {
        syncStates.first?.person
    }

    private var stepsByProject: [String: [SubtaskRecord]] {
        Dictionary(grouping: subtasks, by: \.projectId)
    }

    var body: some View {
        List {
            Section {
                ListScreenHeader(
                    title: Strings.Tabs.projects,
                    line: Strings.Projects.header(count: projects.count),
                    status: sync.statusLine
                )
                .listHeaderRow()
            }
            Section {
                ListComposer(
                    placeholder: Strings.Projects.add, text: $title, focused: $titleFocused, onSubmit: titleReturn
                ) {
                    if ProjectComposer.showsFirstSteps(title: title, steps: steps) {
                        firstSteps
                    }
                }
            }
            if projects.isEmpty {
                Section {
                    ListEmptyState(
                        symbol: "hammer", line: Strings.Projects.empty, hint: Strings.Projects.emptyHint
                    )
                }
            }
            ForEach(projects) { project in
                card(project)
            }
        }
        .accessibilityIdentifier("projectsList")
        .roostAnimation(.standard, value: open)
        .roostHaptic(.selection, trigger: added)
        .roostHaptic(.checkOff, trigger: checkedOff)
        .roostHaptic(.undo, trigger: uncheckedOff)
        .roostHaptic(.milestone, trigger: milestones)
        .undoBar(undo)
        .sheet(item: $editingDue) { project in
            DueDaySheet(initial: project.dueOn.flatMap { ProjectDates.day(from: $0) } ?? Date()) { picked in
                setDueOn(project, ProjectDates.dayString(picked))
            }
        }
        .onChange(of: projects.map(\.id), initial: true) { _, ids in
            // The mockup opens the first card; do that once, then leave the choice to the user.
            if !openedFirst, let first = ids.first {
                open.insert(first)
                openedFirst = true
            }
        }
    }

    /// The composer's second field: the steps to start with, one per line, and the button that starts.
    private var firstSteps: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            TextField(Strings.Projects.steps, text: $steps, prompt: Text(Strings.Projects.steps)
                .foregroundStyle(RoostColor.Role.textSecondary.color), axis: .vertical)
                .lineLimit(1 ... 6)
                .roostType(.subheadline)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .accessibilityLabel(Strings.Projects.steps)
            Button(Strings.Projects.start, action: start)
                .roostType(.headline)
                .buttonStyle(.borderedProminent)
                .tint(RoostColor.Role.accent.color)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, RoostSpacing.xl + RoostSpacing.md)
    }

    @ViewBuilder
    private func card(_ project: ProjectRecord) -> some View {
        let projectSteps = stepsByProject[project.id] ?? []
        let progress = ProjectProgress(steps: projectSteps, isDone: \.done)
        let isOpen = open.contains(project.id)
        let now = Date()
        let dueLabel = project.dueOn.flatMap { ProjectDates.label($0, now: now) }
        let pastDue = !progress.isFinished && (project.dueOn.map { ProjectDates.isPast($0, now: now) } ?? false)
        Section {
            ProjectRow(project: project, progress: progress, isOpen: isOpen, dueLabel: dueLabel, pastDue: pastDue) {
                toggleOpen(project)
            }
            .listRowBackground(RoostColor.Role.surface.color)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { remove(project) } label: {
                    Label(archiveLabel(progress), systemImage: progress.isFinished ? "archivebox" : "trash")
                }
                .tint(RoostColor.Role.danger.color)
            }
            .contextMenu {
                Button(project.dueOn == nil ? Strings.Projects.setDueDay : Strings.Projects.changeDueDay,
                       systemImage: "calendar") { editingDue = project }
                if project.dueOn != nil {
                    Button(Strings.Projects.clearDueDay, systemImage: "calendar.badge.minus") { setDueOn(project, nil) }
                }
                Button(role: .destructive) { remove(project) } label: {
                    Label(
                        progress.isFinished ? Strings.Projects.archive : Strings.Projects.deleteProject,
                        systemImage: progress.isFinished ? "archivebox" : "trash"
                    )
                }
            }
            if isOpen {
                ForEach(Array(projectSteps.enumerated()), id: \.element.id) { index, step in
                    SubtaskRow(
                        step: step,
                        // `move(fromOffsets:toOffset:)` counts destinations in the list before the
                        // move, so one place down is index + 2, not index + 1.
                        moveUp: index > 0 ? { reorder(project, move: [index], to: index - 1) } : nil,
                        moveDown: index < projectSteps.count - 1
                            ? { reorder(project, move: [index], to: index + 2) } : nil,
                        onToggle: { toggle(step) },
                        onAssign: { setAssignee(step, $0) }
                    )
                    .listRowBackground(RoostColor.Role.surface.color)
                    .roostTransition(.checkOff)
                    .swipeToDelete(rejected: step.rejected) { remove(step) }
                }
                .onMove { source, destination in
                    reorder(project, move: source, to: destination)
                }
                SubtaskComposer { text, owner in add(text, owner: owner, to: project) }
                    .listRowBackground(RoostColor.Role.surface.color)
                if progress.isFinished {
                    ArchiveRow { remove(project) }
                        .listRowBackground(RoostColor.Role.surface.color)
                }
            }
        }
    }

    private func archiveLabel(_ progress: ProjectProgress) -> String {
        progress.isFinished ? Strings.Projects.archive : Strings.Lists.delete
    }

    // MARK: actions

    /// Return on the title field: never creates, never clears the first-steps text. The Start button
    /// is the only path that starts a project.
    private func titleReturn() {
        let next = ProjectComposer.afterTitleReturn(title: title, steps: steps)
        title = next.title
        steps = next.steps
    }

    private func start() {
        let lines = steps.split(whereSeparator: \.isNewline).map(String.init)
        let project: ProjectRecord
        do {
            guard let started = try ListActions.startProject(title, steps: lines, in: context) else {
                // Blank title: leave the first-steps field alone. Return on the title uses titleReturn.
                return
            }
            project = started
        } catch {
            return // the store refused; the fields keep what was typed
        }
        title = ""
        steps = ""
        titleFocused = false
        added += 1
        open.insert(project.id)
        sync.syncSoon()
    }

    private func toggleOpen(_ project: ProjectRecord) {
        if open.contains(project.id) {
            open.remove(project.id)
        } else {
            open.insert(project.id)
        }
    }

    /// True when the step went into the store; the composer clears itself and keeps the keyboard.
    private func add(_ text: String, owner: String?, to project: ProjectRecord) -> Bool {
        guard (try? ListActions.addSubtask(text, to: project, assignee: owner, in: context)) != nil
        else { return false }
        added += 1
        sync.syncSoon()
        return true
    }

    private func setAssignee(_ step: SubtaskRecord, _ person: String?) {
        try? ListActions.setAssignee(step, person, in: context)
        sync.syncSoon()
    }

    private func toggle(_ step: SubtaskRecord) {
        let done = !step.done
        try? ListActions.setDone(step, done, by: person, in: context)
        if done {
            checkedOff += 1
        } else {
            uncheckedOff += 1
        }
        let siblings = (try? ListActions.liveSubtasks(of: step.projectId, in: context)) ?? []
        if done, ProjectProgress(steps: siblings, isDone: \.done).isFinished {
            milestones += 1 // the last step: the card just became a finished one
        }
        sync.syncSoon()
    }

    private func reorder(_ project: ProjectRecord, move source: IndexSet, to destination: Int) {
        let changed = (try? ListActions.reorderSubtasks(
            of: project, move: source, to: destination, in: context
        )) ?? 0
        guard changed > 0 else { return }
        sync.syncSoon()
    }

    private func setDueOn(_ project: ProjectRecord, _ day: String?) {
        try? ListActions.setDueOn(project, day, in: context)
        sync.syncSoon()
    }

    /// The removal is in the store at once; its sync waits for the undo window (see `ListUndo`).
    private func remove(_ step: SubtaskRecord) {
        let title = step.title
        try? ListActions.removeSubtask(step, in: context)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            _ = try? ListActions.restoreSubtask(step, in: context)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func remove(_ project: ProjectRecord) {
        let title = project.title
        let cascaded = (try? ListActions.removeProject(project, in: context)) ?? []
        open.remove(project.id)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            guard let restored = try? ListActions.restoreProject(project, steps: cascaded, in: context) else { return }
            open.insert(restored.id)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }
}

private struct ProjectRow: View {
    let project: ProjectRecord
    let progress: ProjectProgress
    let isOpen: Bool
    let dueLabel: String?
    let pastDue: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var value: String {
        var parts: [String] = []
        if progress.isFinished {
            parts.append(Strings.Projects.finished)
        }
        parts.append(Strings.Projects.stepsDone(done: progress.done, total: progress.total))
        if pastDue {
            parts.append(Strings.Projects.pastDue)
        }
        if let dueLabel {
            parts.append(dueLabel)
        }
        if project.rejected {
            parts.append(Strings.Lists.didNotSyncValue)
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }

    @ViewBuilder
    private var badges: some View {
        if project.rejected {
            NotSyncedMarker()
        }
        if progress.isFinished {
            TagBadge(text: Strings.Projects.doneChip, role: .success, symbol: "checkmark")
                .roostTransition(.badge)
        }
    }

    private var hasBadges: Bool {
        project.rejected || progress.isFinished
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                HStack(spacing: RoostSpacing.sm) {
                    Text(project.title)
                        .roostType(.title)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: RoostSpacing.sm)
                    // At an accessibility size the card's title needs the whole width, so the
                    // chips drop to their own line and only the chevron stays beside it.
                    if !typeSize.isAccessibilitySize {
                        badges
                    }
                    Chevron(isOpen: isOpen)
                }
                if typeSize.isAccessibilitySize, hasBadges {
                    HStack(spacing: RoostSpacing.sm) {
                        badges
                    }
                }
                HStack(spacing: RoostSpacing.sm) {
                    ProgressBar(fraction: progress.fraction, isFinished: progress.isFinished)
                    Text(Strings.Projects.progress(done: progress.done, total: progress.total))
                        .roostType(.monoTally)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .contentTransition(.numericText(value: Double(progress.done)))
                    if let dueLabel {
                        Text(dueLabel)
                            .roostType(.caption)
                            .foregroundStyle(pastDue ? RoostColor.Role.danger.color : RoostColor.Role.textSecondary
                                .color)
                            .fixedSize()
                    }
                }
            }
            .padding(.vertical, RoostSpacing.xs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The bar, the digits and the chip are one number changing, so they move on one animation.
        .roostAnimation(.standard, value: progress)
        .accessibilityLabel(project.title)
        .accessibilityValue(value)
        .accessibilityHint(isOpen ? Strings.Projects.hideSteps : Strings.Projects.showSteps)
    }
}

private struct Chevron: View {
    let isOpen: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .roostType(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(RoostColor.Role.textSecondary.color)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .roostAnimation(.quick, value: isOpen)
            .accessibilityHidden(true)
    }
}

/// The mockup's progress bar. The width is the thing, and it moves on the card's one animation, so
/// the bar, the digits, and the chip all arrive together.
private struct ProgressBar: View {
    let fraction: Double
    let isFinished: Bool
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = RoostSpacing.sm

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RoostColor.Role.separator.color)
                Capsule()
                    .fill(isFinished ? RoostColor.Role.success.color : RoostColor.Role.accent.color)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct SubtaskRow: View {
    let step: SubtaskRecord
    /// Nil at the ends of the list. They exist so VoiceOver can do what the drag gesture does.
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let onToggle: () -> Void
    let onAssign: (String?) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var value: String {
        var parts: [String] = [step.done ? Strings.Projects.stepDone : Strings.Projects.stepNotDone]
        if let person = Person(rawValue: step.assignee ?? "") {
            parts.append(Strings.Projects.ownedBy(person.displayName))
        }
        if step.rejected {
            parts.append(Strings.Lists.didNotSyncValue)
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }

    private var title: some View {
        Text(step.title)
            .roostType(.body)
            .foregroundStyle(step.done ? RoostColor.Role.textSecondary.color : RoostColor.Role.textPrimary.color)
            .strikethrough(step.done, color: RoostColor.Role.textSecondary.color)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var ownerAvatar: some View {
        if let owner = Person(rawValue: step.assignee ?? "") {
            RoostAvatar(person: owner.design, label: Strings.Projects.ownedBy(owner.displayName))
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RoostSpacing.md) {
                CheckCircle(isOn: step.done)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                        title
                        if step.rejected {
                            NotSyncedMarker()
                        }
                    }
                    Spacer(minLength: 0)
                    ownerAvatar
                } else {
                    title
                    Spacer(minLength: RoostSpacing.sm)
                    if step.rejected {
                        NotSyncedMarker()
                    }
                    ownerAvatar
                }
            }
            .padding(.vertical, RoostSpacing.xxs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Picker(Strings.Projects.owner, selection: Binding(get: { step.assignee }, set: onAssign)) {
                Text(Strings.Projects.nobody).tag(String?.none)
                ForEach(Person.allCases, id: \.self) { person in
                    Text(person.displayName).tag(Optional(person.rawValue))
                }
            }
        }
        .accessibilityLabel(step.title)
        .accessibilityValue(value)
        .accessibilityHint(step.done ? Strings.Projects.markNotDone : Strings.Projects.markDone)
        .accessibilityActions {
            if let moveUp {
                Button(Strings.Projects.moveUp, action: moveUp)
            }
            if let moveDown {
                Button(Strings.Projects.moveDown, action: moveDown)
            }
            Button(Strings.Projects.nobody) { onAssign(nil) }
            ForEach(Person.allCases, id: \.self) { person in
                Button(person.displayName) { onAssign(person.rawValue) }
            }
        }
    }
}

private struct ArchiveRow: View {
    let onArchive: () -> Void

    var body: some View {
        Button(action: onArchive) {
            HStack(spacing: RoostSpacing.md) {
                Image(systemName: "archivebox")
                    .roostType(.body)
                    .accessibilityHidden(true)
                Text(Strings.Projects.archive)
                    .roostType(.body)
                Spacer(minLength: RoostSpacing.sm)
            }
            .foregroundStyle(RoostColor.Role.accent.color)
            .padding(.vertical, RoostSpacing.xxs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubtaskComposer: View {
    /// Returns whether the step was added.
    let onAdd: (String, String?) -> Bool
    @State private var draft = ""
    @State private var owner: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            PlusBadge(isActive: !draft.isEmpty)
            TextField(Strings.Projects.addStep, text: $draft, prompt: Text(Strings.Projects.addStep)
                .foregroundStyle(RoostColor.Role.textSecondary.color))
                .roostType(.body)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityLabel(Strings.Projects.addStep)
                .accessibilityHint(Strings.Lists.composerHint)
            Menu {
                Picker(Strings.Projects.owner, selection: $owner) {
                    Text(Strings.Projects.nobody).tag(String?.none)
                    ForEach(Person.allCases, id: \.self) { person in
                        Text(person.displayName).tag(Optional(person.rawValue))
                    }
                }
            } label: {
                Group {
                    if let person = Person(rawValue: owner ?? "") {
                        RoostAvatar(person: person.design)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                    }
                }
                .frame(width: RoostSpacing.minTapTarget, height: RoostSpacing.minTapTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.Projects.owner)
            .accessibilityValue(owner.map { Person(rawValue: $0)?.displayName ?? $0 } ?? Strings.Projects.nobody)
        }
        .padding(.vertical, RoostSpacing.xxs)
        .frame(minHeight: RoostSpacing.minTapTarget)
    }

    private func submit() {
        guard ListActions.cleaned(draft) != nil else {
            draft = "" // blank: let Return put the keyboard away, and take the stray spaces with it
            return
        }
        guard onAdd(draft, owner) else { return } // the store refused; the line stays in the field
        draft = ""
        owner = nil
        refocus($focused) // keep the keyboard up: steps come in batches too
    }
}

/// The date picker behind "Set a due day". Graphical, in the household's time zone, so the day picked is
/// the day stored whatever zone the phone is in.
private struct DueDaySheet: View {
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _day = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(Strings.Projects.dueDayPicker, selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, HouseholdCalendar().calendar.timeZone)
                .tint(RoostColor.Role.accent.color)
                .padding(RoostSpacing.lg)
                .navigationTitle(Strings.Projects.dueDayPicker)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.Settings.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.Projects.dueDayDone) {
                            onPick(day)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
