import AVFoundation
import Speech
import SwiftUI

/// The hub: a paper window with the sidebar on the left, a toolbar strip level with the window
/// controls, and the current page on a raised sheet.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light
    @AppStorage("sidebarCollapsed") private var collapsed = false
    /// The page shown before the current one, so a page switch can rise from the side it came from.
    @State private var previousScreen: AppModel.Screen = .dictation
    @State private var showsShortcuts = false
    @Namespace private var selectionSpace

    static let labScreens: [AppModel.Screen] = [.setup, .train, .evaluate, .use]
    private static let mainScreens: [AppModel.Screen] = [.dictation, .insights, .style, .transforms, .files, .meetings, .personalization]
    private static let navigationOrder: [AppModel.Screen] = mainScreens + labScreens + [.settings]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: collapsed ? Theme.sidebarCollapsedWidth : Theme.sidebarWidth)
                .clipped()
            page
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
                .shadow(color: .black.opacity(0.04), radius: Theme.s2, y: Theme.s0)
                .padding([.trailing, .bottom], Theme.s2)
        }
        .padding(.top, Theme.toolbarHeight)
        .overlay(alignment: .top) {
            HubToolbar(collapsed: $collapsed, showsShortcuts: $showsShortcuts)
                .frame(height: Theme.titlebarHeight)
        }
        .background(Theme.paper)
        .background(TrafficLightInset(height: Theme.titlebarHeight))
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .font(.hkBody)
        .groupBoxStyle(CardGroupBoxStyle())
        .tint(Theme.ink)
        .preferredColorScheme(appearance.colorScheme)
        .animation(reduceMotion ? nil : Theme.glide, value: collapsed)
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
        .onChange(of: model.screen) { old, new in
            previousScreen = old
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: new.rawValue, .priority: NSNumber(value: 50)])
        }
        .sheet(isPresented: $showsShortcuts) {
            KeyboardShortcutsSheet()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
        }
        .sheet(isPresented: Binding(get: { model.showsOnboarding }, set: { model.showsOnboarding = $0 })) {
            OnboardingView()
                .environment(model)
                .preferredColorScheme(appearance.colorScheme)
        }
        .task {
            // The first run shows once, the first time the window opens.
            if !AppDataDirectory.isRunningTests, OnboardingRecord().showsOnLaunch { model.showsOnboarding = true }
        }
    }

    // MARK: Sidebar

    /// The lab is research tooling, so it stays folded away unless opened or in use.
    @AppStorage("showsSilentLab") private var showsLab = false
    private var labIsOpen: Bool { showsLab || Self.labScreens.contains(model.screen) }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLockup(collapsed: collapsed, live: model.audio.isRunning)
                .padding(.top, Theme.s2)
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s4)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    ForEach(Self.mainScreens) { row($0) }
                    labHeader
                    if labIsOpen {
                        ForEach(Self.labScreens) { row($0) }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: Theme.s1) {
                if !collapsed {
                    SetupChecklist()
                        .padding(.bottom, Theme.s2)
                        .transition(.opacity)
                }
                SidebarItem(title: "Shortcuts", icon: .keyboard, collapsed: collapsed) { showsShortcuts = true }
                row(.settings)
            }
            .padding([.horizontal, .bottom], Theme.s3)
        }
    }

    private func row(_ screen: AppModel.Screen) -> some View {
        SidebarRow(screen: screen, collapsed: collapsed, selection: selectionSpace)
    }

    @ViewBuilder
    private var labHeader: some View {
        if collapsed {
            // Icons only: a short hairline stands in for the section title.
            Button {
                withAnimation(Theme.snappy) { showsLab.toggle() }
            } label: {
                Rectangle().fill(Theme.hairline)
                    .frame(width: Theme.iconColumn, height: Theme.hairlineWidth)
                    .frame(maxWidth: .infinity, minHeight: Theme.chipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, Theme.s1)
            .help(labIsOpen ? "Hide the Silent Lab" : "Show the Silent Lab")
        } else {
            Button {
                withAnimation(Theme.snappy) { showsLab.toggle() }
            } label: {
                HStack(spacing: Theme.s1) {
                    SectionLabel(title: "Silent Lab")
                    Glyph(.chevronRight, size: Theme.iconXS)
                        .foregroundStyle(Theme.ink3)
                        .rotationEffect(.degrees(labIsOpen ? 90 : 0))
                    Spacer()
                    if model.motion.isConnected {
                        Circle().fill(Theme.success).frame(width: Theme.dot, height: Theme.dot)
                            .help(model.motion.status.label)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s5)
            .padding(.bottom, Theme.s0)
            .help(labIsOpen ? "Hide the Silent Lab" : "Show the Silent Lab: AirPods gestures and silent words")
            .accessibilityLabel("Silent Lab")
            .accessibilityValue(labIsOpen ? "Expanded" : "Collapsed")
        }
    }

    // MARK: Page

    /// Moving down the sidebar, the next page rises from below; moving up, it settles from above.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let from = Self.navigationOrder.firstIndex(of: previousScreen) ?? 0
        let to = Self.navigationOrder.firstIndex(of: model.screen) ?? 0
        let rise: CGFloat = to >= from ? 14 : -14
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: rise)),
                           removal: .opacity.animation(.easeOut(duration: 0.1)))
    }

    private var page: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch model.screen {
                case .dictation: DictationView()
                case .transforms: TransformView()
                case .files: FileTranscriptionView()
                case .meetings: MeetingNotesView()
                case .setup: SetupView()
                case .train: TrainView()
                case .evaluate: EvaluateView()
                case .use: UseView()
                case .personalization: PersonalizationView()
                case .style: StyleView()
                case .insights: InsightsView()
                case .settings: SettingsView()
                }
            }
            .id(model.screen)
            .transition(pageTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if Self.labScreens.contains(model.screen) {
                MotionStatusBadge(status: model.motion.status, rate: model.motion.sampleRate)
                    .font(.hkCaption)
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.chipHeight)
                    .background(Theme.well, in: Capsule())
                    .padding(Theme.s4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
        .animation(reduceMotion ? nil : Theme.snappy, value: model.screen)
    }
}

extension AppModel.Screen {
    /// The page's glyph in the sidebar and wherever the page is named.
    var icon: HushIcon {
        switch self {
        case .dictation: .dictation
        case .transforms: .transforms
        case .files: .files
        case .meetings: .meetings
        case .setup: .connect
        case .train: .train
        case .evaluate: .evaluate
        case .use: .silent
        case .personalization: .vocabulary
        case .style: .style
        case .insights: .insights
        case .settings: .settings
        }
    }
}

/// Dictator's mark and wordmark, left-aligned on the sidebar icons. The mark is the app icon's
/// sage ribbon and opens into a lens while dictating; collapsed, only the mark stays.
private struct BrandLockup: View {
    var collapsed: Bool
    var live: Bool

    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(live ? "DictatorMenuBarLive" : "DictatorMenuBar")
                .resizable()
                .frame(width: Theme.iconXL, height: Theme.iconXL)
                .foregroundStyle(Theme.signal)
                .contentTransition(.opacity)
                .animation(Theme.gentle, value: live)
            if !collapsed {
                // The wordmark in the app's serif voice, like the page titles.
                Text("Dictator")
                    .font(.hkCardTitle.weight(.medium))
                    .tracking(-0.2)
                    .fixedSize()
                    .transition(.opacity.combined(with: .offset(x: -Theme.figureGap)))
            }
        }
        .padding(.leading, collapsed ? 0 : Theme.s1)
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .frame(height: Theme.fieldHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dictator")
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let storageKey = "appearance"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Sidebar navigation row. The selection fill slides from row to row, the selected glyph fills
/// in sage and makes its gesture once, hovering plays the gesture, and collapsed rows keep only
/// the glyph (with the title as a tooltip).
private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    var screen: AppModel.Screen
    var collapsed: Bool
    var selection: Namespace.ID

    var body: some View {
        SidebarItem(title: screen.sidebarTitle, icon: screen.icon, collapsed: collapsed,
                    isSelected: model.screen == screen, selection: selection) {
            withAnimation(Theme.snappy) { model.screen = screen }
        }
        .accessibilityIdentifier("sidebar.\(screen.id)")
    }
}

/// One sidebar entry: a page, or an action such as Shortcuts.
private struct SidebarItem: View {
    var title: String
    var icon: HushIcon
    var collapsed: Bool
    var isSelected = false
    var selection: Namespace.ID?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s3) {
                Glyph(icon, size: Theme.iconL)
                    .foregroundStyle(isSelected || hovering ? Theme.ink : Theme.ink2)
                    .frame(width: Theme.iconColumn)
                if !collapsed {
                    Text(title)
                        .font(.hkNav.weight(isSelected ? .medium : .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .hushIconHover(hovering)
            .hushIconActive(isSelected)
            .padding(.horizontal, collapsed ? 0 : Theme.s3)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .frame(height: Theme.sidebarRow)
            .background {
                if isSelected, let selection {
                    RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                        .fill(Theme.selection)
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if hovering {
                    RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                        .fill(Theme.hover)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(collapsed ? title : "")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// First-run steps for voice dictation. Hides itself once every step is done.
private struct SetupChecklist: View {
    @Environment(AppModel.self) private var model
    @State private var microphoneGranted = false
    @State private var speechGranted = false

    private struct Step: Identifiable {
        var id: String { title }
        var title: String
        var isDone: Bool
        var opens: AppModel.Screen
        var settingsSection: SettingsView.Section?
        /// The macOS permission this step asks for, instead of just opening a page.
        var permission: DictationNotice.Privacy?
    }

    private var steps: [Step] {
        var steps = [
            Step(title: "Allow microphone", isDone: microphoneGranted, opens: .dictation, permission: .microphone),
        ]
        if !usesDownloadedParakeet {
            steps.append(Step(title: "Allow speech recognition", isDone: speechGranted,
                              opens: .dictation, permission: .speechRecognition))
        }
        steps.append(Step(title: "Turn on typing", isDone: model.insertion.isEnabled,
                          opens: .settings, settingsSection: .insertion))
        steps.append(Step(title: "Finish a first dictation", isDone: model.didCompleteFirstDictation,
                          opens: .dictation))
        return steps
    }

    private var usesDownloadedParakeet: Bool {
        model.dictationEngine == .parakeet
            && model.parakeet.isDownloaded
            && model.parakeet.model.supports(localeIdentifier: model.dictationLanguage)
    }

    var body: some View {
        let completed = steps.filter(\.isDone).count
        Group {
            if completed < steps.count {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    HStack {
                        Text("Get set up").font(.hkCaption.weight(.semibold))
                        Spacer()
                        Text("\(completed) of \(steps.count)")
                            .font(.hkMeta.weight(.medium).monospacedDigit())
                            .foregroundStyle(Theme.ink3)
                            .contentTransition(.numericText(value: Double(completed)))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.hairline)
                            Capsule().fill(Theme.signal)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(steps.count))
                        }
                    }
                    .frame(height: Theme.progressHeight)
                    ForEach(steps) { step in
                        ChecklistStep(title: step.title, isDone: step.isDone) {
                            if let permission = step.permission {
                                request(permission)
                                return
                            }
                            if let section = step.settingsSection {
                                UserDefaults.standard.set(section.rawValue, forKey: "settingsSection")
                            }
                            withAnimation(Theme.snappy) { model.screen = step.opens }
                        }
                    }
                    Button {
                        model.openOnboarding()
                    } label: {
                        HStack(spacing: Theme.s1) {
                            Glyph(.play, size: Theme.iconXS)
                            Text("Take the 60-second tour")
                        }
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(Theme.ink2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.s0)
                }
                .padding(Theme.s3)
                .surface(.outlined)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Theme.gentle, value: completed)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: model.audio.isRunning) { _, _ in refresh() }
        .onChange(of: model.dictationEngine) { _, _ in refresh() }
        .onChange(of: model.dictationLanguage) { _, _ in refresh() }
        .onChange(of: model.parakeet.isDownloaded) { _, _ in refresh() }
    }

    /// Shows the macOS prompt the first time; once it has been answered "Don't Allow", only
    /// System Settings can change it, so open that pane instead.
    private func request(_ permission: DictationNotice.Privacy) {
        Task { @MainActor in
            let outcome: LocalPermissionOutcome = switch permission {
            case .microphone: await LocalPermissionAccess.microphone()
            case .speechRecognition: await LocalPermissionAccess.speechRecognition()
            }
            refresh()
            if outcome == .denied || outcome == .restricted {
                model.openPrivacySettings(permission)
            }
        }
    }

    private func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}

/// One checklist step: an open ring that fills with a drawn check when done.
private struct ChecklistStep: View {
    var title: String
    var isDone: Bool
    var perform: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: Theme.s2) {
                ZStack {
                    Circle()
                        .strokeBorder(isDone ? Theme.signal : hovering ? Theme.ink2 : Theme.ink3, lineWidth: Theme.selectedStroke)
                    Circle().fill(Theme.signal).scaleEffect(isDone ? 1 : 0.2).opacity(isDone ? 1 : 0)
                    CheckStroke()
                        .trim(from: 0, to: isDone ? 1 : 0)
                        .stroke(Theme.inverseInk, style: StrokeStyle(lineWidth: Theme.selectedStroke, lineCap: .round, lineJoin: .round))
                        .padding(Theme.s1)
                }
                .frame(width: Theme.iconM, height: Theme.iconM)
                Text(title)
                    .font(.hkCaption)
                    .foregroundStyle(isDone ? Theme.ink3 : Theme.ink)
                    .strikethrough(isDone, color: Theme.ink3)
                Spacer(minLength: 0)
                if !isDone {
                    Glyph(.chevronRight, size: Theme.iconXS)
                        .foregroundStyle(Theme.ink3)
                        .opacity(hovering ? 1 : 0)
                        .offset(x: hovering ? 0 : -Theme.s1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .animation(Theme.gentle, value: isDone)
    }
}

/// The check inside a done checklist ring, drawn on with `trim`.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}
