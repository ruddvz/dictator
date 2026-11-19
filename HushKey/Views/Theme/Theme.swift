import AppKit
import SwiftUI

// MARK: - Tokens

/// HushKey's warm editorial design system. Codes in comments match docs/DESIGN_SYSTEM.md.
enum Theme {
    // MARK: Spacing (S0–S8, a 4-pt grid; S0 is the 2-pt nudge for hairline-thin gaps)
    static let s0: CGFloat = 2
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64

    // MARK: Layout roles (what the spacing steps are for, so every page uses the same ones)
    static let pageGutter: CGFloat = 40      // page column inset from the sheet's sides
    static let pageTop = s7                  // sheet top → page title
    static let pageBottom = s6
    static let headerGap = s6                // page header → first section
    static let sectionGap = s5               // between sections on a page
    static let sectionTitleGap = s3          // section title → its content
    static let titleGap = s2                 // title → subtitle, in page headers and sections
    static let stackGap = s3                 // items inside a card or section
    static let gridGap = s4                  // gutter between cards in a grid, both ways
    static let cardPadding = s4              // inside a card or option card
    static let cardPaddingL = s5             // roomy cards: insights, banners, sheets
    static let rowPaddingV = s4              // settings rows and group rows
    static let rowPaddingH = s4              // list and group rows' side inset
    static let controlGap = s2               // between buttons in a row
    static let iconGap = s2                  // glyph ↔ label
    static let figureGap: CGFloat = 6        // figure ↔ its unit label, title ↔ hero line

    static let leading: CGFloat = 3          // extra line spacing for reading text and transcripts

    // MARK: Radii (R1 sheet, R2 card, R3 inner/row, R4 small, RC control; pills use Capsule)
    static let r1: CGFloat = 16
    static let r2: CGFloat = 12
    static let r3: CGFloat = 8
    static let r4: CGFloat = 4
    static let controlRadius: CGFloat = 10
    /// Concentric corner for something inset `padding` inside a shape of radius `outer`,
    /// never tighter than R4.
    static func inner(_ outer: CGFloat, padding: CGFloat) -> CGFloat { max(r4, outer - padding) }

    // MARK: Strokes
    static let hairlineWidth: CGFloat = 1
    static let selectedStroke: CGFloat = 1.5 // selected cards, focused fields
    static let ruleWidth: CGFloat = 2        // underlines, quote rules, accent bars
    static let dash: [CGFloat] = [6, 4]      // dashed drop zones and "add" tiles

    // MARK: Control heights (H)
    static let controlHeight: CGFloat = 36   // buttons, menus, fields (macOS large)
    static let fieldHeight: CGFloat = 32     // inline search fields, icon buttons
    static let chipHeight: CGFloat = 24      // chips, compact menus
    static let toolbarButton: CGFloat = 28   // toolbar icon controls (Wispr's size)
    static let sidebarRow: CGFloat = 36
    static let listRow: CGFloat = 52         // minimum list row
    static let rowMinHeight: CGFloat = 64    // settings row: label + description + control
    static let optionCardHeight: CGFloat = 136 // selectable option cards (Style, Transforms)
    static let editorShort: CGFloat = 72     // inline editors: minimum heights…
    static let editorMedium: CGFloat = 140
    static let editorTall: CGFloat = 220
    static let editorShortMax: CGFloat = 120 // …and the heights they stop growing at
    static let editorTallMax: CGFloat = 260
    static let textEditorInset: CGFloat = 5  // NSTextView's own line-fragment padding, matched by placeholders
    static let notesMinHeight: CGFloat = 384 // meeting notes list + editor
    static let meterWidth: CGFloat = 120     // inline level meters
    static let valueWidth: CGFloat = 48      // numeric readouts beside sliders and bars
    static let progressHeight: CGFloat = 4   // thin progress tracks
    static let dot: CGFloat = 8              // status dots
    static let toolbarHeight: CGFloat = 46   // window-control strip above the sheet (Flow: sheet ~46 pt down)
    static let titlebarHeight: CGFloat = 42  // traffic lights and toolbar icons centre 21 pt down, as in Flow
    static let trafficLightClearance: CGFloat = 85 // toolbar's first control, clear of the window buttons
    static let listMaxHeight: CGFloat = 320  // scrolling lists inside sheets

    // MARK: Icons (I)
    static let iconXS: CGFloat = 12          // chevrons, tiny checks
    static let iconS: CGFloat = 14           // chips, meta lines
    static let iconM: CGFloat = 16           // buttons, inline
    static let iconL: CGFloat = 18           // sidebar, nav, cards
    static let iconXL: CGFloat = 28          // empty states, feature tiles
    static let iconColumn: CGFloat = 20      // fixed slot so labels beside icons line up
    static let iconTile: CGFloat = 32        // tinted square behind a notice glyph

    // MARK: Widths (W)
    static let pageWidth: CGFloat = 800
    static let homeWidth: CGFloat = 1040     // Wispr's home: 770 column + 24 gap + 248 stats
    static let sideColumn: CGFloat = 280     // side card beside a home-width column
    static let sidebarWidth: CGFloat = 216
    static let sidebarCollapsedWidth: CGFloat = 68
    static let settingsNavWidth: CGFloat = 176
    static let menuWidth: CGFloat = 196
    static let menuWidthCompact: CGFloat = 160 // menus that share a line with a field
    static let buttonMinWidth: CGFloat = 96  // trailing buttons in a settings column
    static let detailWidth: CGFloat = 440    // settings-row label + detail column
    static let readingWidth: CGFloat = 560   // subtitles and paragraphs
    static let noteWidth: CGFloat = 384      // centred empty-state messages
    static let sheetWidth: CGFloat = 520     // modal editor sheets
    static let sheetWidthWide: CGFloat = 620 // grid sheets (languages)
    static let popoverWidth: CGFloat = 320   // toolbar popovers
    static let searchWidth: CGFloat = 180    // inline search field's text
    static let timeColumn: CGFloat = 80      // history rows' time column
    static let onboardingSize = CGSize(width: 640, height: 600)

    // MARK: Opacity
    static let disabledOpacity: Double = 0.4

    // Color: warm paper and ink, each with a dark counterpart
    // Fog & sage: cool fog surfaces, charcoal text, one calm sage signal.
    static let paper = dynamic(light: 0xEEF0EE, dark: 0x121614)       // window + sidebar
    static let sheet = dynamic(light: 0xFAFBFA, dark: 0x1A1F1D)       // raised page
    static let well = dynamic(light: 0xF2F4F2, dark: 0x222826)        // inset card on the sheet
    static let selection = dynamic(light: 0xE0E7E2, dark: 0x26302B)   // selected sidebar row
    static let hover = dynamic(light: 0xE7ECE8, dark: 0x1E2522)
    static let hairline = dynamic(light: 0xDCE1DD, dark: 0x2C3430)
    static let ink = dynamic(light: 0x1E2321, dark: 0xE9EEEB)
    static let ink2 = dynamic(light: 0x626B66, dark: 0x9BA6A0)
    static let ink3 = dynamic(light: 0x737C77, dark: 0x7E8983)  // quieter than ink2, still ≥ 4.5:1
    static let inverseInk = dynamic(light: 0xFAFBFA, dark: 0x121614)
    static let signal = dynamic(light: 0x4A7763, dark: 0x7FB39C)      // the one accent
    static let signalSoft = dynamic(light: 0xE3ECE7, dark: 0x22322B)  // tinted fills behind signal
    static let keycap = dynamic(light: 0xDDE7E1, dark: 0x2A3A33)
    static let keycapEdge = dynamic(light: 0x9DB5A8, dark: 0x4C6A5C)
    static let listening = signal
    static let finishing = dynamic(light: 0x6F8796, dark: 0x9AB2C0)   // slate: working, not alarming
    static let success = dynamic(light: 0x3F7A5C, dark: 0x8CC4A5)
    static let danger = dynamic(light: 0xB5534A, dark: 0xE0877E)

    // Derived surfaces and edges (named so views never mix their own opacities)
    static let rowHover = well.opacity(0.7)            // list row under the pointer
    static let signalWash = signalSoft.opacity(0.5)    // preview and draft cards
    static let signalEdge = signal.opacity(0.5)        // tinted borders and rules
    static let dangerSoft = danger.opacity(0.12)       // destructive hover fill
    static let track = hairline.opacity(0.5)           // bar and meter tracks
    static let fieldEdgeHover = ink3.opacity(0.6)      // menu and field border under the pointer

    // Hero: a deep fog-green panel, the same in both modes, with sage and fog glows drifting in it.
    static let heroBase = dynamic(light: 0x18201C, dark: 0x0E1311)
    static let heroInk = dynamic(light: 0xF1F4F2, dark: 0xE9EEEB)
    static let heroInk2 = dynamic(light: 0xAAB8B0, dark: 0x9BA6A0)
    static let heroGlow = dynamic(light: 0x7FB39C, dark: 0x7FB39C)    // sage, lit for a dark surface
    static let heroMist = dynamic(light: 0x8FA7B4, dark: 0x7F97A4)    // fog, never used as an accent

    // Motion
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Fast out, soft landing, for panels and the sidebar width (Wispr's most used curve).
    static let glide = Animation.timingCurve(0.05, 0.6, 0.4, 0.95, duration: 0.28)
    /// Gap between items that enter one after another (sections, rows, heatmap columns).
    static let stagger: Double = 0.05

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// HushKey's type scale. macOS defaults (13 pt body, 10 pt captions) read small in a
/// full-window app, so every view uses these steps instead of system text styles.
extension Font {
    // Display (New York serif): titles and figures
    static let hkFigureXL = Font.display(36)                            // the one big figure on a card
    static let hkFigureL = Font.display(34)                             // home band headline
    static let hkTitle1 = Font.display(28)                              // page titles
    static let hkFigureM = Font.display(28)                             // stat figures beside a label
    static let hkSheetTitle = Font.display(26)                          // modal sheet titles, hero metrics
    static let hkDisplayBand = Font.display(24)                         // banner titles, inline figures
    static let hkTitle2 = Font.display(22)                              // card titles, large values
    static let hkCardTitle = Font.display(20)                           // option-card and empty-state titles
    static let hkDisplayS = Font.display(18)                            // small serif labels
    static let hkQuote = Font.display(16)                               // quoted samples

    // UI (SF Pro)
    static let hkTitle3 = Font.system(size: 18, weight: .semibold)      // section titles
    static let hkHeadline = Font.system(size: 16, weight: .semibold)    // emphasised row titles
    static let hkRowTitle = Font.system(size: 16, weight: .medium)      // settings and list row labels
    static let hkBody = Font.system(size: 16)                           // reading text, list rows
    static let hkTranscript = Font.system(size: 17)                     // the live transcript
    static let hkCallout = Font.system(size: 15)                        // row descriptions, secondary text
    static let hkControl = Font.system(size: 15, weight: .medium)       // buttons, menus, tabs
    static let hkNav = Font.system(size: 15)                            // sidebar and settings nav rows
    static let hkSubhead = Font.system(size: 14)                        // time column, notice text
    static let hkCaption = Font.system(size: 13)                        // status lines
    static let hkMeta = Font.system(size: 12)                           // timestamps, counts
    static let hkBadge = Font.system(size: 11, weight: .semibold)       // step numbers, tiny badges

    /// HushKey's voice: New York (the system serif) at a regular weight for page titles and
    /// big figures, so headings read as written, not generated. Everything else is SF Pro.
    /// Figures take `.monospacedDigit()` where they compare.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Motion

/// Content that rises 10 pt and fades in when it first appears, `order` steps after the rest.
/// Reduce Motion keeps the fade and drops the rise.
struct Reveal: ViewModifier {
    var order: Int
    var distance: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(Theme.gentle.delay(Double(order) * Theme.stagger)) { shown = true } }
            }
    }
}

extension View {
    func reveal(_ order: Int = 0, distance: CGFloat = 10) -> some View {
        modifier(Reveal(order: order, distance: distance))
    }
}

// MARK: - Surfaces

/// The card surfaces, one recipe each. `surface` draws only the fill and edge, for shapes that
/// lay out their own content; `card` adds the standard padding and full width.
enum SurfaceStyle {
    /// `well` fill, no edge: grouped content on the sheet.
    case well
    /// `sheet` fill with a hairline: lists, editors, outlined cards.
    case outlined
    /// `well` fill with a hairline: insight and stat cards.
    case wellOutlined
    /// `signalSoft` fill with a `signal` edge: the chosen option.
    case selected
    /// Washed `signalSoft` with a soft `signal` edge: previews and drafts.
    case tinted
    /// `signalSoft` fill, no edge: a promise or notice.
    case soft

    var fill: Color {
        switch self {
        case .well, .wellOutlined: Theme.well
        case .outlined: Theme.sheet
        case .selected, .soft: Theme.signalSoft
        case .tinted: Theme.signalWash
        }
    }

    var edge: Color {
        switch self {
        case .well, .soft: .clear
        case .outlined, .wellOutlined: Theme.hairline
        case .selected: Theme.signal
        case .tinted: Theme.signalEdge
        }
    }

    var edgeWidth: CGFloat {
        switch self {
        case .well, .soft: 0
        case .selected: Theme.selectedStroke
        default: Theme.hairlineWidth
        }
    }
}

extension View {
    /// Fill and edge of a card surface at `radius`, without padding.
    func surface(_ style: SurfaceStyle, radius: CGFloat = Theme.r2) -> some View {
        background(style.fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(style.edge, lineWidth: style.edgeWidth))
    }

    /// A full-width card: `cardPadding` inside, `r2` corners.
    func card(padding: CGFloat = Theme.cardPadding, style: SurfaceStyle = .well) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(style)
    }
}

// MARK: - Buttons

/// Sage rounded button for the one main action on a surface (Wispr: 36 pt, radius 10).
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.signal
    var foreground: Color = Theme.inverseInk
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(foreground)
            .hushIconSize(Theme.iconM)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(height: Theme.controlHeight)
            .background(tint.opacity(isEnabled ? (hovering ? 0.88 : 1) : Theme.disabledOpacity),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Neutral filled button for secondary actions, such as a settings row's "Change".
struct SecondaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(Theme.ink.opacity(isEnabled ? 1 : Theme.disabledOpacity))
            .hushIconSize(Theme.iconM)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(minWidth: minWidth)
            .frame(height: Theme.controlHeight)
            // `selection` sits a step above `well` in both modes, and the hairline keeps the edge
            // visible on dark rows, where a fill alone fades into the group.
            .background(hovering && isEnabled ? Theme.hairline : Theme.selection,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Red-text neutral button for destructive actions; the confirmation dialog does the warning.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(Theme.danger.opacity(isEnabled ? 1 : Theme.disabledOpacity))
            .hushIconSize(Theme.iconM)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(height: Theme.controlHeight)
            .background(hovering && isEnabled ? Theme.dangerSoft : Theme.hover,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// Square icon-only control that shows a soft fill on hover.
struct IconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.hkControl)
            .foregroundStyle(hovering ? Theme.ink : Theme.ink2)
            .hushIconSize(Theme.iconM)
            .hushIconHover(hovering)
            .frame(width: Theme.fieldHeight, height: Theme.fieldHeight)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// A row or card that gives a little under the pointer when pressed.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

// MARK: - Keycaps

/// One key, drawn in the sage highlight used wherever HushKey shows a shortcut.
struct Keycap: View {
    var glyph: String
    var size: CGFloat = 13

    var body: some View {
        Text(glyph)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(minWidth: size * 1.85, minHeight: size * 1.85)
            .padding(.horizontal, glyph.count > 1 ? size * 0.46 : 0)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Theme.keycapEdge)
                        .offset(y: size * 0.115)
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Theme.keycap)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .strokeBorder(Theme.keycapEdge, lineWidth: Theme.hairlineWidth))
    }
}

/// Renders a compact shortcut label such as "⌥⇧D" as a row of keycaps.
struct KeycapShortcut: View {
    var label: String
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 0.28) {
            ForEach(Array(Self.keys(in: label).enumerated()), id: \.offset) { _, key in
                Keycap(glyph: key, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(label)")
    }

    /// Splits "⌥⇧D" into one key per modifier glyph plus the key, keeping word keys such as
    /// "fn", "F5", "Space" and "Mouse 4" whole.
    static func keys(in label: String) -> [String] {
        if label.hasPrefix("fn") { return ["fn"] + keys(in: String(label.dropFirst(2))) }
        let modifiers = label.prefix { "⌃⌥⇧⌘".contains($0) }
        let key = label.dropFirst(modifiers.count)
        return modifiers.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }
}

// MARK: - State icon

/// Stable, native state glyphs around HushKey's own ribbon mark. Status changes stay legible
/// without continuously rebuilding a custom path while the UI is scrolling or recording.
struct StateIcon: View {
    enum Phase: Equatable { case idle, listening, working, done }

    var phase: Phase
    var level: Float = 0

    private var normalizedLevel: CGFloat { CGFloat(min(1, max(0, level))) }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Image("HushKeyMenuBar").resizable().scaledToFit()
            case .listening:
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(x: 1, y: 0.82 + normalizedLevel * 0.36)
                    .opacity(0.76 + normalizedLevel * 0.24)
                    .animation(.linear(duration: 0.09), value: normalizedLevel)
            case .working:
                Image(systemName: "hourglass")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

/// Small rounded chip for status and context such as the active writing mode.
struct StatusChip: View {
    var title: String
    var icon: HushIcon
    var tint: Color = Theme.ink2

    var body: some View {
        Label(title, icon: icon)
            .hushIconSize(Theme.iconS)
            .font(.hkCaption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.s3)
            .frame(height: Theme.chipHeight)
            .background(Theme.well, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
    }
}

/// Uppercase section label used above lists and groups.
struct SectionLabel: View {
    var title: String

    var body: some View {
        // Sentence case, untracked, the body face a step smaller (no tracked capitals).
        Text(title)
            .font(.hkCaption.weight(.medium))
            .foregroundStyle(Theme.ink2)
    }
}

/// GitHub-style grid of the last few weeks; darker cells mean more dictations that day.
struct ActivityHeatmap: View {
    /// Dictations per day, keyed by the start of the day.
    var counts: [Date: Int]
    var weeks = 12
    var now = Date()
    /// Chart geometry: twelve compact weeks fit beside a stat, so cells are their own measure.
    private static let cell: CGFloat = 10
    private static let gap: CGFloat = 3
    private static let radius: CGFloat = 2

    init(entries: [DictationHistoryEntry], weeks: Int = 12, now: Date = Date()) {
        counts = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.createdAt) }.mapValues(\.count)
        self.weeks = weeks
        self.now = now
    }

    init(counts: [Date: Int], weeks: Int = 12, now: Date = Date()) {
        self.counts = counts
        self.weeks = weeks
        self.now = now
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Columns are weeks ending with the current one; rows are weekdays from the locale's first day.
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let maxCount = max(1, counts.values.max() ?? 1)

        HStack(spacing: Self.gap) {
            ForEach(0..<weeks, id: \.self) { column in
                VStack(spacing: Self.gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let start = calendar.date(byAdding: .day, value: (column - weeks + 1) * 7, to: lastColumnStart) ?? today
                        let day = calendar.date(byAdding: .day, value: row, to: start) ?? today
                        let count = counts[day] ?? 0
                        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                            .fill(day > today ? Color.clear
                                  : count == 0 ? Theme.hairline
                                  : Theme.signal.opacity(0.3 + 0.7 * Double(count) / Double(maxCount)))
                            .frame(width: Self.cell, height: Self.cell)
                            .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                            .accessibilityElement()
                            .accessibilityHidden(day > today)
                            .accessibilityLabel("\(day.formatted(date: .long, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                    }
                }
                .reveal(column / 2, distance: 4) // the weeks fill in left to right
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
    }
}
