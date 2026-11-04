import SwiftUI

// HushKey's icon family. Every icon is drawn here on a 24 × 24 grid with one round-capped
// stroke (8.5 % of the icon's size, so 1.5 pt at 18), rounded corners of 2.5 units, and at
// most one sage "accent" part that fills in when the icon is selected. Nothing here is an SF
// Symbol: system menus (NSMenu, context menus) still use SF Symbols because they can only
// draw images, everything SwiftUI draws uses these.
//
// Motion: each icon has one small, characteristic gesture (the bell swings, the gear turns,
// the mic tilts toward you) that plays on hover and, a little larger, once on selection.

enum HushIcon: String, CaseIterable, Identifiable {
    // Places
    case dictation, insights, style, transforms, files, meetings, vocabulary, settings
    case connect, train, evaluate, silent
    // Window
    case sidebar, sun, moon, bell, power, lock, keyboard
    // Actions
    case play, stop, copy, check, edit, more, trash, search, close, undo, plus
    case chevronRight, chevronDown, arrowRight, arrowUpRight, arrowDownRight, download, share, refresh, insert
    // Things
    case warning, info, sparkle, flame, globe, folder, document, mic, waveform, record, ring, shield
    case clock, window, list, grid, speaker, checkCircle, cursor
    case mail, message, code, briefcase, quote, swap, minus

    var id: String { rawValue }

    /// The gesture an icon makes on hover.
    enum Motion { case tilt(Double), lift, spin(Double), nudge(CGFloat), pulse, swing }

    var motion: Motion {
        switch self {
        case .dictation, .mic: .tilt(-10)
        case .insights, .evaluate, .more, .record, .speaker, .waveform: .pulse
        case .style, .edit, .search, .connect: .tilt(8)
        case .transforms, .sparkle: .tilt(-14)
        case .settings: .spin(60)
        case .sun: .spin(45)
        case .close, .plus: .spin(90)
        case .refresh: .spin(180)
        case .moon: .tilt(-18)
        case .bell: .swing
        case .undo: .nudge(-2)
        case .arrowRight, .arrowDownRight, .chevronRight, .copy, .sidebar, .insert, .share, .meetings: .nudge(2)
        case .download, .chevronDown: .lift
        case .mail, .message, .quote: .tilt(-6)
        case .swap: .nudge(2)
        default: .lift
        }
    }

    /// SF Symbol names this family replaces, so call sites can move over one name at a time.
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
            "checklist": .list, "text.alignleft": .list, "square.grid.2x2": .grid,
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

    // MARK: Drawing

    struct Part {
        enum Role { case line, solid, accent }
        var path: Path
        var role: Role
    }

    var parts: [Part] {
        var parts: [Part] = []
        func line(_ build: (inout Pen) -> Void) { var pen = Pen(); build(&pen); parts.append(Part(path: pen.path, role: .line)) }
        func solid(_ build: (inout Pen) -> Void) { var pen = Pen(); build(&pen); parts.append(Part(path: pen.path, role: .solid)) }
        func accent(_ build: (inout Pen) -> Void) { var pen = Pen(); build(&pen); parts.append(Part(path: pen.path, role: .accent)) }

        switch self {
        case .dictation, .mic:
            accent { $0.rect(9, 3, 6, 11.5, r: 3) }
            line { $0.rect(9, 3, 6, 11.5, r: 3) }
            line { $0.arc(12, 11, r: 6.5, from: 0, sweep: 180); $0.move(12, 17.5); $0.to(12, 21) }

        case .insights:
            accent { $0.rect(10.25, 4, 3.5, 16.5, r: 1.75) }
            line {
                $0.rect(4, 12, 3.5, 8.5, r: 1.75)
                $0.rect(10.25, 4, 3.5, 16.5, r: 1.75)
                $0.rect(16.5, 8.5, 3.5, 12, r: 1.75)
            }

        case .style:
            line { $0.move(3, 19.5); $0.to(8.5, 5); $0.to(14, 19.5); $0.move(5, 14.5); $0.to(12, 14.5) }
            accent { $0.circle(18, 16, r: 3) }
            line { $0.circle(18, 16, r: 3); $0.move(21, 12.5); $0.to(21, 19.5) }

        case .transforms:
            line { $0.move(4, 20); $0.to(14.5, 9.5) }
            line { $0.move(13, 8); $0.to(16, 11) }
            accent { $0.star(18, 5.5, r: 3.4); $0.star(9, 4.5, r: 2); $0.star(20, 13, r: 1.7) }
            line { $0.star(18, 5.5, r: 3.4); $0.star(9, 4.5, r: 2); $0.star(20, 13, r: 1.7) }

        case .files, .document:
            line {
                $0.move(14, 3); $0.to(7.5, 3); $0.quad(5, 5.5, c: 5, 3); $0.to(5, 18.5); $0.quad(7.5, 21, c: 5, 21)
                $0.to(16.5, 21); $0.quad(19, 18.5, c: 19, 21); $0.to(19, 8); $0.to(14, 3)
                $0.move(14, 3); $0.to(14, 6.5); $0.quad(15.5, 8, c: 14, 8); $0.to(19, 8)
            }
            accent { $0.move(8.5, 12.5); $0.to(15.5, 12.5); $0.move(8.5, 16); $0.to(13, 16) }
            line { $0.move(8.5, 12.5); $0.to(15.5, 12.5); $0.move(8.5, 16); $0.to(13, 16) }

        case .meetings:
            accent { $0.circle(9, 8, r: 3.2) }
            line { $0.circle(9, 8, r: 3.2); $0.arc(9, 20.5, r: 6, from: 180, sweep: 180) }
            line { $0.circle(16.8, 9, r: 2.4); $0.arc(17, 19.5, r: 4.5, from: 215, sweep: 125) }

        case .vocabulary:
            line {
                $0.move(12, 6.5); $0.curve(3.5, 5, c1: 10, 5, c2: 6.5, 4.5); $0.to(3.5, 18.5)
                $0.curve(12, 20, c1: 6.5, 18, c2: 10, 18.5)
                $0.move(12, 6.5); $0.curve(20.5, 5, c1: 14, 5, c2: 17.5, 4.5); $0.to(20.5, 18.5)
                $0.curve(12, 20, c1: 17.5, 18, c2: 14, 18.5)
                $0.move(12, 6.5); $0.to(12, 20)
            }
            accent { $0.move(15.5, 5.1); $0.to(15.5, 10.5); $0.to(17, 9.2); $0.to(18.5, 10.5); $0.to(18.5, 4.8); $0.close() }

        case .settings:
            accent { $0.circle(12, 12, r: 3) }
            line { $0.gear(12, 12, outer: 9, inner: 6.9, teeth: 8); $0.circle(12, 12, r: 3) }

        case .connect:
            line { $0.arc(12, 13.5, r: 8, from: 180, sweep: 180) }
            accent { $0.rect(4, 13.5, 4, 7, r: 2); $0.rect(16, 13.5, 4, 7, r: 2) }
            line { $0.rect(4, 13.5, 4, 7, r: 2); $0.rect(16, 13.5, 4, 7, r: 2) }

        case .train:
            accent { $0.move(12, 3.5); $0.to(20.5, 8); $0.to(12, 12.5); $0.to(3.5, 8); $0.close() }
            line {
                $0.move(12, 3.5); $0.to(20.5, 8); $0.to(12, 12.5); $0.to(3.5, 8); $0.close()
                $0.move(3.5, 12); $0.to(12, 16.5); $0.to(20.5, 12)
                $0.move(3.5, 16); $0.to(12, 20.5); $0.to(20.5, 16)
            }

        case .evaluate:
            line { $0.circle(12, 12, r: 8.5); $0.circle(12, 12, r: 4.5) }
            accent { $0.circle(12, 12, r: 4.5) }
            solid { $0.circle(12, 12, r: 1.4) }

        case .silent:
            line {
                $0.move(7.5, 4.5); $0.to(16.5, 4.5); $0.quad(20.5, 8.5, c: 20.5, 4.5); $0.to(20.5, 13)
                $0.quad(16.5, 17, c: 20.5, 17); $0.to(11.5, 17); $0.to(7.5, 20.5); $0.to(7.5, 17)
                $0.quad(3.5, 13, c: 3.5, 17); $0.to(3.5, 8.5); $0.quad(7.5, 4.5, c: 3.5, 4.5); $0.close()
            }
            accent { $0.circle(8.5, 10.8, r: 1.6); $0.circle(12, 10.8, r: 1.6); $0.circle(15.5, 10.8, r: 1.6) }
            solid { $0.circle(8.5, 10.8, r: 1.1); $0.circle(12, 10.8, r: 1.1); $0.circle(15.5, 10.8, r: 1.1) }

        case .sidebar:
            accent { $0.rect(3.5, 4.5, 6, 15, r: 3, corners: .left) }
            line { $0.rect(3.5, 4.5, 17, 15, r: 3); $0.move(9.5, 4.5); $0.to(9.5, 19.5) }

        case .sun:
            accent { $0.circle(12, 12, r: 3.8) }
            line {
                $0.circle(12, 12, r: 3.8)
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4
                    $0.move(12 + 6.6 * cos(angle), 12 + 6.6 * sin(angle))
                    $0.to(12 + 8.6 * cos(angle), 12 + 8.6 * sin(angle))
                }
            }

        case .moon:
            accent { $0.crescent() }
            line { $0.crescent() }

        case .bell:
            line {
                $0.move(4.5, 17.5); $0.to(6, 15.5); $0.to(6, 11); $0.curve(12, 5, c1: 6, 7.7, c2: 8.7, 5)
                $0.curve(18, 11, c1: 15.3, 5, c2: 18, 7.7); $0.to(18, 15.5); $0.to(19.5, 17.5); $0.close()
                $0.move(12, 3); $0.to(12, 5)
            }
            accent { $0.move(9.8, 20.3); $0.quad(14.2, 20.3, c: 12, 22.3) }
            line { $0.move(9.8, 20.3); $0.quad(14.2, 20.3, c: 12, 22.3) }

        case .power:
            line { $0.arc(12, 13, r: 7.5, from: -60, sweep: 300); $0.move(12, 3.5); $0.to(12, 11.5) }

        case .lock:
            accent { $0.rect(5, 10.5, 14, 10, r: 2.5) }
            line {
                $0.rect(5, 10.5, 14, 10, r: 2.5)
                $0.move(8, 10.5); $0.to(8, 7.5); $0.quad(12, 3.5, c: 8, 3.5); $0.quad(16, 7.5, c: 16, 3.5); $0.to(16, 10.5)
            }

        case .keyboard:
            line { $0.rect(3, 6, 18, 12.5, r: 2.5); $0.move(8, 14.5); $0.to(16, 14.5) }
            solid { for x in [7.0, 10.3, 13.7, 17.0] { $0.circle(x, 10.3, r: 0.95) } }

        case .play:
            accent { $0.roundedTriangle() }
            line { $0.roundedTriangle() }

        case .stop:
            solid { $0.rect(6.5, 6.5, 11, 11, r: 2.5) }

        case .copy:
            line { $0.move(4.5, 13.5); $0.to(4.5, 7); $0.quad(7, 4.5, c: 4.5, 4.5); $0.to(13.5, 4.5) }
            accent { $0.rect(8.5, 8.5, 11, 11, r: 2.5) }
            line { $0.rect(8.5, 8.5, 11, 11, r: 2.5) }

        case .check:
            line { $0.move(5, 12.5); $0.to(10, 17.5); $0.to(19, 7) }

        case .checkCircle:
            accent { $0.circle(12, 12, r: 8.5) }
            line { $0.circle(12, 12, r: 8.5); $0.move(8.2, 12.3); $0.to(11, 15); $0.to(16, 9.3) }

        case .edit:
            line {
                $0.move(11, 4); $0.to(6.5, 4); $0.quad(4, 6.5, c: 4, 4); $0.to(4, 17.5); $0.quad(6.5, 20, c: 4, 20)
                $0.to(17.5, 20); $0.quad(20, 17.5, c: 20, 20); $0.to(20, 13)
            }
            accent { $0.move(17.5, 3.5); $0.to(20.5, 6.5); $0.to(12, 15); $0.to(8.5, 15.5); $0.to(9, 12); $0.close() }
            line { $0.move(17.5, 3.5); $0.to(20.5, 6.5); $0.to(12, 15); $0.to(8.5, 15.5); $0.to(9, 12); $0.close() }

        case .more:
            solid { $0.circle(5.5, 12, r: 1.6); $0.circle(12, 12, r: 1.6); $0.circle(18.5, 12, r: 1.6) }

        case .trash:
            line {
                $0.move(4, 6.5); $0.to(20, 6.5)
                $0.move(9, 6.5); $0.to(9, 5); $0.quad(10.5, 3.5, c: 9, 3.5); $0.to(13.5, 3.5); $0.quad(15, 5, c: 15, 3.5); $0.to(15, 6.5)
                $0.move(6, 6.5); $0.to(7, 18.8); $0.quad(9, 20.5, c: 7.2, 20.5); $0.to(15, 20.5); $0.quad(17, 18.8, c: 16.8, 20.5); $0.to(18, 6.5)
                $0.move(10, 10.5); $0.to(10, 16.5); $0.move(14, 10.5); $0.to(14, 16.5)
            }

        case .search:
            accent { $0.circle(10.5, 10.5, r: 6.5) }
            line { $0.circle(10.5, 10.5, r: 6.5); $0.move(15.3, 15.3); $0.to(20, 20) }

        case .close:
            line { $0.move(6.5, 6.5); $0.to(17.5, 17.5); $0.move(17.5, 6.5); $0.to(6.5, 17.5) }

        case .undo:
            line {
                $0.move(9, 8.5); $0.to(14.5, 8.5); $0.quad(20, 14, c: 20, 8.5); $0.quad(14.5, 19.5, c: 20, 19.5); $0.to(8, 19.5)
                $0.move(12.5, 4.5); $0.to(8.5, 8.5); $0.to(12.5, 12.5)
            }

        case .plus:
            line { $0.move(12, 5); $0.to(12, 19); $0.move(5, 12); $0.to(19, 12) }

        case .chevronRight:
            line { $0.move(9.5, 6); $0.to(15.5, 12); $0.to(9.5, 18) }

        case .chevronDown:
            line { $0.move(6, 9.5); $0.to(12, 15.5); $0.to(18, 9.5) }

        case .arrowRight:
            line { $0.move(4.5, 12); $0.to(19, 12); $0.move(13.5, 6.5); $0.to(19, 12); $0.to(13.5, 17.5) }

        case .arrowUpRight:
            line { $0.move(7, 17); $0.to(17, 7); $0.move(9, 7); $0.to(17, 7); $0.to(17, 15) }

        case .arrowDownRight:
            line { $0.move(7, 7); $0.to(17, 17); $0.move(9, 17); $0.to(17, 17); $0.to(17, 9) }

        case .download:
            line {
                $0.move(12, 3.5); $0.to(12, 14.5); $0.move(7.5, 10); $0.to(12, 14.5); $0.to(16.5, 10)
                $0.move(4, 15); $0.to(4, 17.5); $0.quad(6.5, 20, c: 4, 20); $0.to(17.5, 20); $0.quad(20, 17.5, c: 20, 20); $0.to(20, 15)
            }

        case .share:
            line {
                $0.move(12, 14.5); $0.to(12, 3.5); $0.move(7.5, 8); $0.to(12, 3.5); $0.to(16.5, 8)
                $0.move(4, 15); $0.to(4, 17.5); $0.quad(6.5, 20, c: 4, 20); $0.to(17.5, 20); $0.quad(20, 17.5, c: 20, 20); $0.to(20, 15)
            }

        case .refresh:
            line { $0.arc(12, 12, r: 7.5, from: -80, sweep: 300); $0.move(16, 3); $0.to(13.4, 4.6); $0.to(15.2, 7.4) }

        case .insert:
            line { $0.move(4, 6); $0.to(20, 6); $0.move(4, 18); $0.to(20, 18); $0.move(4, 12); $0.to(10, 12) }
            accent { $0.move(13.5, 8.5); $0.to(17, 12); $0.to(13.5, 15.5); $0.move(10, 12); $0.to(17, 12) }
            line { $0.move(13.5, 8.5); $0.to(17, 12); $0.to(13.5, 15.5); $0.move(10, 12); $0.to(17, 12) }

        case .warning:
            line {
                $0.move(10.3, 5); $0.quad(13.7, 5, c: 12, 2.2); $0.to(20.6, 17.2); $0.quad(18.9, 20, c: 22.2, 20)
                $0.to(5.1, 20); $0.quad(3.4, 17.2, c: 1.8, 20); $0.close()
                $0.move(12, 9.5); $0.to(12, 13.5)
            }
            solid { $0.circle(12, 16.6, r: 1.05) }

        case .info:
            line { $0.circle(12, 12, r: 8.5); $0.move(12, 11); $0.to(12, 16.5) }
            solid { $0.circle(12, 7.8, r: 1.05) }

        case .sparkle:
            accent { $0.star(11, 12, r: 7); $0.star(19, 5, r: 2.3) }
            line { $0.star(11, 12, r: 7); $0.star(19, 5, r: 2.3) }

        case .flame:
            accent { $0.flame() }
            line { $0.flame() }

        case .globe:
            line {
                $0.circle(12, 12, r: 8.5)
                $0.move(3.5, 12); $0.to(20.5, 12)
                $0.move(12, 3.5); $0.curve(12, 20.5, c1: 7.5, 7.5, c2: 7.5, 16.5)
                $0.move(12, 3.5); $0.curve(12, 20.5, c1: 16.5, 7.5, c2: 16.5, 16.5)
            }

        case .folder:
            accent { $0.folder() }
            line { $0.folder() }

        case .waveform:
            line {
                for (index, height) in [3.0, 8, 13, 6, 10, 4].enumerated() {
                    let x = 4.5 + Double(index) * 3
                    $0.move(x, 12 - height / 2); $0.to(x, 12 + height / 2)
                }
            }

        case .ring:
            line { $0.circle(12, 12, r: 8.5) }

        case .record:
            line { $0.circle(12, 12, r: 8.5) }
            accent { $0.circle(12, 12, r: 4.5) }
            solid { $0.circle(12, 12, r: 3.6) }

        case .shield:
            accent { $0.shield() }
            line { $0.shield(); $0.move(9, 12.2); $0.to(11.2, 14.4); $0.to(15.2, 10.2) }

        case .clock:
            line { $0.circle(12, 12, r: 8.5); $0.move(12, 7.5); $0.to(12, 12); $0.to(15, 14) }

        case .window:
            line { $0.rect(3.5, 4.5, 17, 15, r: 3); $0.move(3.5, 9); $0.to(20.5, 9) }
            solid { $0.circle(6.5, 6.8, r: 0.8); $0.circle(9, 6.8, r: 0.8) }

        case .list:
            line { $0.move(9.5, 7); $0.to(20, 7); $0.move(9.5, 12); $0.to(20, 12); $0.move(9.5, 17); $0.to(16, 17) }
            solid { $0.circle(5, 7, r: 1.3); $0.circle(5, 12, r: 1.3); $0.circle(5, 17, r: 1.3) }

        case .grid:
            accent { $0.rect(4, 4, 7, 7, r: 2) }
            line { $0.rect(4, 4, 7, 7, r: 2); $0.rect(13, 4, 7, 7, r: 2); $0.rect(4, 13, 7, 7, r: 2); $0.rect(13, 13, 7, 7, r: 2) }

        case .speaker:
            line {
                $0.move(4, 9.5); $0.to(7.5, 9.5); $0.to(12, 5.5); $0.to(12, 18.5); $0.to(7.5, 14.5); $0.to(4, 14.5); $0.close()
                $0.arc(13, 12, r: 3.5, from: -50, sweep: 100)
                $0.arc(13, 12, r: 7, from: -50, sweep: 100)
            }

        case .mail:
            accent { $0.rect(3.5, 5.5, 17, 13, r: 2.5) }
            line { $0.rect(3.5, 5.5, 17, 13, r: 2.5); $0.move(4.5, 7.5); $0.to(12, 13); $0.to(19.5, 7.5) }

        case .message:
            accent { $0.bubble() }
            line { $0.bubble() }

        case .code:
            line { $0.move(8.5, 7); $0.to(3.5, 12); $0.to(8.5, 17); $0.move(15.5, 7); $0.to(20.5, 12); $0.to(15.5, 17); $0.move(13.5, 5); $0.to(10.5, 19) }

        case .briefcase:
            accent { $0.rect(3.5, 7.5, 17, 12.5, r: 2.5) }
            line {
                $0.rect(3.5, 7.5, 17, 12.5, r: 2.5)
                $0.move(9, 7.5); $0.to(9, 6); $0.quad(10.5, 4.5, c: 9, 4.5); $0.to(13.5, 4.5); $0.quad(15, 6, c: 15, 4.5); $0.to(15, 7.5)
                $0.move(3.5, 12.5); $0.to(20.5, 12.5)
            }

        case .quote:
            solid { $0.circle(7.5, 10, r: 2.6); $0.circle(16.5, 10, r: 2.6) }
            line { $0.move(10.1, 10); $0.quad(6, 17.5, c: 10.1, 15.5); $0.move(19.1, 10); $0.quad(15, 17.5, c: 19.1, 15.5) }

        case .swap:
            line {
                $0.move(4, 8.5); $0.to(19, 8.5); $0.move(15, 4.5); $0.to(19, 8.5); $0.to(15, 12.5)
                $0.move(20, 15.5); $0.to(5, 15.5); $0.move(9, 11.5); $0.to(5, 15.5); $0.to(9, 19.5)
            }

        case .minus:
            line { $0.move(5, 12); $0.to(19, 12) }

        case .cursor:
            line {
                $0.move(9, 4); $0.quad(12, 6, c: 11, 4); $0.quad(15, 4, c: 13, 4)
                $0.move(9, 20); $0.quad(12, 18, c: 11, 20); $0.quad(15, 20, c: 13, 20)
                $0.move(12, 6); $0.to(12, 18)
            }
        }
        return parts
    }
}

// MARK: - Pen

/// A path builder on the 24-unit grid, scaled to the icon's frame when drawn.
struct Pen {
    var path = Path()

    enum Corners { case all, left }

    mutating func move(_ x: Double, _ y: Double) { path.move(to: CGPoint(x: x, y: y)) }
    mutating func to(_ x: Double, _ y: Double) { path.addLine(to: CGPoint(x: x, y: y)) }
    mutating func quad(_ x: Double, _ y: Double, c cx: Double, _ cy: Double) {
        path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
    }
    mutating func curve(_ x: Double, _ y: Double, c1: (Double, Double), c2: (Double, Double)) {
        path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1.0, y: c1.1), control2: CGPoint(x: c2.0, y: c2.1))
    }
    mutating func curve(_ x: Double, _ y: Double, c1 x1: Double, _ y1: Double, c2 x2: Double, _ y2: Double) {
        curve(x, y, c1: (x1, y1), c2: (x2, y2))
    }
    mutating func close() { path.closeSubpath() }

    mutating func circle(_ x: Double, _ y: Double, r: Double) {
        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    mutating func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double, corners: Corners = .all) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        switch corners {
        case .all: path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
        case .left:
            path.addRoundedRect(in: rect, cornerRadii: RectangleCornerRadii(topLeading: r, bottomLeading: r), style: .continuous)
        }
    }

    /// An arc in degrees; 0 points right and positive sweeps clockwise on screen.
    mutating func arc(_ x: Double, _ y: Double, r: Double, from start: Double, sweep: Double) {
        let center = CGPoint(x: x, y: y)
        let begin = CGPoint(x: x + r * cos(start * .pi / 180), y: y + r * sin(start * .pi / 180))
        path.move(to: begin)
        path.addRelativeArc(center: center, radius: r, startAngle: .degrees(start), delta: .degrees(sweep))
    }

    /// A four-pointed sparkle with softly pinched sides.
    mutating func star(_ x: Double, _ y: Double, r: Double) {
        let pinch = r * 0.18
        move(x, y - r)
        quad(x + r, y, c: x + pinch, y - pinch)
        quad(x, y + r, c: x + pinch, y + pinch)
        quad(x - r, y, c: x - pinch, y + pinch)
        quad(x, y - r, c: x - pinch, y - pinch)
        close()
    }

    mutating func gear(_ x: Double, _ y: Double, outer: Double, inner: Double, teeth: Int) {
        let step = 2 * Double.pi / Double(teeth)
        for tooth in 0..<teeth {
            let mid = Double(tooth) * step - .pi / 2
            let points: [(Double, Double)] = [(mid - step * 0.32, inner), (mid - step * 0.17, outer),
                                              (mid + step * 0.17, outer), (mid + step * 0.32, inner)]
            for (index, (angle, radius)) in points.enumerated() {
                let point = (x + radius * cos(angle), y + radius * sin(angle))
                if tooth == 0, index == 0 { move(point.0, point.1) } else { to(point.0, point.1) }
            }
        }
        close()
    }

    /// The moon: a disc with a bite taken from its upper right.
    mutating func crescent() {
        // Outer circle (12, 12) r 8.5, bite circle (17, 7.5) r 7.
        let (c1, r1) = ((12.0, 12.0), 8.5)
        let (c2, r2) = ((17.0, 7.5), 7.0)
        let dx = c2.0 - c1.0, dy = c2.1 - c1.1
        let d = (dx * dx + dy * dy).squareRoot()
        let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        let h = (r1 * r1 - a * a).squareRoot()
        let mx = c1.0 + a * dx / d, my = c1.1 + a * dy / d
        let p1 = (mx + h * dy / d, my - h * dx / d)
        let p2 = (mx - h * dy / d, my + h * dx / d)
        func angle(_ c: (Double, Double), _ p: (Double, Double)) -> Double { atan2(p.1 - c.1, p.0 - c.0) }
        // Outer: from p2 the long way round (away from the bite) to p1.
        let o1 = angle(c1, p2), o2 = angle(c1, p1)
        var outerSweep = o2 - o1
        while outerSweep <= 0 { outerSweep += 2 * .pi }
        if outerSweep < .pi { outerSweep -= 2 * .pi }
        // Inner: back from p1 to p2 along the bite, the short way.
        let i1 = angle(c2, p1), i2 = angle(c2, p2)
        var innerSweep = i2 - i1
        while innerSweep > .pi { innerSweep -= 2 * .pi }
        while innerSweep < -.pi { innerSweep += 2 * .pi }
        move(p2.0, p2.1)
        path.addRelativeArc(center: CGPoint(x: c1.0, y: c1.1), radius: r1, startAngle: .radians(o1), delta: .radians(outerSweep))
        path.addRelativeArc(center: CGPoint(x: c2.0, y: c2.1), radius: r2, startAngle: .radians(i1), delta: .radians(innerSweep))
        close()
    }

    mutating func roundedTriangle() {
        move(8, 6.2); quad(9.6, 5.3, c: 8, 4.6); to(18.2, 10.6); quad(18.2, 13.4, c: 20.1, 12)
        to(9.6, 18.7); quad(8, 17.8, c: 8, 19.4); close()
    }

    mutating func flame() {
        move(12, 3)
        curve(17.5, 14, c1: 13, 7, c2: 17.5, 9)
        curve(12, 20.5, c1: 17.5, 18, c2: 15, 20.5)
        curve(6.5, 14.5, c1: 9, 20.5, c2: 6.5, 18)
        curve(9.5, 9, c1: 6.5, 12, c2: 8, 10.5)
        curve(11.5, 12.5, c1: 9.8, 11, c2: 10.5, 12.2)
        curve(12, 3, c1: 13, 9, c2: 11, 6)
        close()
    }

    mutating func folder() {
        move(3.5, 7); quad(6, 4.5, c: 3.5, 4.5); to(9.5, 4.5); to(11.5, 7); to(18, 7); quad(20.5, 9.5, c: 20.5, 7)
        to(20.5, 17); quad(18, 19.5, c: 20.5, 19.5); to(6, 19.5); quad(3.5, 17, c: 3.5, 19.5); close()
    }

    mutating func bubble() {
        move(12, 4.5); curve(20.5, 11.5, c1: 17, 4.5, c2: 20.5, 7.6); curve(12, 18.5, c1: 20.5, 15.4, c2: 17, 18.5)
        curve(9.2, 18.1, c1: 11, 18.5, c2: 10, 18.4); to(5, 20); to(5.9, 16.3)
        curve(3.5, 11.5, c1: 4.4, 15, c2: 3.5, 13.4); curve(12, 4.5, c1: 3.5, 7.6, c2: 7, 4.5); close()
    }

    mutating func shield() {
        move(12, 3.5); to(19, 6.2); to(19, 11.5); curve(12, 20.5, c1: 19, 15.8, c2: 16, 19)
        curve(5, 11.5, c1: 8, 19, c2: 5, 15.8); to(5, 6.2); close()
    }
}

// MARK: - View

extension EnvironmentValues {
    @Entry var hushIconSize: CGFloat = 18
    /// Set by the hub's button styles and rows, so icons inside them play their hover gesture.
    @Entry var hushIconHover = false
    /// Set by selected rows and tabs: the icon's accent part fills in sage.
    @Entry var hushIconActive = false
}

extension View {
    func hushIconSize(_ size: CGFloat) -> some View { environment(\.hushIconSize, size) }
    func hushIconHover(_ hovering: Bool) -> some View { environment(\.hushIconHover, hovering) }
    func hushIconActive(_ active: Bool) -> some View { environment(\.hushIconActive, active) }
}

/// One HushKey icon (a glyph from `HushIcon`). Size, hover and selection come from the environment unless given here.
struct Glyph: View {
    var icon: HushIcon
    var size: CGFloat?
    var active: Bool?
    var hovering: Bool?

    @Environment(\.hushIconSize) private var environmentSize
    @Environment(\.hushIconHover) private var environmentHover
    @Environment(\.hushIconActive) private var environmentActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flourish = false

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
        let lineWidth = max(1.1, side * 0.085) * 24 / side
        let amount: Double = reduceMotion ? 0 : flourish ? 1.5 : isHovering ? 1 : 0

        ZStack {
            ForEach(Array(icon.parts.enumerated()), id: \.offset) { _, part in
                let shape = GridShape(path: part.path)
                switch part.role {
                case .line:
                    shape.stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                case .solid:
                    shape.fill()
                case .accent:
                    shape.fill(Theme.signal.opacity(isActive ? 0.28 : 0))
                        .scaleEffect(isActive ? 1 : 0.6)
                }
            }
        }
        .frame(width: side, height: side)
        .modifier(IconMotion(motion: icon.motion, amount: amount))
        .animation(.spring(response: 0.38, dampingFraction: 0.55), value: amount)
        .animation(Theme.snappy, value: isActive)
        .onChange(of: isActive) { _, now in
            guard now, !reduceMotion else { return }
            flourish = true
            Task {
                try? await Task.sleep(for: .seconds(0.18))
                flourish = false
            }
        }
        .accessibilityHidden(true)
    }
}

/// A glyph for an SF Symbol name that comes from the model (a mode's or category's `symbol`):
/// HushKey's own drawing when the family has one, the system symbol otherwise.
struct SymbolGlyph: View {
    var symbol: String
    var size: CGFloat?
    @Environment(\.hushIconSize) private var environmentSize

    init(_ symbol: String, size: CGFloat? = nil) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        if let icon = HushIcon(symbol: symbol) {
            Glyph(icon, size: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: (size ?? environmentSize) * 0.8))
                .frame(width: size ?? environmentSize, height: size ?? environmentSize)
        }
    }
}

/// Draws a 24-unit path scaled into the frame.
private struct GridShape: Shape {
    var path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
            .scaledBy(x: scale, y: scale))
    }
}

private struct IconMotion: ViewModifier {
    var motion: HushIcon.Motion
    var amount: Double

    func body(content: Content) -> some View {
        switch motion {
        case .tilt(let degrees):
            content.rotationEffect(.degrees(degrees * amount), anchor: .bottom)
        case .spin(let degrees):
            content.rotationEffect(.degrees(degrees * amount))
        case .swing:
            content.rotationEffect(.degrees(14 * amount), anchor: .top)
        case .lift:
            content.offset(y: -1.5 * amount)
        case .nudge(let distance):
            content.offset(x: distance * amount)
        case .pulse:
            content.scaleEffect(1 + 0.1 * amount)
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
