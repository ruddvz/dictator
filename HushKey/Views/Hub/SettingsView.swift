import CoreAudio
import AppKit
import SwiftUI

/// Settings, laid out like Wispr Flow's: a section list on the left and grouped rows
/// (label, one-line description, right-aligned control) on the right.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("settingsSection") private var section: Section = .dictation

    /// Short sections, so none scrolls for screens. "General" was split into the first five;
    /// a saved "General" falls back to Dictation.
    enum Section: String, CaseIterable, Identifiable {
        case dictation = "Dictation"
        case shortcuts = "Shortcuts"
        case cleanup = "Cleanup"
        case system = "System"
        case appearance = "Appearance"
        case insertion = "Insertion"
        case data = "Data & privacy"
        case about = "About"
        var id: String { rawValue }

        /// The name shown in the nav. `rawValue` is saved in "settingsSection", so it stays put.
        var title: String { self == .insertion ? "Typing" : rawValue }

        /// Where links to the old General section land.
        static var general: Section { .dictation }

        var icon: HushIcon {
            switch self {
            case .dictation: .mic
            case .shortcuts: .keyboard
            case .cleanup: .sparkle
            case .system: .settings
            case .appearance: .sun
            case .insertion: .cursor
            case .data: .shield
            case .about: .info
            }
        }
    }

    var body: some View {
        // The title and section nav stay put; only the section's content scrolls, so the nav is
        // always in reach.
        PageColumn {
            PageHeader(title: "Settings")

            HStack(alignment: .top, spacing: Theme.s6) {
                SettingsNav(section: $section)
                    .frame(width: Theme.settingsNavWidth)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.s6) {
                        switch section {
                        case .dictation: DictationSettings()
                        case .shortcuts: ShortcutSettings()
                        case .cleanup: CleanupSettings()
                        case .system: SystemSettings()
                        case .appearance: AppearanceSettings()
                        case .insertion: InsertionSettings()
                        case .data: DataSettings()
                        case .about: AboutSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.pageBottom)
                    .id(section)
                    .transition(.opacity.combined(with: .offset(y: Theme.figureGap)))
                }
                .scrollIndicators(.automatic)
            }
            .animation(Theme.snappy, value: section)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsNav: View {
    @Binding var section: SettingsView.Section
    @State private var hovered: SettingsView.Section?
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            ForEach(SettingsView.Section.allCases) { item in
                let selected = item == section
                Button {
                    withAnimation(Theme.snappy) { section = item }
                } label: {
                    HStack(spacing: Theme.s3) {
                        Glyph(item.icon, size: Theme.iconL)
                            .frame(width: Theme.iconColumn)
                            .foregroundStyle(selected || hovered == item ? Theme.ink : Theme.ink2)
                            .hushIconActive(selected)
                            .hushIconHover(hovered == item)
                        Text(item.title)
                            .font(.hkNav.weight(selected ? .medium : .regular))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.sidebarRow)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                                .fill(Theme.selection)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        } else if hovered == item {
                            RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                                .fill(Theme.hover)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Dictation

private struct DictationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var audio = model.audio

        SettingsGroup(title: "Dictation") {
            SettingsRow(title: "Language", detail: "Recognized on this Mac. Nothing is sent online.") {
                LanguageButton(selection: $model.dictationLanguage)
            }
            DictationEngineRows()
            SettingsRow(title: "Microphone", detail: microphoneDetail,
                        detailTint: (audio.error ?? model.transcriber.error) == nil ? Theme.ink2 : Theme.danger) {
                MenuPicker(selection: $audio.selectedDeviceID,
                           options: [(AudioDeviceID?.none, "System default")]
                            + audio.devices.map { (Optional($0.id), $0.name) })
                    .disabled(audio.isRunning || audio.isStarting)
                    .help("Stop recording before changing microphones.")
            }
        }

        SettingsGroup(title: "While you dictate") {
            SettingsRow(title: "Dictation bar", detail: "The small bar at the bottom of your screen.") {
                RowToggle(isOn: $model.showsFloatingPill, label: "Show the dictation bar")
            }
            SettingsRow(title: "Sounds", detail: "A soft cue when the mic opens, when text lands, and when something fails.") {
                RowToggle(isOn: $model.playsDictationSounds, label: "Play dictation sounds")
            }
        }
    }

    private var microphoneDetail: String {
        if let error = model.audio.error ?? model.transcriber.error { return error }
        if let name = model.audio.activeDeviceName { return "Listening with \(name)." }
        return "Used for dictation and meeting notes. Audio is never saved."
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let insertion = model.insertion

        SettingsGroup(title: "Dictation",
                      footer: "Click a shortcut, then press the new keys. fn, a key with ⌘, ⌥ or ⌃, or a side mouse button all work.") {
            SettingsRow(title: "Dictation key",
                        detail: model.dictationShortcutStatus,
                        detailTint: model.dictationShortcutNeedsAttention ? Theme.danger : Theme.ink2) {
                ShortcutRecorder(action: .dictation, combo: model.dictationShortcut.combo,
                                 defaultCombo: DictationShortcut.default.combo, resetLabel: "Reset to fn") {
                    if let combo = $0 { model.dictationShortcut = DictationShortcut(combo) }
                }
            }
            if model.dictationShortcut.usesFunctionKey, model.dictationShortcutNeedsAttention {
                GroupRow {
                    HStack(spacing: Theme.s2) {
                        if AXIsProcessTrusted() {
                            Button("Open Keyboard Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button("Open Accessibility Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        Button("Check again") { model.refreshFunctionKeyStatus() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            if !model.dictationShortcut.usesFunctionKey {
                SettingsRow(title: "Shortcut behavior", detail: "Hold to talk, or press once to start and again to stop.") {
                    MenuPicker(selection: $model.dictationCaptureBehavior,
                               options: DictationCaptureBehavior.allCases.map { ($0, $0.rawValue) })
                }
            }
            SettingsRow(title: "Paste last dictation", detail: model.pasteLastShortcutStatus) {
                ShortcutRecorder(action: .pasteLast, combo: model.pasteLastShortcut?.combo,
                                 defaultCombo: PasteLastShortcut.default.combo, allowsTurningOff: true) {
                    model.pasteLastShortcut = $0.map(PasteLastShortcut.init)
                }
            }
        }

        SettingsGroup(title: "Editing and inserting") {
            SettingsRow(title: "Edit selected text by voice", detail: model.selectedTextEditShortcutStatus) {
                ShortcutRecorder(action: .editSelection, combo: model.selectedTextEditShortcut.combo,
                                 defaultCombo: SelectedTextEditShortcut.default.combo) {
                    if let combo = $0 { model.selectedTextEditShortcut = SelectedTextEditShortcut(combo) }
                }
            }
            SettingsRow(title: "Paste again",
                        detail: insertion.isEnabled ? "Types the last dictation or silent word again, from Home or Silent Use."
                            : "Turn on typing in Settings › Typing to use this.") {
                ShortcutRecorder(action: .insertAgain, combo: insertion.shortcut.combo,
                                 defaultCombo: InsertionShortcut.default.combo) {
                    if let combo = $0 { insertion.shortcut = InsertionShortcut(combo) }
                }
            }
            .disabled(!insertion.isEnabled)
            .opacity(insertion.isEnabled ? 1 : 0.5)
            SettingsRow(title: "Undo the last insertion", detail: "Right after, while the field is unchanged.") {
                KeycapShortcut(label: TextInsertionService.undoShortcut.label, size: 12)
            }
        }

        SettingsGroup(title: "Silent input") {
            SettingsRow(title: "Silent capture", detail: "Hold to capture a word in Train or Silent Use. Holding Control works too.") {
                ShortcutRecorder(action: .silentCapture, combo: model.captureShortcut.combo,
                                 defaultCombo: CaptureShortcut.default.combo) {
                    if let combo = $0 { model.captureShortcut = CaptureShortcut(combo) }
                }
            }
        }
    }
}

// MARK: - Cleanup

private struct CleanupSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        SettingsGroup(title: "Cleanup") {
            SettingsRow(title: "Spoken corrections",
                        detail: "Say “scratch that” or “no, actually” to keep the corrected words: “at four, no, actually five” becomes “at five”.") {
                RowToggle(isOn: $model.appliesSpokenCorrections, label: "Apply spoken corrections")
            }
            SettingsRow(title: "Remove filler words", detail: "Drops um, uh, stutters and “you know”. Your words are never reworded.") {
                RowToggle(isOn: $model.cleansDictationFillers, label: "Remove filler words")
            }
            SettingsRow(title: DictationSmartCleanup.hasAppleIntelligence ? "Polish with Apple Intelligence" : "Polish on this Mac",
                        detail: DictationSmartCleanup.isAvailable
                            ? "Catches the fillers rules miss, like “I was like thinking”, and fixes punctuation. On this Mac; it can only remove fillers."
                            : "Needs Apple Intelligence, or the small cleanup model below.") {
                RowToggle(isOn: $model.polishesWithAppleIntelligence, label: "Polish dictation on this Mac")
                    .disabled(!DictationSmartCleanup.isAvailable || !model.cleansDictationFillers)
            }
            if !DictationSmartCleanup.hasAppleIntelligence {
                SettingsRow(title: "Cleanup model", detail: LocalCleanupModel.shared.statusDescription) {
                    LocalCleanupModelControls(isLocked: model.audio.isRunning || model.isFinalizingDictation)
                }
            }
            SettingsRow(title: "Use nearby text for names",
                        detail: model.usesNearbyTextHints ? model.insertion.contextAccessStatus
                            : "Reads a few words around the cursor, then forgets them.") {
                RowToggle(isOn: $model.usesNearbyTextHints, label: "Use nearby text hints")
            }
            if model.usesNearbyTextHints {
                GroupRow {
                    Button("Check access") { model.requestNearbyTextAccess() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            SettingsRow(title: "Vocabulary", detail: "Names, terms and phrases HushKey should know.") {
                Button("Open") { model.screen = .personalization }
                    .buttonStyle(SecondaryButtonStyle(minWidth: Theme.buttonMinWidth))
            }
        }

        SettingsGroup(title: "App profiles",
                      footer: "Automatic profiles keep each app’s language, vocabulary, snippets, corrections, writing style, and filler cleanup on this Mac.") {
            DictationAppProfilesEditor()
        }
    }
}

// MARK: - System

private struct SystemSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        SettingsGroup(title: "System", footer: model.launchAtLoginMessage) {
            SettingsRow(title: "Launch at login",
                        detail: "HushKey works from the menu bar with its window closed. Starting at login keeps fn ready.") {
                RowToggle(isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchesAtLogin($0) }),
                          label: "Launch HushKey at login")
            }
            SettingsRow(title: "Always show in Dock",
                        detail: "Off keeps HushKey in the menu bar, with a Dock icon only while this window is open.") {
                RowToggle(isOn: $model.showsInDock, label: "Always show HushKey in the Dock")
            }
            SettingsRow(title: "Mute audio while dictating",
                        detail: "Music and videos go quiet while the mic is open, then come back.") {
                RowToggle(isOn: $model.mutesAudioWhileDictating, label: "Mute audio while dictating")
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light

    var body: some View {
        SettingsGroup(title: "Appearance") {
            SettingsRow(title: "Theme", detail: "Fog by day, deep sage at night.") {
                MenuPicker(selection: $appearance,
                           options: AppearancePreference.allCases.map { ($0, $0.rawValue) })
            }
        }
    }
}

// MARK: - Insertion

private struct InsertionSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("settingsSection") private var section: SettingsView.Section = .insertion

    var body: some View {
        @Bindable var model = model
        @Bindable var insertion = model.insertion
        let enabled = Binding(get: { insertion.isEnabled },
                              set: { $0 ? insertion.enable() : insertion.disable() })

        SettingsGroup(title: "Typing into other apps",
                      footer: "Password fields are always skipped. HushKey only types into the field you started in.") {
            SettingsRow(title: "Type where your cursor is", detail: "Dictation goes straight into the text box you’re in.") {
                RowToggle(isOn: enabled, label: "Type into the focused field")
            }
            SettingsRow(title: "Paste when typing is blocked", detail: "Verifies the exact text field; restores the clipboard when safe.") {
                RowToggle(isOn: $insertion.allowsPasteFallback, label: "Paste if typing fails")
            }
            .disabled(!insertion.isEnabled)
            .opacity(insertion.isEnabled ? 1 : 0.5)
            SettingsRow(title: "Type as you speak",
                        detail: "Each phrase goes in once it settles, in fields HushKey can read back, like TextEdit and Notes. Elsewhere, and with Parakeet or Code mode, text arrives at the end. Typed phrases aren’t changed later, so cleanup works phrase by phrase.") {
                RowToggle(isOn: $model.typesWhileSpeaking, label: "Type as you speak")
            }
            .disabled(!insertion.isEnabled)
            .opacity(insertion.isEnabled ? 1 : 0.5)
            SettingsRow(title: "Paste again and undo",
                        detail: "\(insertion.shortcut.label) types the last text again; \(TextInsertionService.undoShortcut.label) undoes it while the field is unchanged.") {
                Button("Shortcuts") { section = .shortcuts }
                    .buttonStyle(SecondaryButtonStyle(minWidth: Theme.buttonMinWidth))
            }
        }
    }
}

// MARK: - Data & privacy

private struct DataSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteTemplates = false
    @State private var confirmDeleteSessions = false
    @State private var confirmPersonalBackupImport = false

    var body: some View {
        @Bindable var model = model

        PrivacyPromise()

        SettingsGroup(title: "History") {
            SettingsRow(title: "Keep recent dictations", detail: "Clear them any time from Home.") {
                RowToggle(isOn: $model.savesDictationHistory, label: "Save recent dictations")
            }
            SettingsRow(title: "Delete transcripts after",
                        detail: model.dictationHistoryRetention == .forever
                            ? "Saved transcripts stay until you delete them."
                            : "Older ones are deleted from this Mac, checked whenever HushKey is open.") {
                MenuPicker(selection: $model.dictationHistoryRetention,
                           options: DictationHistoryRetention.allCases.map { ($0, $0.label) })
            }
            .disabled(!model.savesDictationHistory)
            .opacity(model.savesDictationHistory ? 1 : 0.5)
        }

        SettingsGroup(title: "Your files", footer: model.dataMessage) {
            SettingsRow(title: model.datasetArchiveUnreadable ? "Training dataset needs attention" : "Training dataset",
                        detail: model.datasetArchiveUnreadable
                            ? "The saved file couldn’t be read. Its recovery copy is kept in Application Support."
                            : "Silent Lab templates, saved in Application Support.") {
                HStack(spacing: Theme.s2) {
                    Button("Export…") { model.exportDataset() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.datasetArchiveUnreadable)
                    Button("Delete…") { confirmDeleteTemplates = true }
                        .buttonStyle(DestructiveButtonStyle())
                }
            }
            SettingsRow(title: "Session logs",
                        detail: "Motion logs are in Documents. Enable microphone audio in Silent Lab → Setup.") {
                HStack(spacing: Theme.s2) {
                    Button("Export…") { model.exportSessions() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Delete…") { confirmDeleteSessions = true }
                        .buttonStyle(DestructiveButtonStyle())
                        .disabled(model.recorder.isRecording)
                }
            }
            SettingsRow(title: "Personal data backup",
                        detail: "Dictations, vocabulary, snippets, corrections and writing styles. No audio.") {
                HStack(spacing: Theme.s2) {
                    Button("Export…") { model.exportPersonalDataBackup() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Import…") {
                        confirmPersonalBackupImport = model.selectPersonalDataBackup()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .confirmationDialog(model.datasetArchiveUnreadable
                            ? "Remove the unreadable training dataset from this Mac?"
                            : "Delete all training templates from this Mac?",
                            isPresented: $confirmDeleteTemplates, titleVisibility: .visible) {
            Button(model.datasetArchiveUnreadable ? "Remove unreadable dataset" : "Delete templates", role: .destructive) {
                model.clearTrainingData()
            }
        }
        .confirmationDialog("Delete all session logs and local audio files?", isPresented: $confirmDeleteSessions, titleVisibility: .visible) {
            Button("Delete session logs", role: .destructive) { model.deleteSessionLogs() }
        }
        .confirmationDialog("Import personal HushKey backup?", isPresented: $confirmPersonalBackupImport,
                            titleVisibility: .visible) {
            Button("Merge backup") {
                model.applyPersonalDataBackup(using: .merge)
                confirmPersonalBackupImport = model.pendingPersonalDataBackup != nil
            }
            Button("Replace backed-up data", role: .destructive) {
                model.applyPersonalDataBackup(using: .replace)
                confirmPersonalBackupImport = model.pendingPersonalDataBackup != nil
            }
            Button("Cancel", role: .cancel) { model.cancelPersonalDataImport() }
        } message: {
            if let backup = model.pendingPersonalDataBackup {
                if model.dictationHistoryArchiveUnreadable {
                    backupImportMessage(backup.summary, unreadableHistory: true)
                } else {
                    backupImportMessage(backup.summary, unreadableHistory: false)
                }
            } else {
                Text("The selected backup is no longer available.")
            }
        }

    }

    private func backupImportMessage(_ summary: String, unreadableHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text("Backup: \(summary).")
            Text("Replace overwrites dictations, words, snippets, corrections, writing styles, and app profiles.")
            Text("File transcripts, meeting notes, Silent Lab templates, and session logs stay on this Mac.")
            if unreadableHistory {
                Text("The unreadable dictation archive is replaced. HushKey keeps a recovery copy when possible.")
            }
            Text("Merge keeps local conflicts and adds missing entries. Audio is not included.")
        }
    }
}

/// HushKey's edge over cloud dictation, said once and plainly.
private struct PrivacyPromise: View {
    var body: some View {
        HStack(spacing: Theme.s4) {
            Glyph(.shield)
                .hushIconSize(Theme.iconXL)
                .foregroundStyle(Theme.signal)
                .frame(width: Theme.s7, height: Theme.s7)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("Nothing leaves this Mac")
                    .font(.hkTitle3)
                Text("Speech, motion, transcripts and templates are processed and stored locally. No account, no cloud.")
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: Theme.cardPaddingL, style: .soft)
    }
}

// MARK: - About

private struct AboutSettings: View {
    @State private var status: String?

    private let documents: [(title: String, detail: String, name: String, ext: String)] = [
        ("Licenses and attribution", "Open-source code HushKey adapts.", "NOTICE", "md"),
        ("Argmax MIT license", "On-device speech model runtime.", "ARGMAX-MIT-LICENSE", "txt"),
        ("Third-party notices", "Bundled model notices.", "ARGMAX-NOTICES", "txt"),
        ("Local speech models", "Accuracy and speed on this Mac.", "LOCAL_MODEL_EVALUATION", "md"),
    ]

    var body: some View {
        SettingsGroup(title: "HushKey", footer: status) {
            SettingsRow(title: "Version", detail: "Private, on-device dictation and silent input.") {
                // Same column as the Open buttons below, so the value sits where their labels do.
                Text(version)
                    .font(.hkControl.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                    .frame(minWidth: Theme.buttonMinWidth)
            }
            ForEach(documents, id: \.name) { item in
                SettingsRow(title: item.title, detail: item.detail) {
                    Button("Open") { open(item.name, item.ext) }
                        .buttonStyle(SecondaryButtonStyle(minWidth: Theme.buttonMinWidth))
                }
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    private func open(_ name: String, _ fileExtension: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            status = "This document is missing from the app bundle."
            return
        }
        status = NSWorkspace.shared.open(url) ? nil : "macOS could not open this document."
    }
}

private struct DictationAppProfilesEditor: View {
    private enum CleanupOverride: String, CaseIterable, Identifiable, Hashable {
        case useDefault = "Use default"
        case removeFillers = "Remove fillers"
        case keepFillers = "Keep fillers"

        var id: String { rawValue }
        var value: Bool? {
            switch self {
            case .useDefault: nil
            case .removeFillers: true
            case .keepFillers: false
            }
        }

        init(value: Bool?) {
            switch value {
            case true: self = .removeFillers
            case false: self = .keepFillers
            case nil: self = .useDefault
            }
        }
    }

    private struct CommonApp: Identifiable {
        var name: String
        var bundleIdentifier: String
        var id: String { bundleIdentifier }
    }

    @Environment(AppModel.self) private var model
    @State private var appName = ""
    @State private var bundleIdentifier = ""
    @State private var mode: DictationMode = .natural
    @State private var vocabulary = ""
    @State private var languageIdentifier: String?
    @State private var snippets = ""
    @State private var usesAppSnippets = false
    @State private var correctionRules = ""
    @State private var usesAppCorrections = false
    @State private var cleanupOverride = CleanupOverride.useDefault
    @State private var writingStylePresetID: UUID?
    @State private var editingIdentifier: String?
    @State private var status = ""

    private let commonApps: [CommonApp] = [
        .init(name: "Mail", bundleIdentifier: "com.apple.mail"),
        .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
        .init(name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"),
        .init(name: "Discord", bundleIdentifier: "com.hnc.Discord"),
        .init(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
        .init(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome")
    ]

    var body: some View {
        GroupRow {
            Text("\(model.dictationAppProfiles.count) of \(HushKeyPersonalDataBackup.maximumAppProfiles) profiles, included in personal data backups")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
        }
        ForEach(model.dictationAppProfiles) { profile in
            SettingsRow(title: profile.appName, detail: "\(profile.mode.rawValue), \(profile.bundleIdentifier)") {
                HStack(spacing: Theme.s0) {
                    Button("Edit", icon: .edit) { load(profile) }
                        .buttonStyle(IconButtonStyle())
                        .help("Edit \(profile.appName) profile")
                    Button("Delete", icon: .trash) {
                        model.deleteDictationAppProfile(bundleIdentifier: profile.bundleIdentifier)
                        if editingIdentifier == profile.id { resetForm() }
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Delete \(profile.appName) profile")
                }
            }
        }
        GroupRow {
            HStack(spacing: Theme.s2) {
                field("App name", text: $appName)
                Menu {
                    ForEach(commonApps) { app in
                        Button(app.name) { appName = app.name; bundleIdentifier = app.bundleIdentifier }
                    }
                } label: {
                    Label("Common apps", icon: .grid)
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.button)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            }
            field("Bundle identifier, e.g. com.apple.mail", text: $bundleIdentifier)
            HStack(spacing: Theme.s2) {
                MenuPicker(selection: $mode,
                           options: DictationMode.allCases.filter { $0 != .automatic }.map { ($0, $0.rawValue) },
                           width: Theme.menuWidthCompact)
                field("Extra names or terms, comma separated", text: $vocabulary)
            }
            DisclosureGroup("Optional app-specific overrides") {
                VStack(alignment: .leading, spacing: Theme.stackGap) {
                    HStack(spacing: Theme.controlGap) {
                        Menu {
                            Button("Use default language") { languageIdentifier = nil }
                            ForEach(DictationLanguage.onDevice) { language in
                                Button(language.name) { languageIdentifier = language.identifier }
                            }
                        } label: {
                            Label(languageTitle, icon: .globe)
                        }
                        .menuStyle(.button)
                        .buttonStyle(SecondaryButtonStyle())
                        MenuPicker(selection: $cleanupOverride,
                                   options: CleanupOverride.allCases.map { ($0, $0.rawValue) }, width: Theme.menuWidthCompact)
                    }
                    Menu {
                        Button("Use global transform selection") { writingStylePresetID = nil }
                        ForEach(model.writingStylePresets) { preset in
                            Button(preset.name) { writingStylePresetID = preset.id }
                        }
                    } label: {
                        Label(writingStyleTitle, icon: .style)
                    }
                    .menuStyle(.button)
                    .buttonStyle(SecondaryButtonStyle())

                    Toggle("Use app-specific snippets", isOn: $usesAppSnippets)
                    if usesAppSnippets {
                        TextEditor(text: $snippets)
                            .font(.hkBody.monospaced())
                            .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorShortMax)
                            .editorField()
                        Text("One per line: spoken cue => expanded phrase. An empty list disables global snippets for this app.")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }

                    Toggle("Use app-specific corrections", isOn: $usesAppCorrections)
                    if usesAppCorrections {
                        TextEditor(text: $correctionRules)
                            .font(.hkBody.monospaced())
                            .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorShortMax)
                            .editorField()
                        Text("One per line: recognized phrase => corrected phrase. The global correction switch remains the master control.")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Text("These settings apply only when Dictation mode is Automatic. Default language uses your global choice; default cleanup follows Settings.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.top, Theme.s2)
            }
            .font(.hkCallout)
            .tint(Theme.ink2)
            HStack(spacing: Theme.s2) {
                Button(editingIdentifier == nil ? "Add profile" : "Save profile") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              appName.count > 80 || vocabulary.utf8.count > DictationAppProfile.maximumCustomizationBytes ||
                              (editingIdentifier == nil && model.dictationAppProfiles.count >= HushKeyPersonalDataBackup.maximumAppProfiles) ||
                              !DictationAppProfile.isValidBundleIdentifier(bundleIdentifier))
                if editingIdentifier != nil {
                    Button("Cancel") { resetForm() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if !status.isEmpty {
                    Text(status).font(.hkCaption).foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.hkBody)
            .padding(.horizontal, Theme.s3)
            .frame(height: Theme.controlHeight)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
    }

    private func load(_ profile: DictationAppProfile) {
        appName = profile.appName
        bundleIdentifier = profile.bundleIdentifier
        mode = profile.mode
        vocabulary = profile.vocabulary
        languageIdentifier = profile.languageIdentifier
        snippets = profile.snippets ?? ""
        usesAppSnippets = profile.snippets != nil
        correctionRules = profile.correctionRules ?? ""
        usesAppCorrections = profile.correctionRules != nil
        cleanupOverride = CleanupOverride(value: profile.cleansFillers)
        writingStylePresetID = profile.writingStylePresetID
        editingIdentifier = profile.id
        status = "Editing \(profile.appName)."
    }

    private func save() {
        guard model.saveDictationAppProfile(appName: appName, bundleIdentifier: bundleIdentifier,
                                            mode: mode, vocabulary: vocabulary,
                                            languageIdentifier: languageIdentifier,
                                            snippets: usesAppSnippets ? snippets : nil,
                                            correctionRules: usesAppCorrections ? correctionRules : nil,
                                            cleansFillers: cleanupOverride.value,
                                            writingStylePresetID: writingStylePresetID) else {
            status = "Check the app details, choose an available on-device language, fix invalid rules, and keep no more than 100 profiles."
            return
        }
        if let editingIdentifier,
           DictationAppProfile.normalizedBundleIdentifier(editingIdentifier) !=
            DictationAppProfile.normalizedBundleIdentifier(bundleIdentifier) {
            model.deleteDictationAppProfile(bundleIdentifier: editingIdentifier)
        }
        resetForm(message: "Saved on this Mac.")
    }

    private func resetForm(message: String = "") {
        appName = ""
        bundleIdentifier = ""
        mode = .natural
        vocabulary = ""
        languageIdentifier = nil
        snippets = ""
        usesAppSnippets = false
        correctionRules = ""
        usesAppCorrections = false
        cleanupOverride = .useDefault
        writingStylePresetID = nil
        editingIdentifier = nil
        status = message
    }

    private var languageTitle: String {
        guard let languageIdentifier else { return "Use default language" }
        return DictationLanguage.onDevice.first { $0.identifier == languageIdentifier }?.name ?? languageIdentifier
    }

    private var writingStyleTitle: String {
        guard let writingStylePresetID else { return "Use global transform selection" }
        return model.writingStylePresets.first { $0.id == writingStylePresetID }?.name ?? "Choose a writing style"
    }
}

