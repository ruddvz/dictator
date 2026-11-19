import SwiftUI

/// Curated system symbols for HushKey's native macOS controls.
/// The custom ribbon remains the brand mark; navigation and actions use SF Symbols for crisp,
/// familiar shapes at every scale.
enum HushIcon: String, CaseIterable, Identifiable {
    case dictation, insights, style, transforms, files, meetings, vocabulary, settings
    case connect, train, evaluate, silent
    case sidebar, sun, moon, bell, power, lock, keyboard
    case play, stop, copy, check, edit, more, trash, search, close, undo, plus
    case chevronRight, chevronDown, arrowRight, arrowUpRight, arrowDownRight, download, share, refresh, insert
    case warning, info, sparkle, flame, globe, folder, document, mic, waveform, record, ring, shield
    case clock, window, list, tasks, shorten, grid, speaker, checkCircle, cursor
    case mail, message, code, briefcase, quote, swap, minus

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .dictation, .mic: "mic"
        case .insights: "chart.bar"
        case .style: "textformat"
        case .transforms: "wand.and.stars"
        case .files, .document: "doc.text"
        case .meetings: "person.2.wave.2"
        case .vocabulary: "character.book.closed"
        case .settings: "gearshape"
        case .connect: "headphones"
        case .train: "square.stack.3d.up"
        case .evaluate: "chart.bar.xaxis"
        case .silent: "text.bubble"
        case .sidebar: "sidebar.left"
        case .sun: "sun.max"
        case .moon: "moon"
        case .bell: "bell"
        case .power: "power"
        case .lock: "lock"
        case .keyboard: "keyboard"
        case .play: "play"
        case .stop: "stop"
        case .copy: "doc.on.doc"
        case .check: "checkmark"
        case .edit: "pencil"
        case .more: "ellipsis"
        case .trash: "trash"
        case .search: "magnifyingglass"
        case .close: "xmark"
        case .undo: "arrow.uturn.backward"
        case .plus: "plus"
        case .chevronRight: "chevron.right"
        case .chevronDown: "chevron.down"
        case .arrowRight: "arrow.right"
        case .arrowUpRight: "arrow.up.right"
        case .arrowDownRight: "arrow.down.right"
        case .download: "square.and.arrow.down"
        case .share: "square.and.arrow.up"
        case .refresh: "arrow.clockwise"
        case .insert: "text.insert"
        case .warning: "exclamationmark.triangle"
        case .info: "info.circle"
        case .sparkle: "sparkles"
        case .flame: "flame"
        case .globe: "globe"
        case .folder: "folder"
        case .waveform: "waveform"
        case .record: "record.circle"
        case .ring: "circle"
        case .shield: "checkmark.shield"
        case .clock: "clock"
        case .window: "macwindow"
        case .list: "list.bullet"
        case .tasks: "checklist"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .grid: "square.grid.2x2"
        case .speaker: "speaker.wave.2"
        case .checkCircle: "checkmark.circle"
        case .cursor: "text.cursor"
        case .mail: "envelope"
        case .message: "bubble.left"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .briefcase: "briefcase"
        case .quote: "text.quote"
        case .swap: "arrow.left.arrow.right"
        case .minus: "minus"
        }
    }

    /// Filled variants make selected navigation and status states read clearly without relying on color.
    var selectedSymbolName: String {
        switch self {
        case .dictation, .mic: "mic.fill"
        case .insights: "chart.bar.fill"
        case .style: "textformat.size"
        case .transforms: "wand.and.stars.inverse"
        case .files, .document: "doc.text.fill"
        case .meetings: "person.2.wave.2.fill"
        case .vocabulary: "character.book.closed.fill"
        case .settings: "gearshape.fill"
        case .connect: "headphones.circle.fill"
        case .train: "square.stack.3d.up.fill"
        case .evaluate: "chart.bar.fill"
        case .silent: "text.bubble.fill"
        case .sun: "sun.max.fill"
        case .moon: "moon.fill"
        case .bell: "bell.fill"
        case .lock: "lock.fill"
        case .play: "play.fill"
        case .stop: "stop.fill"
        case .trash: "trash.fill"
        case .folder: "folder.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .flame: "flame.fill"
        case .record: "record.circle.fill"
        case .shield: "checkmark.shield.fill"
        case .checkCircle: "checkmark.circle.fill"
        case .mail: "envelope.fill"
        case .message: "bubble.left.fill"
        case .briefcase: "briefcase.fill"
        default: symbolName
        }
    }

    /// Keeps existing SF Symbol call sites concise while mapping them to HushKey's selected variants.
    init?(symbol: String) {
        let name = symbol.replacingOccurrences(of: ".fill", with: "")
        let map: [String: HushIcon] = [
            "mic": .mic, "chart.bar": .insights, "textformat": .style, "wand.and.stars": .transforms,
            "doc.text": .document, "person.2.wave.2": .meetings, "character.book.closed": .vocabulary,
            "gearshape": .settings, "headphones": .connect, "square.stack.3d.up": .train,
            "chart.bar.xaxis": .evaluate, "text.bubble": .silent, "sidebar.left": .sidebar,
            "sun.max": .sun, "moon": .moon, "bell": .bell, "power": .power, "lock": .lock,
            "lock.open": .lock, "keyboard": .keyboard, "play": .play, "stop": .stop,
            "doc.on.doc": .copy, "doc.on.clipboard": .copy, "checkmark": .check, "pencil": .edit,
            "square.and.pencil": .edit, "ellipsis": .more, "trash": .trash, "magnifyingglass": .search,
            "xmark": .close, "xmark.circle": .close, "arrow.uturn.backward": .undo,
            "arrow.uturn.backward.circle": .undo, "plus": .plus, "plus.circle": .plus,
            "chevron.right": .chevronRight, "chevron.down": .chevronDown, "arrow.right": .arrowRight,
            "arrow.up.right": .arrowUpRight, "square.and.arrow.down": .download,
            "square.and.arrow.up": .share, "arrow.clockwise": .refresh, "text.insert": .insert,
            "exclamationmark.triangle": .warning, "exclamationmark.circle": .warning,
            "info.circle": .info, "sparkles": .sparkle, "flame": .flame, "globe": .globe,
            "folder": .folder, "doc.richtext": .document, "note.text": .document, "waveform.path": .waveform,
            "waveform": .waveform, "record.circle": .record, "circle": .ring, "lock.shield": .shield,
            "checkmark.shield": .shield, "hourglass": .clock, "clock": .clock, "macwindow": .window,
            "checklist": .tasks, "text.alignleft": .list, "arrow.down.right.and.arrow.up.left": .shorten, "square.grid.2x2": .grid,
            "speaker.wave.2": .speaker, "checkmark.circle": .checkCircle, "text.cursor": .cursor,
            "character.cursor.ibeam": .cursor, "slider.horizontal.3": .settings,
            "dot.radiowaves.left.and.right": .waveform, "mic.badge.plus": .mic,
            "envelope": .mail, "bubble.left": .message, "bubble.left.and.bubble.right": .message,
            "chevron.left.forwardslash.chevron.right": .code, "briefcase": .briefcase, "text.quote": .quote,
            "arrow.left.arrow.right": .swap, "list.bullet": .list, "minus": .minus, "waveform.badge.mic": .mic,
            "headphones.slash": .connect, "questionmark": .info, "text.badge.xmark": .close,
            "hand.raised.slash": .warning, "waveform.badge.plus": .waveform, "text.badge.plus": .document,
            "text.magnifyingglass": .search, "circle.dashed": .record, "checkmark.seal": .checkCircle,
            "arrow.down.right": .arrowDownRight, "hand.tap": .record, "person.2": .meetings,
        ]
        guard let icon = map[name] ?? map[symbol] else { return nil }
        self = icon
    }
}

// MARK: - View

extension EnvironmentValues {
    @Entry var hushIconSize: CGFloat = 18
    @Entry var hushIconHover = false
    @Entry var hushIconActive = false
}

extension View {
    func hushIconSize(_ size: CGFloat) -> some View { environment(\.hushIconSize, size) }
    func hushIconHover(_ hovering: Bool) -> some View { environment(\.hushIconHover, hovering) }
    func hushIconActive(_ active: Bool) -> some View { environment(\.hushIconActive, active) }
}

/// Native SF Symbol rendered at the design-system size with a quiet selected/hover state.
struct Glyph: View {
    var icon: HushIcon
    var size: CGFloat?
    var active: Bool?
    var hovering: Bool?

    @Environment(\.hushIconSize) private var environmentSize
    @Environment(\.hushIconHover) private var environmentHover
    @Environment(\.hushIconActive) private var environmentActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ icon: HushIcon, size: CGFloat? = nil, active: Bool? = nil, hovering: Bool? = nil) {
        self.icon = icon
        self.size = size
        self.active = active
        self.hovering = hovering
    }

    var body: some View {
        let side = size ?? environmentSize
        let isActive = active ?? environmentActive
        let isHovering = hovering ?? environmentHover
        Image(systemName: isActive ? icon.selectedSymbolName : icon.symbolName)
            .font(.system(size: side, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(width: side, height: side)
            .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering && !reduceMotion)
            .accessibilityHidden(true)
    }
}

/// A glyph for an SF Symbol name that comes from the model (a mode's or category's `symbol`).
struct SymbolGlyph: View {
    var symbol: String
    var size: CGFloat?
    @Environment(\.hushIconSize) private var environmentSize

    init(_ symbol: String, size: CGFloat? = nil) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        let side = size ?? environmentSize
        if let icon = HushIcon(symbol: symbol) {
            Glyph(icon, size: side)
        } else {
            Image(systemName: symbol)
                .font(.system(size: side, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Labels and buttons

extension Label where Title == Text, Icon == Glyph {
    @MainActor init(_ title: String, icon: HushIcon) {
        self.init { Text(title) } icon: { Glyph(icon) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Glyph> {
    @MainActor init(_ title: String, icon: HushIcon, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, icon: icon) }
    }
}
