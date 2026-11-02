import CoreAudio
import AppKit
import SwiftUI

/// Settings, laid out like Wispr Flow's: a section list on the left and grouped rows
/// (label, one-line description, right-aligned control) on the right.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("settingsSection") private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case insertion = "Insertion"
        case data = "Data & privacy"
        case about = "About"
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .insertion: "character.cursor.ibeam"
            case .data: "lock.shield"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Settings", subtitle: "")

                HStack(alignment: .top, spacing: Theme.s6) {
                    SettingsNav(section: $section)
                        .frame(width: 176)
                    VStack(alignment: .leading, spacing: Theme.s6) {
                        switch section {
                        case .general: GeneralSettings()
                        case .insertion: InsertionSettings()
                        case .data: DataSettings()
                        case .about: AboutSettings()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(section)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .animation(Theme.snappy, value: section)
            }
            .pageLayout()
        }
    }
}

private struct SettingsNav: View {
    @Binding var section: SettingsView.Section
    @State private var hovered: SettingsView.Section?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsView.Section.allCases) { item in
                let selected = item == section
                Button {
                    section = item
                } label: {
                    HStack(spacing: Theme.s3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                        Text(item.rawValue)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.s3 - 2)
                    .frame(height: Theme.sidebarRow)
                    .background(selected ? Theme.selection : (hovered == item ? Theme.hover : .clear),
                                in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? item : (hovered == item ? nil : hovered) }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light

    var body: some View {
        @Bindable var model = model
        @Bindable var audio = model.audio

        SettingsGroup(title: "Dictation") {
            SettingsRow(title: "Dictation key",
                        detail: model.dictationShortcutStatus,
                        detailTint: model.dictationShortcutNeedsAttention ? Theme.danger : Theme.ink2) {
                MenuPicker(selection: $model.dictationShortcut,
                           options: DictationShortcut.allCases.map { ($0, $0.menuTitle) })
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
                SettingsRow(title: "Shortcut behaviour", detail: "Hold to talk, or press once to start and again to stop.") {
                    MenuPicker(selection: $model.dictationCaptureBehavior,
                               options: DictationCaptureBehavior.allCases.map { ($0, $0.rawValue) })
                }
            }
            SettingsRow(title: "Language", detail: "Recognised on this Mac. Nothing is sent online.") {
                MenuPicker(selection: $model.dictationLanguage, options: languageOptions)
            }
            SettingsRow(title: "Microphone", detail: microphoneDetail,
                        detailTint: (audio.error ?? model.transcriber.error) == nil ? Theme.ink2 : Theme.danger) {
                MenuPicker(selection: $audio.selectedDeviceID,
                           options: [(AudioDeviceID?.none, "System default")]
                            + audio.devices.map { (Optional($0.id), $0.name) })
            }
            SettingsRow(title: "Dictation bar", detail: "The small bar at the bottom of your screen.") {
                RowToggle(isOn: $model.showsFloatingPill, label: "Show the dictation bar")
            }
        }

        SettingsGroup(title: "Cleanup") {
            SettingsRow(title: "Spoken corrections", detail: "“Scratch that” and “actually” fix what you just said.") {
                RowToggle(isOn: $model.appliesSpokenCorrections, label: "Apply spoken corrections")
            }
            SettingsRow(title: "Remove filler words", detail: "Drops a standalone um, uh or erm. The original is kept.") {
                RowToggle(isOn: $model.cleansDictationFillers, label: "Remove filler words")
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
            SettingsRow(title: "Vocabulary and snippets", detail: "Names, terms and phrases HushKey should know.") {
                Button("Open") { model.screen = .personalization }
                    .buttonStyle(SecondaryButtonStyle(minWidth: 96))
            }
        }

        SettingsGroup(title: "Shortcuts") {
            SettingsRow(title: "Edit selected text by voice", detail: model.selectedTextEditShortcutStatus) {
                MenuPicker(selection: $model.selectedTextEditShortcut,
                           options: SelectedTextEditShortcut.allCases.map { ($0, $0.label) })
            }
            SettingsRow(title: "Silent capture", detail: "Hold to capture a word in Train or Silent Use.") {
                MenuPicker(selection: $model.captureShortcut,
                           options: CaptureShortcut.allCases.map { ($0, $0.label) })
            }
        }

        SettingsGroup(title: "App profiles",
                      footer: "In Automatic mode, HushKey writes in each app’s style. App names stay on this Mac.") {
            DictationAppProfilesEditor()
        }

        SettingsGroup(title: "Appearance") {
            SettingsRow(title: "Theme", detail: "Fog by day, deep sage at night.") {
                MenuPicker(selection: $appearance,
                           options: AppearancePreference.allCases.map { ($0, $0.rawValue) })
            }
        }
    }

    private var languageOptions: [(value: String, title: String)] {
        var options = DictationLanguage.onDevice.map { ($0.identifier, $0.name) }
        if !DictationLanguage.onDevice.contains(where: { $0.identifier == model.dictationLanguage }) {
            options.append((model.dictationLanguage,
                            Locale.current.localizedString(forIdentifier: model.dictationLanguage) ?? model.dictationLanguage))
        }
        return options
    }

    private var microphoneDetail: String {
        if let error = model.audio.error ?? model.transcriber.error { return error }
        if let name = model.audio.activeDeviceName { return "Listening with \(name)." }
        return "Used for dictation and meeting notes. Audio is never saved."
    }
}

// MARK: - Insertion

private struct InsertionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var insertion = model.insertion
        let enabled = Binding(get: { insertion.isEnabled },
                              set: { $0 ? insertion.enable() : insertion.disable() })

        SettingsGroup(title: "Typing into other apps",
                      footer: "Password fields are always skipped. HushKey only types into the field you started in.") {
            SettingsRow(title: "Type where your cursor is", detail: insertion.status) {
                RowToggle(isOn: enabled, label: "Type into the focused field")
            }
            SettingsRow(title: "Insert shortcut", detail: "Types the last transcript or silent word again.") {
                MenuPicker(selection: $insertion.shortcut,
                           options: InsertionShortcut.allCases.map { ($0, $0.label) })
            }
            .disabled(!insertion.isEnabled)
            .opacity(insertion.isEnabled ? 1 : 0.5)
            SettingsRow(title: "Paste when typing is blocked", detail: "Your clipboard is put back afterwards.") {
                RowToggle(isOn: $insertion.allowsPasteFallback, label: "Paste fallback")
            }
            .disabled(!insertion.isEnabled)
            .opacity(insertion.isEnabled ? 1 : 0.5)
            SettingsRow(title: "Undo the last insertion", detail: "Right after, while the field is unchanged.") {
                KeycapShortcut(label: "⌥⇧U", size: 13)
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
            SettingsRow(title: "Keep recent transcripts", detail: "Clear them any time from the Dictation page.") {
                RowToggle(isOn: $model.savesDictationHistory, label: "Save recent transcripts")
            }
        }

        SettingsGroup(title: "Your files", footer: model.dataMessage) {
            SettingsRow(title: "Training dataset", detail: "Silent Lab templates, saved in Application Support.") {
                HStack(spacing: Theme.s2) {
                    Button("Export…") { model.exportDataset() }
                        .buttonStyle(SecondaryButtonStyle())
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
                        detail: "Recent dictations, vocabulary, snippets and corrections. No audio.") {
                HStack(spacing: Theme.s2) {
                    Button("Export…") { model.exportPersonalDataBackup() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Import…") {
                        confirmPersonalBackupImport = model.selectPersonalDataBackup()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .confirmationDialog("Delete all training templates from this Mac?", isPresented: $confirmDeleteTemplates, titleVisibility: .visible) {
            Button("Delete templates", role: .destructive) { model.clearTrainingData() }
        }
        .confirmationDialog("Delete all session logs and local audio files?", isPresented: $confirmDeleteSessions, titleVisibility: .visible) {
            Button("Delete session logs", role: .destructive) { model.deleteSessionLogs() }
        }
        .confirmationDialog("Import personal HushKey backup?", isPresented: $confirmPersonalBackupImport,
                            titleVisibility: .visible) {
            Button("Merge backup") { model.applyPersonalDataBackup(using: .merge) }
            Button("Replace backed-up data", role: .destructive) { model.applyPersonalDataBackup(using: .replace) }
            Button("Cancel", role: .cancel) { model.cancelPersonalDataImport() }
        } message: {
            if let backup = model.pendingPersonalDataBackup {
                if model.dictationHistoryArchiveUnreadable {
                    Text("The backup contains \(backup.summary) Replace affects only dictations, vocabulary, snippets and corrections; file transcripts, meeting notes, Silent Lab templates and session logs stay on this Mac. Your unreadable dictation archive will be replaced, with a recovery copy preserved where possible. Merge keeps local conflicts and adds missing backup entries. Audio is not included.")
                } else {
                    Text("The backup contains \(backup.summary) Replace affects only dictations, vocabulary, snippets and corrections; file transcripts, meeting notes, Silent Lab templates and session logs stay on this Mac. Merge keeps your current entries and adds missing backup entries. Audio is not included.")
                }
            } else {
                Text("The selected backup is no longer available.")
            }
        }

    }
}

/// HushKey's edge over cloud dictation, said once and plainly.
private struct PrivacyPromise: View {
    var body: some View {
        HStack(spacing: Theme.s4) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.signal)
                .frame(width: 48, height: 48)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing leaves this Mac")
                    .font(.hkTitle3)
                Text("Speech, motion, transcripts and templates are processed and stored locally. No account, no cloud.")
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
    }
}

// MARK: - About

private struct AboutSettings: View {
    @State private var status: String?

    private let documents: [(title: String, detail: String, name: String, ext: String)] = [
        ("Licenses and attribution", "Open-source code HushKey adapts.", "NOTICE", "md"),
        ("Argmax MIT license", "On-device speech model runtime.", "ARGMAX-MIT-LICENSE", "txt"),
        ("Third-party notices", "Bundled model notices.", "ARGMAX-NOTICES", "txt"),
    ]
    private let research: [(title: String, detail: String, name: String, ext: String)] = [
        ("Wispr Flow vs TypeWhisper", "The supplied comparison report.", "Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01", "pdf"),
        ("Competitor notes", "What other dictation apps do.", "COMPETITOR_RESEARCH", "md"),
        ("Dictation alternatives", "Follow-up research.", "COMPETITOR_RESEARCH_ADDENDUM_2026-11-01", "md"),
        ("Local speech models", "Accuracy and speed on this Mac.", "LOCAL_MODEL_EVALUATION", "md"),
    ]

    var body: some View {
        SettingsGroup(title: "HushKey") {
            SettingsRow(title: "Version", detail: "Private, on-device dictation and silent input.") {
                Text(version)
                    .font(.hkCallout.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
            }
            ForEach(documents, id: \.name) { item in
                SettingsRow(title: item.title, detail: item.detail) {
                    Button("Open") { open(item.name, item.ext) }
                        .buttonStyle(SecondaryButtonStyle(minWidth: 96))
                }
            }
        }
        SettingsGroup(title: "Research", footer: status) {
            ForEach(research, id: \.name) { item in
                SettingsRow(title: item.title, detail: item.detail) {
                    Button("Open") { open(item.name, item.ext) }
                        .buttonStyle(SecondaryButtonStyle(minWidth: 96))
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
        ForEach(model.dictationAppProfiles) { profile in
            SettingsRow(title: profile.appName, detail: "\(profile.mode.rawValue) · \(profile.bundleIdentifier)") {
                HStack(spacing: 2) {
                    Button("Edit", systemImage: "pencil") { load(profile) }
                        .buttonStyle(IconButtonStyle())
                        .help("Edit \(profile.appName) profile")
                    Button("Delete", systemImage: "trash") {
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
                    Label("Common apps", systemImage: "square.grid.2x2")
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
                           width: 160)
                field("Extra names or terms, comma separated", text: $vocabulary)
            }
            HStack(spacing: Theme.s2) {
                Button(editingIdentifier == nil ? "Add profile" : "Save profile") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              appName.count > 80 || vocabulary.utf8.count > 4_000 ||
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
                .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func load(_ profile: DictationAppProfile) {
        appName = profile.appName
        bundleIdentifier = profile.bundleIdentifier
        mode = profile.mode
        vocabulary = profile.vocabulary
        editingIdentifier = profile.id
        status = "Editing \(profile.appName)."
    }

    private func save() {
        guard model.saveDictationAppProfile(appName: appName, bundleIdentifier: bundleIdentifier,
                                            mode: mode, vocabulary: vocabulary) else {
            status = "Check the app name, bundle identifier, and vocabulary length."
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
        editingIdentifier = nil
        status = message
    }
}

