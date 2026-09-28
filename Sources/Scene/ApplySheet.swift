import SceneEngine
import SceneThemes
import SwiftUI

/// The plan: every app, what Scene will do there, and what it needs. Nothing changes until Apply.
struct ApplySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let theme: Theme

    @State private var mode: AppearanceMode = .system
    @State private var request: ApplyRequest?
    @State private var planned: [PlannedIntegration] = []
    @State private var selected: Set<String> = []
    @State private var phase: Phase = .planning

    enum Phase { case planning, ready, applying, done }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch phase {
            case .planning: ProgressView("Checking your apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready: planList
            case .applying: ProgressView(model.progress.isEmpty ? "Applying…" : model.progress).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done: ResultsList(report: model.lastReport)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 640)
        .task(id: mode) { await makePlan() }
    }

    var header: some View {
        HStack(spacing: 14) {
            if let variant = theme.variants[request?.effectiveAppearance ?? model.appearance(for: theme)] {
                DesktopPreview(variant: variant, wallpaper: model.wallpaper(for: variant)?.url, compact: true).frame(width: 120)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(phase == .done ? "Applied \(theme.manifest.name)" : "Apply \(theme.manifest.name)").font(.title2.weight(.semibold))
                Text(phase == .done ? "Each app reports its own result." : "Scene changes only what is listed here. You can undo it or restore your original setup at any time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    var planList: some View {
        List {
            if theme.availableAppearances.count == 2 {
                Section {
                    Picker("Appearance", selection: $mode) {
                        Text("Match macOS").tag(AppearanceMode.system)
                        Text("Always Light").tag(AppearanceMode.light)
                        Text("Always Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    Text(mode == .system ? "Apps that support it switch between the light and dark variants with macOS." : "Scene sets macOS to \(mode == .light ? "Light" : "Dark").")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(groups, id: \.0) { title, items in
                Section(title) {
                    ForEach(items) { item in PlanRow(item: item, isOn: binding(for: item)) }
                }
            }
            let unavailable = planned.filter { !$0.detection.installed }
            if !unavailable.isEmpty {
                Section("Not installed") {
                    Text(unavailable.map(\.name).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Follows Light/Dark") {
                Text("Slack, Discord, Safari, and Chrome do not let other apps set their colors. They match macOS when their own appearance setting is set to follow the system.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    var groups: [(String, [PlannedIntegration])] {
        let installed = planned.filter { $0.detection.installed }
        return [("Desktop", .system), ("Terminals", .terminal), ("Editors", .editor), ("Experimental: private macOS settings", .experimental)].compactMap { title, kind in
            let items = installed.filter { $0.kind == kind }
            return items.isEmpty ? nil : (title, items)
        }
    }

    func binding(for item: PlannedIntegration) -> Binding<Bool> {
        Binding(get: { selected.contains(item.id) }, set: { on in
            if on { selected.insert(item.id); model.disabledIntegrations.remove(item.id) }
            else { selected.remove(item.id); model.disabledIntegrations.insert(item.id) }
        })
    }

    var needsAutomation: Bool {
        planned.contains { selected.contains($0.id) && ($0.plan?.requirements.contains { if case .automation = $0 { true } else { false } } ?? false) }
    }

    var footer: some View {
        HStack {
            if phase == .ready, needsAutomation {
                Label("macOS will ask once to let Scene control System Events, to switch Light/Dark.", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch phase {
            case .done:
                Button("Undo") { Task { phase = .applying; await model.undo(); dismiss() } }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            default:
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(phase == .applying)
                Button("Apply") { Task { await apply() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(phase != .ready || selected.isEmpty)
            }
        }
        .padding(16)
    }

    func makePlan() async {
        phase = .planning
        let (request, planned) = await model.plan(theme, mode: mode)
        self.request = request
        self.planned = planned
        selected = Set(planned.filter { $0.plan != nil && !($0.plan?.operations.isEmpty ?? true) && !model.disabledIntegrations.contains($0.id) }.map(\.id))
        phase = .ready
    }

    func apply() async {
        guard let request else { return }
        phase = .applying
        await model.apply(request, planned: planned, selected: selected)
        phase = .done
    }
}

struct PlanRow: View {
    let item: PlannedIntegration
    @Binding var isOn: Bool
    @State private var expanded = false

    var canApply: Bool { item.plan != nil && !(item.plan?.operations.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.checkbox).disabled(!canApply)
                Image(systemName: Symbols.integration(item.id)).frame(width: 20).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.body.weight(.medium))
                        if let version = item.detection.version { Text(version).font(.caption).foregroundStyle(.tertiary) }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
                }
                Spacer()
                StatusChip(item: item)
                if canApply || !(item.plan?.conflicts.isEmpty ?? true) {
                    Button { withAnimation { expanded.toggle() } } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.borderless).help("Details")
                }
            }
            if expanded, let plan = item.plan {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.operations.indices, id: \.self) { i in
                        Label(plan.operations[i].summary, systemImage: "arrow.right.circle").font(.caption)
                    }
                    ForEach(plan.conflicts, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    ForEach(plan.notes, id: \.self) { Label($0, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.leading, 58)
            }
        }
        .padding(.vertical, 4)
    }

    var subtitle: String {
        if let error = item.error { return error }
        if case .needsOneTimeSetup(let step) = item.detection.setup { return step }
        if let note = item.plan?.notes.first, item.plan?.operations.isEmpty ?? true { return note }
        return item.detection.detail ?? ""
    }
}

struct StatusChip: View {
    let item: PlannedIntegration

    var body: some View {
        let (text, color) = status
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    var status: (String, Color) {
        if item.error != nil {
            if case .experimental = item.detection.support { return ("Off", .secondary) }
            return ("Blocked", .red)
        }
        guard let plan = item.plan else { return ("Unavailable", .secondary) }
        if plan.operations.isEmpty { return ("No change", .secondary) }
        if plan.requirements.contains(where: { if case .oneTimeSetup = $0 { true } else { false } }) { return ("One-time setup", .orange) }
        if case .experimental = item.detection.support { return ("Experimental", .purple) }
        if !item.detection.liveUpdate { return ("On next launch", .blue) }
        return ("Live", .green)
    }
}

struct ResultsList: View {
    let report: ApplyReport?

    var body: some View {
        List(report?.results ?? []) { result in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Symbols.outcome(result.outcome).0).foregroundStyle(Symbols.outcome(result.outcome).1).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name).font(.body.weight(.medium))
                    Text(Symbols.message(result.outcome)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }
}

enum Symbols {
    static func integration(_ id: String) -> String {
        switch id {
        case "wallpaper": "photo"
        case "appearance": "circle.lefthalf.filled"
        case "accent": "paintbrush.pointed"
        case "iconStyle": "app.badge"
        case "ghostty", "iterm2": "terminal"
        case "neovim": "chevron.left.forwardslash.chevron.right"
        default: "curlybraces.square"
        }
    }

    static func outcome(_ outcome: Outcome) -> (String, Color) {
        switch outcome {
        case .applied: ("checkmark.circle.fill", .green)
        case .appliedRestartNeeded: ("arrow.clockwise.circle.fill", .blue)
        case .appliedPartlyOverridden: ("checkmark.circle.trianglebadge.exclamationmark", .orange)
        case .needsAction: ("hand.point.right.fill", .orange)
        case .skipped: ("minus.circle", .secondary)
        case .failed: ("xmark.octagon.fill", .red)
        }
    }

    static func message(_ outcome: Outcome) -> String {
        switch outcome {
        case .applied: "Done and verified."
        case .appliedRestartNeeded(let why): why
        case .appliedPartlyOverridden(let keys): "Applied. Your own config overrides part of it: " + keys.joined(separator: " ")
        case .needsAction(let what): what
        case .skipped(let why): why
        case .failed(let why): why
        }
    }
}
