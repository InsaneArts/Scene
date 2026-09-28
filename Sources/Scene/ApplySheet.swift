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
        let variant = request?.current ?? model.variant(for: theme)
        VStack(spacing: 0) {
            hero(variant)
            Group {
                switch phase {
                case .planning: ProgressView("Checking your apps…")
                case .ready: planList
                case .applying:
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(model.progress.isEmpty ? "Applying…" : model.progress)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(40)
                case .done: ResultsList(report: model.lastReport)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer(variant)
        }
        .frame(width: 640, height: 720)
        .task(id: mode) { await makePlan() }
    }

    func hero(_ variant: ResolvedVariant) -> some View {
        ZStack(alignment: .bottomLeading) {
            WallpaperView(variant: variant, url: model.wallpaper(for: variant)?.url, pixels: 1280)
            LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase == .done ? "Applied" : "Apply theme").font(.subheadline.weight(.semibold)).opacity(0.8)
                    Text(theme.manifest.name).font(.system(size: 30, weight: .bold))
                    Text(summary).font(.callout).opacity(0.85)
                }
                Spacer(minLength: 16)
                PaletteDots(colors: variant.hues, size: 12)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
            .environment(\.colorScheme, .dark)
            .padding(22)
        }
        .frame(height: 176)
        .clipped()
    }

    var summary: String {
        switch phase {
        case .done:
            let results = model.lastReport?.results ?? []
            return "\(results.filter(\.outcome.isSuccess).count) of \(results.count) apps changed. Each app reports its own result."
        default: return "Scene changes only what is listed here. Undo it at any time."
        }
    }

    var planList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if theme.availableAppearances.count == 2 {
                    CardSection(title: "Appearance") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Appearance", selection: $mode) {
                                Text("Match macOS").tag(AppearanceMode.system)
                                Text("Always Light").tag(AppearanceMode.light)
                                Text("Always Dark").tag(AppearanceMode.dark)
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            Text(mode == .system ? "Apps that support it switch between the light and dark looks with macOS."
                                                 : "Scene sets macOS to \(mode == .light ? "Light" : "Dark").")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(groups, id: \.0) { title, items in
                    CardSection(title: title) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 56) }
                            PlanRow(item: item, isOn: binding(for: item))
                        }
                    }
                }
                let missing = planned.filter { !$0.detection.installed }
                if !missing.isEmpty {
                    Text("Not installed: " + missing.map(\.name).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                }
            }
            .padding(20)
        }
    }

    var groups: [(String, [PlannedIntegration])] {
        let installed = planned.filter { $0.detection.installed }
        return [("Desktop", .system), ("Terminals", .terminal), ("Editors", .editor), ("macOS look · experimental", .experimental)].compactMap { title, kind in
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

    func footer(_ variant: ResolvedVariant) -> some View {
        let accent = CapsuleButtonStyle(fill: variant.interface.accent.color, label: variant.onAccent)
        let plain = CapsuleButtonStyle(fill: .primary.opacity(0.1), label: .primary)
        return HStack(spacing: 10) {
            if phase == .ready, needsAutomation {
                Label("macOS asks once to let Scene control System Events, to switch Light/Dark.", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary)
            } else if phase == .ready {
                Text("\(selected.count) app\(selected.count == 1 ? "" : "s") selected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch phase {
            case .done:
                Button("Undo") { Task { phase = .applying; await model.undo(); dismiss() } }.buttonStyle(plain)
                Button("Done") { dismiss() }.buttonStyle(accent).keyboardShortcut(.defaultAction)
            default:
                Button("Cancel") { dismiss() }.buttonStyle(plain).keyboardShortcut(.cancelAction).disabled(phase == .applying)
                Button("Apply Theme") { Task { await apply() } }
                    .buttonStyle(accent).keyboardShortcut(.defaultAction)
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

    var canApply: Bool { !(item.plan?.operations.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AppIcon(id: item.id, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.body.weight(.medium))
                        if let version = item.detection.version { Text(version).font(.caption).foregroundStyle(.tertiary) }
                        if let (text, color) = status { Pill(text: text, color: color) }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if canApply || !(item.plan?.conflicts.isEmpty ?? true) {
                    Button { withAnimation(.snappy(duration: 0.25)) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                    .help(expanded ? "Hide the changes" : "Show every change")
                }
                Toggle("Change \(item.name)", isOn: $isOn)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!canApply)
            }
            if expanded, let plan = item.plan {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(plan.operations.indices, id: \.self) { i in
                        Label(plan.operations[i].summary, systemImage: "arrow.right")
                    }
                    ForEach(plan.conflicts, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    ForEach(plan.notes, id: \.self) { Label($0, systemImage: "info.circle").foregroundStyle(.secondary) }
                }
                .font(.caption)
                .padding(.leading, 44)
                .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    var subtitle: String {
        if let error = item.error { return error }
        if case .needsOneTimeSetup(let step) = item.detection.setup { return step }
        if let note = item.plan?.notes.first, item.plan?.operations.isEmpty ?? true { return note }
        // Before and after, so "Dark" does not read as the plan.
        if let dark = item.plan?.operations.lazy.compactMap({ if case .setAppearance(let dark) = $0 { dark } else { nil } }).first {
            let now = item.detection.detail ?? "", next = dark ? "Dark" : "Light"
            return now == next ? "Stays \(next)" : "\(now) → \(next)"
        }
        return item.detection.detail ?? ""
    }

    /// Only what needs attention gets a label. Live, the usual case, gets none.
    var status: (String, Color)? {
        if item.error != nil {
            if case .experimental = item.detection.support { return ("Off", .secondary) }
            return ("Blocked", .red)
        }
        guard let plan = item.plan else { return ("Unavailable", .secondary) }
        if plan.operations.isEmpty { return ("No change", .secondary) }
        if plan.requirements.contains(where: { if case .oneTimeSetup = $0 { true } else { false } }) { return ("One-time setup", .orange) }
        if case .experimental = item.detection.support { return ("Experimental", .purple) }
        if !item.detection.liveUpdate { return ("On next launch", .blue) }
        return nil
    }
}

struct ResultsList: View {
    let report: ApplyReport?

    var body: some View {
        ScrollView {
            CardSection {
                ForEach(Array((report?.results ?? []).enumerated()), id: \.element.id) { index, result in
                    if index > 0 { Divider().padding(.leading, 56) }
                    let (symbol, color) = Symbols.outcome(result.outcome)
                    HStack(spacing: 12) {
                        AppIcon(id: result.id, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).font(.body.weight(.medium))
                            Text(Symbols.message(result.outcome)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: symbol).font(.title3).foregroundStyle(color)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .padding(20)
        }
    }
}

enum Symbols {
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
