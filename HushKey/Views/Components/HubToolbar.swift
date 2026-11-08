import AppKit
import AVFoundation
import Speech
import SwiftUI

/// The strip above the sheet, level with the window controls: the sidebar toggle on the left;
/// appearance, notices and the local profile on the right.
struct HubToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light
    @Binding var collapsed: Bool
    @Binding var showsShortcuts: Bool
    @State private var showsNotices = false
    @State private var showsProfile = false
    @State private var themeTurns = 0.0

    var body: some View {
        // Measured against Wispr Flow: the sidebar toggle sits 99 pt in, level with the traffic
        // lights; theme, bell and profile are 36 pt apart, the last 22 pt from the edge.
        HStack(spacing: Theme.s2) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.glide) { collapsed.toggle() }
            } label: {
                Glyph(.sidebar, active: collapsed)
            }
            .buttonStyle(ToolbarButtonStyle())
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help(collapsed ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)")
            .accessibilityLabel(collapsed ? "Show sidebar" : "Hide sidebar")
            .padding(.leading, Theme.trafficLightClearance) // clears the window controls; centred 99 pt in

            LiveActivityChip()

            Spacer()

            Button {
                withAnimation(Theme.gentle) {
                    themeTurns += 1
                    appearance = isDark ? .light : .dark
                }
            } label: {
                ZStack {
                    Glyph(.sun).opacity(isDark ? 1 : 0).scaleEffect(isDark ? 1 : 0.5)
                    Glyph(.moon).opacity(isDark ? 0 : 1).scaleEffect(isDark ? 0.5 : 1)
                }
                .rotationEffect(.degrees(themeTurns * 180))
            }
            .buttonStyle(ToolbarButtonStyle())
            .contextMenu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help(isDark ? "Switch to light. Right-click to follow the system." : "Switch to dark. Right-click to follow the system.")
            .accessibilityLabel(isDark ? "Light appearance" : "Dark appearance")

            Button { showsNotices.toggle() } label: {
                Glyph(.bell, active: notices.attentionCount > 0)
            }
            .buttonStyle(ToolbarButtonStyle(active: showsNotices))
            .overlay(alignment: .topTrailing) { badge }
            .animation(Theme.snappy, value: notices.attentionCount)
            .popover(isPresented: $showsNotices, arrowEdge: .bottom) {
                NoticesPopover(notices: notices) { showsNotices = false }
                    .environment(model)
                    .preferredColorScheme(appearance.colorScheme)
            }
            .help("Notices")
            .accessibilityLabel("Notices, \(notices.attentionCount) to look at")

            Button { showsProfile.toggle() } label: {
                ProfileAvatar(size: 24)
            }
            .buttonStyle(ToolbarButtonStyle(active: showsProfile))
            .popover(isPresented: $showsProfile, arrowEdge: .bottom) {
                ProfilePopover(showShortcuts: { showsShortcuts = true }) { showsProfile = false }
                    .environment(model)
                    .preferredColorScheme(appearance.colorScheme)
            }
            .help("Your profile")
            .accessibilityLabel("Profile")
        }
        .padding(.trailing, Theme.s2)
    }

    private var isDark: Bool {
        switch appearance {
        case .dark: true
        case .light: false
        case .system: colorScheme == .dark
        }
    }

    private var notices: [Notice] { Notice.current(for: model) }

    @ViewBuilder
    private var badge: some View {
        let count = notices.attentionCount
        if count > 0 {
            Text("\(count)")
                // Badge geometry is the dot's own: it sits on the toolbar glyph's corner.
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.inverseInk)
                .frame(minWidth: Theme.iconS, minHeight: Theme.iconS)
                .background(notices.hasError ? Theme.danger : Theme.signal, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.paper, lineWidth: Theme.selectedStroke))
                .offset(x: 3, y: -1)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

/// What's running right now, beside the sidebar toggle: a dictation or a meeting recording,
/// with the live voice ribbon. Click to go to it.
private struct LiveActivityChip: View {
    @Environment(AppModel.self) private var model

    private enum Activity: Equatable { case dictating, finishing, meeting }

    private var activity: Activity? {
        if model.meetingNotes.isCapturing { return .meeting }
        if model.audio.isRunning { return .dictating }
        if model.isFinalizingDictation || model.transcriber.isFinalizing { return .finishing }
        return nil
    }

    var body: some View {
        ZStack {
            if let activity {
                Button {
                    withAnimation(Theme.snappy) { model.screen = activity == .meeting ? .meetings : .dictation }
                } label: {
                    HStack(spacing: Theme.s2) {
                        LiveLevel(model.audio) { level in
                            BreathRibbon(level: level, mode: activity == .finishing ? .working : .live, tint: Theme.signal)
                        }
                        .frame(width: Theme.s6, height: Theme.iconXS)
                        Text(activity == .meeting ? "Recording meeting"
                             : activity == .finishing ? "Transcribing" : "Listening")
                            .font(.hkMeta.weight(.medium))
                            .contentTransition(.interpolate)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.chipHeight)
                    .background(Theme.signalSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.signalEdge, lineWidth: Theme.hairlineWidth))
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .help(activity == .meeting ? "Open Meeting notes" : "Open Home")
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
        .animation(Theme.snappy, value: activity)
    }
}

/// 28 pt toolbar control (Wispr's size), soft fill on hover and while its popover is open.
struct ToolbarButtonStyle: ButtonStyle {
    var active = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.hkNav)
            .foregroundStyle(hovering || active ? Theme.ink : Theme.ink2)
            .hushIconSize(Theme.iconL)
            .hushIconHover(hovering)
            .frame(width: Theme.toolbarButton, height: Theme.toolbarButton)
            .background(hovering || active ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// Initials on a sage tint: HushKey has no account, so the profile is this Mac's user.
struct ProfileAvatar: View {
    var size: CGFloat

    static var fullName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? NSUserName() : full
    }

    private var initials: String {
        let parts = Self.fullName.split(separator: " ").prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Text(initials)
            // Initials in the serif voice on a quiet well, like a monogram; sage stays for state.
            .font(.display(size * 0.44, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.well, in: Circle())
            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
    }
}

// MARK: - Notices

/// Something worth telling the person: a problem to fix, something to recover, or a milestone.
/// Built from the model's live state, so a notice disappears the moment it no longer applies.
struct Notice: Identifiable {
    enum Kind { case error, attention, milestone }

    var id: String
    var kind: Kind
    var icon: HushIcon
    var title: String
    var detail: String
    var action: String?
    var perform: ((AppModel) -> Void)?

    @MainActor
    static func current(for model: AppModel) -> [Notice] {
        var notices: [Notice] = []
        if let error = model.audio.error ?? model.transcriber.error {
            notices.append(Notice(id: "error", kind: .error, icon: .warning,
                                  title: "Dictation hit a problem", detail: error,
                                  action: "Open Settings") { model in
                UserDefaults.standard.set(SettingsView.Section.dictation.rawValue, forKey: "settingsSection")
                model.screen = .settings
            })
        }
        if model.dictationShortcutNeedsAttention {
            notices.append(Notice(id: "shortcut", kind: .attention, icon: .keyboard,
                                  title: "The dictation key isn’t working", detail: model.dictationShortcutStatus,
                                  action: "Fix…") { model in
                UserDefaults.standard.set(SettingsView.Section.shortcuts.rawValue, forKey: "settingsSection")
                model.screen = .settings
            })
        }
        if !model.insertion.isEnabled {
            notices.append(Notice(id: "insertion", kind: .attention, icon: .cursor,
                                  title: "Typing into apps is off",
                                  detail: "Turn it on so your words appear at the cursor.",
                                  action: "Turn on") { model in
                UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                model.screen = .settings
            })
        }
        let parakeetReady = model.dictationEngine == .parakeet
            && model.parakeet.isDownloaded
            && model.parakeet.model.supports(localeIdentifier: model.dictationLanguage)
        if !parakeetReady && SFSpeechRecognizer.authorizationStatus() != .authorized {
            notices.append(Notice(id: "speech-permission", kind: .attention, icon: .mic,
                                  title: "Speech recognition is off",
                                  detail: "Allow HushKey in Privacy & Security to dictate with Apple Speech.",
                                  action: "Open Settings") { model in
                UserDefaults.standard.set(SettingsView.Section.dictation.rawValue, forKey: "settingsSection")
                model.screen = .settings
            })
        }
        if model.dictationHistoryArchiveUnreadable {
            notices.append(Notice(id: "archive", kind: .attention, icon: .folder,
                                  title: "Saved history couldn't be read",
                                  detail: "New dictations still work. Review the archive on Home.",
                                  action: "Show me") { $0.screen = .dictation })
        }
        if let cancelled = model.cancelledDictation {
            notices.append(Notice(id: "cancelled", kind: .attention, icon: .undo,
                                  title: "A cancelled dictation can come back",
                                  detail: "\(cancelled.durationLabel) kept in memory until you quit. Restore to HushKey; it will not type into another app.",
                                  action: "Recover") { model in
                Task { await model.recoverCancelledDictation() }
            })
        }
        let ledger = model.usageLedger
        let streak = ledger.currentStreak()
        if streak >= 2 {
            notices.append(Notice(id: "streak", kind: .milestone, icon: .flame,
                                  title: "\(streak)-day streak",
                                  detail: "You've dictated every day since \(Calendar.current.date(byAdding: .day, value: 1 - streak, to: Date())?.formatted(.dateTime.weekday(.wide)) ?? "then")."))
        }
        if let milestone = [100_000, 50_000, 25_000, 10_000, 5_000, 1_000].first(where: { ledger.totalWords >= $0 }) {
            notices.append(Notice(id: "words", kind: .milestone, icon: .sparkle,
                                  title: "Past \(milestone.formatted()) words",
                                  detail: "About \(milestone / 40) minutes of typing at 40 words a minute."))
        }
        return notices
    }
}

extension Array where Element == Notice {
    var attentionCount: Int { filter { $0.kind != .milestone }.count }
    var hasError: Bool { contains { $0.kind == .error } }
}

private struct NoticesPopover: View {
    @Environment(AppModel.self) private var model
    var notices: [Notice]
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notices").font(.hkHeadline)
                Spacer()
                if notices.attentionCount > 0 {
                    Text("\(notices.attentionCount) to look at")
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(Theme.s4)

            RowDivider()

            if notices.isEmpty {
                VStack(spacing: Theme.s2) {
                    Glyph(.check, size: Theme.iconL)
                        .foregroundStyle(Theme.signal)
                    Text("All quiet").font(.hkCardTitle)
                    Text("Nothing needs you right now.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.s6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                        if index > 0 { RowDivider().padding(.leading, Theme.s4 + Theme.iconTile + Theme.s3) }
                        row(notice).reveal(index, distance: Theme.figureGap)
                    }
                }
                .padding(.vertical, Theme.s1)
            }
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.sheet)
    }

    private func row(_ notice: Notice) -> some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            Glyph(notice.icon, size: Theme.iconM, active: notice.kind == .milestone)
                .foregroundStyle(tint(notice.kind))
                .frame(width: Theme.iconTile, height: Theme.iconTile)
                .background(tint(notice.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.s0) {
                Text(notice.title).font(.hkSubhead.weight(.semibold))
                Text(notice.detail)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = notice.action, let perform = notice.perform {
                    Button(action) {
                        perform(model)
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.hkCaption.weight(.semibold))
                    .foregroundStyle(Theme.signal)
                    .padding(.top, Theme.s0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s3)
    }

    private func tint(_ kind: Notice.Kind) -> Color {
        switch kind {
        case .error: Theme.danger
        case .attention: Theme.ink
        case .milestone: Theme.signal
        }
    }
}

// MARK: - Profile

private struct ProfilePopover: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light
    var showShortcuts: () -> Void
    var dismiss: () -> Void

    var body: some View {
        let ledger = model.usageLedger
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.s3) {
                ProfileAvatar(size: 44)
                VStack(alignment: .leading, spacing: Theme.s0) {
                    Text(ProfileAvatar.fullName).font(.hkHeadline)
                    Label("Local profile, kept on this Mac", icon: .lock)
                        .hushIconSize(Theme.iconXS)
                        .font(.hkMeta)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(Theme.s4)

            HStack(spacing: 0) {
                stat(ledger.totalWords.formatted(), "words")
                stat(ledger.wordsPerMinute.map { "\($0)" } ?? "–", "wpm")
                stat("\(ledger.currentStreak())", "day streak")
            }
            .padding(.vertical, Theme.s3)
            .background(Theme.well)

            VStack(alignment: .leading, spacing: Theme.s2) {
                SectionLabel(title: "Appearance")
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(Theme.s4)

            RowDivider()

            VStack(spacing: Theme.s0) {
                link("Vocabulary", .vocabulary) { $0.screen = .personalization }
                link("Insights", .insights) { $0.screen = .insights }
                link("Keyboard shortcuts", .keyboard) { _ in showShortcuts() }
                link("Data & privacy", .shield) { model in
                    UserDefaults.standard.set(SettingsView.Section.data.rawValue, forKey: "settingsSection")
                    model.screen = .settings
                }
                link("Settings", .settings) { $0.screen = .settings }
                RowDivider().padding(.vertical, Theme.s1)
                link("Quit HushKey", .power) { _ in NSApp.terminate(nil) }
            }
            .padding(Theme.s2)
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.sheet)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: Theme.s0) {
            Text(value).font(.hkDisplayS).monospacedDigit()
            Text(label).font(.hkMeta).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    private func link(_ title: String, _ icon: HushIcon, perform: @escaping (AppModel) -> Void) -> some View {
        Button {
            dismiss()
            withAnimation(Theme.snappy) { perform(model) }
        } label: {
            Label(title, icon: icon)
                .font(.hkSubhead)
                .hushIconSize(Theme.iconM)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PopoverRowStyle())
    }
}

/// Full-width popover menu row with a hover fill.
struct PopoverRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .hushIconHover(hovering)
            .padding(.horizontal, Theme.s3)
            .frame(height: Theme.fieldHeight)
            .background(hovering ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.inner(Theme.r3, padding: Theme.s0), style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

// MARK: - Keyboard shortcuts

/// Every shortcut in one place, with the current keys; Settings changes them.
struct KeyboardShortcutsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private struct Row {
        var icon: HushIcon
        var title: String
        var detail: String
        var keys: [String]
    }

    private var rows: [Row] {
        let fn = model.dictationShortcut.usesFunctionKey
        let holds = fn || model.dictationCaptureBehavior == .hold
        var rows = [Row(icon: .dictation, title: "Dictate",
                        detail: holds ? "Hold, talk, let go" : "Press to start, again to stop",
                        keys: [model.dictationShortcut.label])]
        if fn {
            rows.append(Row(icon: .waveform, title: "Hands-free", detail: "Double-press, then talk as long as you like", keys: ["fn", "fn"]))
        }
        if let pasteLast = model.pasteLastShortcut {
            rows.append(Row(icon: .insert, title: "Paste last dictation", detail: "Pastes what you just dictated anywhere", keys: [pasteLast.label]))
        }
        rows += [
            Row(icon: .close, title: "Cancel", detail: "While dictating; Undo brings it back", keys: ["esc"]),
            Row(icon: .edit, title: "Edit selected text by voice", detail: "Select text, hold, say the change",
                keys: [model.selectedTextEditShortcut.label]),
            Row(icon: .cursor, title: "Paste again", detail: "Types the last output at your cursor",
                keys: [model.insertion.shortcut.label]),
            Row(icon: .undo, title: "Undo insertion", detail: "Replaces the original field contents",
                keys: ["⌥⇧U"]),
            Row(icon: .silent, title: "Silent capture", detail: "Silent Lab: capture one mouthed word",
                keys: [model.captureShortcut.label]),
            Row(icon: .sidebar, title: "Hide or show the sidebar", detail: "In this window", keys: ["⌃⌘S"]),
            Row(icon: .settings, title: "Settings", detail: "Open HushKey's settings", keys: ["⌘,"]),
        ]
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text("Keyboard shortcuts").font(.hkSheetTitle)
                    Text("Change them in Settings → Shortcuts.").font(.hkCaption).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button("Close", icon: .close) { dismiss() }
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: Theme.s3) {
                        Glyph(row.icon, size: Theme.iconL)
                            .foregroundStyle(Theme.ink2)
                            .frame(width: Theme.iconColumn)
                        VStack(alignment: .leading, spacing: Theme.s0) {
                            Text(row.title).font(.hkRowTitle)
                            Text(row.detail).font(.hkCaption).foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                        HStack(spacing: Theme.s1) {
                            ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                                if key == "esc" || key == "fn" { Keycap(glyph: key, size: 12) }
                                else { KeycapShortcut(label: key, size: 12) }
                            }
                        }
                    }
                    .padding(.vertical, Theme.s3)
                    .padding(.horizontal, Theme.rowPaddingH)
                    .overlay(alignment: .top) { if index > 0 { RowDivider() } }
                    .reveal(index, distance: Theme.figureGap)
                }
            }
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            HStack {
                Spacer()
                Button("Open shortcut settings") {
                    UserDefaults.standard.set(SettingsView.Section.shortcuts.rawValue, forKey: "settingsSection")
                    withAnimation(Theme.snappy) { model.screen = .settings }
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.cardPaddingL)
        .frame(width: Theme.sheetWidth)
        .background(Theme.sheet)
    }
}
