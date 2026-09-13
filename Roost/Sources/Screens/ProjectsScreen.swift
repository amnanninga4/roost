// Projects tab: bigger jobs broken into steps. Each project is a card that opens on tap: a progress bar,
// the steps with check-off, and an "Add a step…" row. Start a project with a title and, if you like,
// its first steps one per line. Swipe a project or a step to delete it. Writes go to the store first,
// then kick a sync.
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
    @State private var openedFirst = false

    private var person: String? {
        syncStates.first?.person
    }

    private var stepsByProject: [String: [SubtaskRecord]] {
        Dictionary(grouping: subtasks, by: \.projectId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ListScreenHeader(title: Strings.Tabs.projects, line: Strings.Projects.header(count: projects.count))
                        .listHeaderRow()
                }
                Section {
                    AddRow(placeholder: Strings.Projects.add, text: $title, focused: $titleFocused, onSubmit: start) {
                        if !title.isEmpty {
                            TextField(Strings.Projects.steps, text: $steps, axis: .vertical)
                                .lineLimit(1 ... 6)
                                .font(RoostFont.body(size: RoostFont.Size.caption, weight: .semibold))
                                .foregroundStyle(RoostColor.inkSoft)
                                .padding(.leading, 32)
                            Button(Strings.Projects.start, action: start)
                                .font(RoostFont.body(size: RoostFont.Size.meta, weight: .bold))
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                if projects.isEmpty {
                    Section {
                        EmptyLine(text: Strings.Projects.empty)
                    }
                }
                ForEach(projects) { project in
                    let projectSteps = stepsByProject[project.id] ?? []
                    let isOpen = open.contains(project.id)
                    Section {
                        ProjectRow(
                            project: project,
                            done: projectSteps.filter(\.done).count,
                            total: projectSteps.count,
                            isOpen: isOpen
                        ) {
                            toggleOpen(project)
                        }
                        .listRowBackground(RoostColor.surface)
                        .swipeToDelete { remove(project) }
                        .contextMenu {
                            Button(role: .destructive) { remove(project) } label: {
                                Label(Strings.Projects.deleteProject, systemImage: "trash")
                            }
                        }
                        if isOpen {
                            ForEach(projectSteps) { step in
                                SubtaskRow(step: step) { toggle(step) }
                                    .listRowBackground(RoostColor.surface)
                                    .swipeToDelete { remove(step) }
                            }
                            SubtaskAddRow { text in add(text, to: project) }
                                .listRowBackground(RoostColor.surface)
                        }
                    }
                }
            }
            .listTabChrome()
            .animation(.default, value: open)
            .onChange(of: projects.map(\.id), initial: true) { _, ids in
                // The mockup opens the first card; do that once, then leave the choice to the user.
                if !openedFirst, let first = ids.first {
                    open.insert(first)
                    openedFirst = true
                }
            }
        }
        .tint(RoostColor.accent)
    }

    // MARK: actions

    private func start() {
        let lines = steps.split(whereSeparator: \.isNewline).map(String.init)
        guard let project = try? ListActions.startProject(title, steps: lines, in: context) else { return }
        title = ""
        steps = ""
        titleFocused = false
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

    private func add(_ text: String, to project: ProjectRecord) {
        guard (try? ListActions.addSubtask(text, to: project, in: context)) != nil else { return }
        sync.syncSoon()
    }

    private func toggle(_ step: SubtaskRecord) {
        try? ListActions.setDone(step, !step.done, by: person, in: context)
        sync.syncSoon()
    }

    private func remove(_ step: SubtaskRecord) {
        try? ListActions.removeSubtask(step, in: context)
        sync.syncSoon()
    }

    private func remove(_ project: ProjectRecord) {
        try? ListActions.removeProject(project, in: context)
        open.remove(project.id)
        sync.syncSoon()
    }
}

private struct ProjectRow: View {
    let project: ProjectRecord
    let done: Int
    let total: Int
    let isOpen: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(project.title)
                        .font(RoostFont.display(size: RoostFont.Size.body, weight: .semibold))
                        .foregroundStyle(RoostColor.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoostColor.inkSoft)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                HStack(spacing: 8) {
                    ProgressBar(fraction: total == 0 ? 0 : Double(done) / Double(total))
                    Text(Strings.Projects.progress(done: done, total: total))
                        .font(RoostFont.mono(size: 10.5, weight: .medium))
                        .foregroundStyle(RoostColor.inkSoft)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.title), \(done) of \(total) done")
        .accessibilityHint(isOpen ? "Collapses the steps" : "Shows the steps")
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(RoostColor.line)
                Capsule().fill(RoostColor.accent).frame(width: max(0, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 8)
    }
}

private struct SubtaskRow: View {
    let step: SubtaskRecord
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                CheckCircle(isOn: step.done)
                Text(step.title)
                    .font(RoostFont.body(size: RoostFont.Size.meta, weight: .semibold))
                    .foregroundStyle(step.done ? RoostColor.inkSoft : RoostColor.ink)
                    .strikethrough(step.done, color: RoostColor.inkSoft)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step.done ? "Undo \(step.title)" : "Mark \(step.title) done")
    }
}

private struct SubtaskAddRow: View {
    let onAdd: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlusBadge()
            TextField(Strings.Projects.addStep, text: $draft)
                .font(RoostFont.body(size: RoostFont.Size.meta, weight: .semibold))
                .foregroundStyle(RoostColor.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit {
                    onAdd(draft)
                    draft = ""
                    refocus($focused) // steps come in batches too
                }
        }
        .padding(.vertical, 2)
    }
}
