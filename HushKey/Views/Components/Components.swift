import SwiftUI

/// The one page header: serif title, optional subtitle (or a custom `detail` line), and
/// trailing actions centred on the title line. It owns the gap to the first section, so every
/// page's content starts the same distance below its title.
struct PageHeader<Detail: View, Actions: View>: View {
    var eyebrow: String = ""
    var title: String
    var subtitle: String = ""
    @ViewBuilder var detail: Detail
    @ViewBuilder var actions: Actions

    var body: some View {
        // Trailing actions line up with the title line, not the middle of title + subtitle.
        HStack(alignment: .pageTitle, spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: Theme.titleGap) {
                // Only lab steps carry a visible eyebrow; elsewhere the sidebar already says where you are.
                if eyebrow.hasPrefix("Step") {
                    SectionLabel(title: eyebrow)
                }
                // HushKey's voice ribbon is the page mark, kept separate from the navigation
                // glyphs so the screens have a recognizable product signature without icon tiles.
                HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                    RibbonMark()
                        .alignmentGuide(.pageTitle) { $0[VerticalAlignment.center] }
                    Text(title)
                        .font(.hkTitle1)
                        .accessibilityIdentifier("page.header")
                        .alignmentGuide(.pageTitle) { $0[VerticalAlignment.center] }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                        .frame(maxWidth: Theme.readingWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                detail
            }
            Spacer(minLength: Theme.s4)
            HStack(spacing: Theme.controlGap) { actions }
                .alignmentGuide(.pageTitle) { $0[VerticalAlignment.center] }
        }
        // `PageColumn` spaces sections by `sectionGap`; the header adds the rest of `headerGap`.
        .padding(.bottom, Theme.headerGap - Theme.sectionGap)
        .reveal(0)
    }
}

extension VerticalAlignment {
    /// The centre of a `PageHeader`'s title line.
    private enum PageTitle: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }
    static let pageTitle = VerticalAlignment(PageTitle.self)
}

extension PageHeader where Detail == EmptyView {
    init(eyebrow: String = "", title: String, subtitle: String = "", @ViewBuilder actions: () -> Actions) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, detail: { EmptyView() }, actions: actions)
    }
}

extension PageHeader where Detail == EmptyView, Actions == EmptyView {
    init(eyebrow: String = "", title: String, subtitle: String = "") {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, detail: { EmptyView() }, actions: { EmptyView() })
    }
}

extension View {
    /// The one page layout: a column up to `maxWidth`, `pageTop` below the top of the sheet and
    /// `pageGutter` from its sides. Every page starts at the home page's left edge, so titles
    /// don't jump when you switch pages; narrower pages end earlier on the right.
    func pageLayout(maxWidth: CGFloat = Theme.pageWidth) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: Theme.homeWidth, alignment: .leading)
            .padding(.horizontal, Theme.pageGutter)
            .padding(.top, Theme.pageTop)
            .padding(.bottom, Theme.pageBottom)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// A hub page's column: a `PageHeader` first, then sections `sectionGap` apart, laid out by
/// `pageLayout`. Pages use this instead of their own stack so gaps can't drift.
struct PageColumn<Content: View>: View {
    var maxWidth: CGFloat = Theme.pageWidth
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionGap) { content }
            .pageLayout(maxWidth: maxWidth)
    }
}

/// The one in-page section heading: `hkTitle3`, an optional one-line subtitle, and an
/// optional trailing accessory (a count, a search field, an icon button) on the title line.
struct SectionTitle<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack(alignment: .center, spacing: Theme.controlGap) {
                Text(title).font(.hkTitle3).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.s4)
                trailing
            }
            // Accessories are at most a field tall, so a title row is the same height on every page.
            .frame(minHeight: Theme.fieldHeight)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: Theme.readingWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// A titled section on a page: `SectionTitle`, then its content `sectionTitleGap` below and
/// `stackGap` apart.
struct PageSection<Trailing: View, Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleGap) {
            SectionTitle(title, subtitle: subtitle) { trailing }
            VStack(alignment: .leading, spacing: Theme.stackGap) { content }
        }
    }
}

extension PageSection where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// Hairline between sections of a page.
struct SectionRule: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: Theme.hairlineWidth)
    }
}

// MARK: - Selectable cards

/// Grid whose rows take the height of their tallest card, with `gridGap` gutters both ways.
struct CardGrid<Item: Identifiable, Cell: View>: View {
    var items: [Item]
    var columns = 3
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: Theme.gridGap, verticalSpacing: Theme.gridGap) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { item in
                        cell(item).frame(maxHeight: .infinity, alignment: .top)
                    }
                    // Short last rows keep full-width columns.
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

/// One choice among cards (Style's cleanup and tone cards, Transforms' tiles): an optional
/// glyph, a serif title with a check when chosen, a short description, then optional content
/// pinned to the bottom. Same padding, minimum height and selected treatment everywhere.
struct SelectableCard<Footer: View>: View {
    var title: String
    var detail: String
    var symbol: String? = nil
    var isSelected: Bool
    var minHeight: CGFloat = Theme.optionCardHeight
    var detailLines: Int? = nil
    var action: () -> Void
    @ViewBuilder var footer: Footer
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.stackGap) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.iconGap) {
                    if let symbol {
                        SymbolGlyph(symbol, size: Theme.iconL)
                            .hushIconActive(isSelected)
                            .hushIconHover(hovering)
                            .foregroundStyle(isSelected || hovering ? Theme.signal : Theme.ink2)
                            .frame(width: Theme.iconColumn)
                    }
                    Text(title)
                        .font(.hkCardTitle)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Glyph(.checkCircle, size: Theme.iconM)
                        .foregroundStyle(Theme.signal)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(isSelected ? 1 : 0.6)
                        .accessibilityHidden(true)
                }
                Text(detail)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(detailLines)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                footer
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .fill(isSelected ? Theme.signalSoft : hovering ? Theme.hover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(isSelected ? Theme.signal : Theme.hairline,
                              lineWidth: isSelected ? Theme.selectedStroke : Theme.hairlineWidth))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .animation(Theme.snappy, value: isSelected)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SelectableCard where Footer == EmptyView {
    init(title: String, detail: String, symbol: String? = nil, isSelected: Bool,
         minHeight: CGFloat = Theme.optionCardHeight, detailLines: Int? = nil, action: @escaping () -> Void) {
        self.init(title: title, detail: detail, symbol: symbol, isSelected: isSelected,
                  minHeight: minHeight, detailLines: detailLines, action: action) { EmptyView() }
    }
}

/// Gives any remaining GroupBox the same filled card as a settings group.
struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            configuration.label
                .font(.hkTitle3)
                .foregroundStyle(Theme.ink)
                .labelStyle(.titleOnly)
            configuration.content
                .font(.hkBody)
        }
        .card(padding: Theme.cardPadding)
    }
}

// MARK: - Rows (Wispr-style: one-line label, short description, right-aligned control)

/// A titled stack of rows on one filled card. Rows draw a hairline above themselves; the
/// first one is clipped away, so dividers only ever sit between rows.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleGap) {
            if let title {
                SectionTitle(title)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -Theme.hairlineWidth)
                .padding(.horizontal, Theme.rowPaddingH)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, Theme.s0)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .reveal(1)
    }
}

/// Hairline that separates rows inside a `SettingsGroup` or `ListGroup`.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: Theme.hairlineWidth)
    }
}

/// Label, optional one-line description, and a right-aligned control.
struct SettingsRow<Control: View>: View {
    var title: String
    var detail: String? = nil
    var detailTint: Color = Theme.ink2
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(title)
                    .font(.hkRowTitle)
                    .foregroundStyle(Theme.ink)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.hkCallout)
                        .foregroundStyle(detailTint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // One measure for every row's detail, so lines wrap at the same place down a group.
            .frame(maxWidth: Theme.detailWidth, alignment: .leading)
            Spacer(minLength: Theme.s4)
            control
        }
        .padding(.vertical, Theme.rowPaddingV)
        .frame(minHeight: Theme.rowMinHeight)
        .overlay(alignment: .top) { RowDivider() }
    }
}

extension SettingsRow where Control == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// A row-shaped slot for content that isn't label + control, such as an inline editor.
struct GroupRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.stackGap) { content }
            .padding(.vertical, Theme.rowPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { RowDivider() }
    }
}

/// Outlined list on the sheet (Wispr's history and dictionary lists): 52 pt rows split by hairlines.
struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.top, -Theme.hairlineWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .surface(.outlined)
            .reveal(1)
    }
}

/// One list row with a hover fill and hover-revealed trailing actions.
struct ListRow<Leading: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s3) {
            leading
            Spacer(minLength: Theme.s2)
            HStack(spacing: Theme.s0) { actions }
                .opacity(hovering ? 1 : 0)
                .offset(x: hovering ? 0 : Theme.s2)
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.s3)
        .frame(minHeight: Theme.listRow)
        .background(hovering ? Theme.rowHover : .clear)
        .overlay(alignment: .top) { RowDivider() }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
    }
}

/// Fixed-width menu for a settings row, styled like a secondary button with a chevron.
struct MenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var width: CGFloat = Theme.menuWidth
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            MenuPickerLabel(title: options.first(where: { $0.value == selection })?.title ?? "Choose",
                            width: width, hovering: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// The closed look of a `MenuPicker`: title, chevron, `sheet` fill and a hairline. Shared by
/// controls that open something else, like the language grid, so every menu looks the same.
struct MenuPickerLabel: View {
    var title: String
    var icon: HushIcon?
    /// Fixed width; nil grows to fit the title, never narrower than a menu.
    var width: CGFloat? = Theme.menuWidth
    var hovering = false

    var body: some View {
        HStack(spacing: Theme.s2) {
            if let icon {
                Glyph(icon).hushIconSize(Theme.iconM).foregroundStyle(Theme.ink2)
            }
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
            Glyph(.chevronDown)
                .hushIconSize(Theme.iconS)
                .foregroundStyle(Theme.ink2)
        }
        .font(.hkControl)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.s3)
        .frame(width: width, height: Theme.controlHeight)
        .frame(minWidth: width == nil ? Theme.menuWidth : nil)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .strokeBorder(hovering ? Theme.fieldEdgeHover : Theme.hairline, lineWidth: Theme.hairlineWidth))
        .contentShape(Rectangle())
    }
}

/// Sage switch at Wispr's toggle size, for the right side of a settings row.
struct RowToggle: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.signal)
            .controlSize(.regular)
    }
}

/// Underlined text tabs (Wispr's "All · Personal · Shared" bar) over a hairline.
struct UnderlineTabs<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    /// An optional count after each title, in `ink3`; hidden at 0.
    var count: ((Value) -> Int)? = nil
    @Namespace private var underline

    var body: some View {
        HStack(spacing: Theme.s5) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(Theme.snappy) { selection = option.value }
                } label: {
                    VStack(spacing: Theme.s2) {
                        HStack(spacing: Theme.s1) {
                            // The semibold title, hidden, reserves the width so selecting a tab doesn't reflow the bar.
                            ZStack {
                                Text(option.title).font(.hkCallout.weight(.semibold)).hidden()
                                Text(option.title)
                                    .font(.hkCallout.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                            }
                            if let count = count?(option.value), count > 0 {
                                Text(count.formatted())
                                    .font(.hkCallout)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink3)
                            }
                        }
                        ZStack {
                            Capsule().fill(.clear).frame(height: Theme.ruleWidth)
                            if selected {
                                Capsule().fill(Theme.ink).frame(height: Theme.ruleWidth)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

/// Centred empty state on the page itself: a quiet glyph, a serif title, one sentence of
/// help and at most one action. No card, no tinted circle.
struct EmptyState<Action: View>: View {
    var icon: HushIcon
    var title: String
    var message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Theme.s2) {
            Glyph(icon, size: Theme.iconXL)
                .foregroundStyle(Theme.ink3)
                .padding(.bottom, Theme.s1)
            Text(title)
                .font(.hkCardTitle)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Theme.noteWidth)
                .fixedSize(horizontal: false, vertical: true)
            action.padding(.top, Theme.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s6)
        .reveal()
    }
}

extension EmptyState where Action == EmptyView {
    init(icon: HushIcon, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

/// Multi-channel line plot of motion samples, drawn with Canvas so it keeps up at sensor rate.
struct SignalPlot: View {
    struct Channel {
        var name: String
        var color: Color
        var value: KeyPath<MotionSample, Double>
    }

    var title: String
    var samples: [MotionSample]
    var channels: [Channel]
    /// Visible time span; defaults to the extent of `samples`.
    var span: ClosedRange<TimeInterval>?
    var minScale: Double = 0.02
    var height: CGFloat = 90
    var showsHeader = true

    static let acceleration = [
        Channel(name: "x", color: Theme.signal, value: \.ax),
        Channel(name: "y", color: Theme.finishing, value: \.ay),
        Channel(name: "z", color: Theme.heroMist, value: \.az),
    ]
    static let rotation = [
        Channel(name: "x", color: Theme.signal, value: \.rx),
        Channel(name: "y", color: Theme.finishing, value: \.ry),
        Channel(name: "z", color: Theme.heroMist, value: \.rz),
    ]
    static let attitude = [
        Channel(name: "pitch", color: Theme.signal, value: \.pitch),
        Channel(name: "roll", color: Theme.finishing, value: \.roll),
        Channel(name: "yaw", color: Theme.heroMist, value: \.yaw),
    ]

    var body: some View {
        let range = span ?? ((samples.first?.t ?? 0)...(samples.last?.t ?? 1))
        let visible = samples.filter { range.contains($0.t) }
        let scale = max(minScale, channels.flatMap { c in visible.map { abs($0[keyPath: c.value]) } }.max() ?? 0)

        VStack(alignment: .leading, spacing: Theme.s1) {
            if showsHeader {
                HStack(spacing: Theme.s3) {
                    Text(title).font(.hkCaption.weight(.semibold))
                    ForEach(channels, id: \.name) { channel in
                        Label(channel.name, icon: .record)
                            .labelStyle(.titleAndIcon)
                            .font(.hkMeta)
                            .foregroundStyle(channel.color)
                    }
                    Spacer()
                    Text("±\(scale, specifier: "%.3f")")
                        .font(.hkMeta.monospacedDigit())
                        .foregroundStyle(Theme.ink2)
                }
            }
            Canvas { context, size in
                let mid = size.height / 2
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: mid))
                axis.addLine(to: CGPoint(x: size.width, y: mid))
                context.stroke(axis, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

                let width = max(range.upperBound - range.lowerBound, 1e-3)
                for channel in channels {
                    var path = Path()
                    for (i, s) in visible.enumerated() {
                        let point = CGPoint(
                            x: (s.t - range.lowerBound) / width * size.width,
                            y: mid - s[keyPath: channel.value] / scale * (mid - 2))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(channel.color), lineWidth: 1.2)
                }
            }
            .frame(height: height)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
        }
    }
}

struct LevelMeter: View {
    var value: Double
    var marker: Double?
    var tint: Color = Theme.signal

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(tint.gradient)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
                if let marker {
                    Rectangle().fill(.primary)
                        .frame(width: Theme.ruleWidth)
                        .offset(x: geo.size.width * min(max(marker, 0), 1) - Theme.ruleWidth / 2)
                }
            }
        }
        .frame(height: Theme.s2)
        .animation(.linear(duration: 0.08), value: value)
    }
}

/// Explicit hold control with a configurable app-local shortcut and an accessible action.
struct HoldToCaptureButton: View {
    var title: String
    var shortcut: String = "⌥⇧M"
    var isCapturing: Bool
    var isEnabled = true
    var onBegin: () -> Void
    var onEnd: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: Theme.figureGap) {
            Glyph(.record)
                .hushIconSize(Theme.iconXL)
                .symbolEffect(.pulse, isActive: isCapturing)
            Text(isCapturing ? "Capturing…" : title)
                .font(.hkHeadline)
            Text("Hold \(shortcut) or press and hold here")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.optionCardHeight)
        .surface(isCapturing ? .selected : .wellOutlined)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : Theme.disabledOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isCapturing ? "Stop capture" : title)
        .accessibilityValue(isCapturing ? "Capturing" : isEnabled ? "Ready" : "Unavailable")
        .accessibilityHint("Press and hold to capture, or hold \(shortcut). Releasing ends the capture.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            guard isEnabled else { return }
            if isCapturing { onEnd() } else { onBegin() }
        }
        .help("Hold \(shortcut) or press and hold here to capture")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !pressed else { return }
                    pressed = true
                    onBegin()
                }
                .onEnded { _ in
                    guard pressed else { return }
                    pressed = false
                    onEnd()
                })
    }
}

struct MotionStatusBadge: View {
    var status: HeadphoneMotionService.Status
    var rate: Double

    var body: some View {
        Label {
            Text(status == .streaming ? "Motion · \(Int(rate.rounded())) Hz" : status.label)
                .font(.hkCallout.monospacedDigit())
        } icon: {
            SymbolGlyph(symbol, size: Theme.iconM)
                .foregroundStyle(color)
        }
        .help("Processed headphone-motion status")
    }

    private var symbol: String {
        switch status {
        case .streaming: "waveform.path"
        case .waiting: "headphones"
        case .denied: "hand.raised.slash"
        case .unsupported: "headphones.slash"
        case .error: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch status {
        case .streaming: Theme.success
        case .waiting: Theme.finishing
        default: Theme.danger
        }
    }
}

// MARK: - Silent Lab

/// The four lab steps as one clickable progress strip, shown on every lab page. Wispr has no
/// equivalent; it keeps the AirPods study legible as a single path rather than four screens.
struct LabProgress: View {
    @Environment(AppModel.self) private var model

    private struct Step: Identifiable {
        var screen: AppModel.Screen
        var title: String
        var done: Bool
        var id: String { title }
    }

    private var steps: [Step] {
        let connected = model.motion.status == .streaming
        let trained = model.meetsTemplateProtocol(condition: .silent)
        let passed = model.isMotionInferenceEnabled
        return [
            Step(screen: .setup, title: "Connect", done: connected),
            Step(screen: .train, title: "Train", done: trained),
            Step(screen: .evaluate, title: "Evaluate", done: passed),
            Step(screen: .use, title: "Silent Use", done: passed && model.screen == .use),
        ]
    }

    var body: some View {
        HStack(spacing: Theme.s2) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                let current = model.screen == step.screen
                Button {
                    model.screen = step.screen
                } label: {
                    HStack(spacing: Theme.s2) {
                        ZStack {
                            Circle()
                                .fill(step.done ? Theme.signal : current ? Theme.ink : Theme.well)
                            if step.done {
                                Glyph(.check)
                                    .hushIconSize(Theme.iconXS)
                                    .foregroundStyle(Theme.inverseInk)
                            } else {
                                Text("\(index + 1)")
                                    .font(.hkBadge.monospacedDigit())
                                    .foregroundStyle(current ? Theme.inverseInk : Theme.ink2)
                            }
                        }
                        .frame(width: Theme.iconColumn, height: Theme.iconColumn)
                        Text(step.title)
                            .font(.hkSubhead.weight(current ? .semibold : .regular))
                            .foregroundStyle(current ? Theme.ink : Theme.ink2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.fieldHeight)
                    .background(current ? Theme.sheet : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(current ? Theme.hairline : .clear, lineWidth: Theme.hairlineWidth))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(step.done ? Theme.signalEdge : Theme.hairline)
                        .frame(height: Theme.hairlineWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.s1)
        .background(Theme.well, in: Capsule())
        .animation(Theme.snappy, value: model.screen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Silent Lab progress")
    }
}

/// Live check that only the jaw moves. AirPods sense the whole head, so a nod looks like a word unless
/// the head stays still; takes and captures where it moved are refused.
struct HeadStillnessIndicator: View {
    var isMoving: Bool

    var body: some View {
        Label(isMoving ? "Head moving · keep still, move only your jaw" : "Head still",
              icon: isMoving ? .warning : .checkCircle)
            .font(.hkCaption)
            .foregroundStyle(isMoving ? Theme.finishing : Theme.ink3)
            .contentTransition(.symbolEffect(.replace))
            .animation(Theme.snappy, value: isMoving)
    }
}

/// Large lab hero: status glyph, title, one line, actions, and optional metrics on the right.
struct LabHero<Actions: View, Metrics: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var message: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var metrics: Metrics

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s5) {
            // The status glyph on its own, in its state colour: no tile behind it.
            SymbolGlyph(symbol, size: Theme.iconXL)
                .foregroundStyle(tint)
                .hushIconActive(true)
                .frame(width: Theme.controlHeight)
            VStack(alignment: .leading, spacing: Theme.titleGap) {
                Text(title).font(.hkDisplayBand).tracking(-0.2)
                Text(message)
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.controlGap) { actions }
                    .padding(.top, Theme.s2)
            }
            Spacer(minLength: Theme.s4)
            metrics
        }
        .card(padding: Theme.cardPaddingL, style: .outlined)
    }
}

/// Big number with a small label, for hero metrics.
struct HeroMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.s0) {
            Text(value)
                .font(.hkSheetTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: Sheets

/// Modal sheet frame shared by the editors: display title, one-line subtitle, close button,
/// content, then a footer with an optional note, Cancel and the primary action.
struct EditorSheet<Content: View>: View {
    var title: String
    var subtitle: String?
    var note: String?
    var primaryTitle: String
    var canSave = true
    var width: CGFloat = Theme.sheetWidth
    var onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text(title).font(.hkSheetTitle)
                    if let subtitle {
                        Text(subtitle).font(.hkCaption).foregroundStyle(Theme.ink2)
                    }
                }
                Spacer()
                Button("Close", icon: .close) { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
            }
            VStack(alignment: .leading, spacing: Theme.s4) { content }
            HStack(spacing: Theme.controlGap) {
                if let note {
                    Text(note).font(.hkCaption).foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: Theme.s4)
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: onSave)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.cardPaddingL)
        .frame(width: width)
        .background(Theme.sheet)
    }
}

/// A labelled field on `well` with a hairline border, matching the Languages search field.
/// `multiline` grows a vertical text field up to `lineLimit` lines instead of one line.
struct SheetField: View {
    var label: String
    var prompt: String
    @Binding var text: String
    var hint: String?
    var multiline = false
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text(label).font(.hkRowTitle)
            Group {
                if multiline {
                    TextField(prompt, text: $text, axis: .vertical)
                        .lineLimit(5...10)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.hkBody)
            .focused($focused)
            .accessibilityLabel(label)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
            .frame(minHeight: Theme.controlHeight)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(focused ? Theme.signal : Theme.hairline,
                              lineWidth: focused ? Theme.selectedStroke : Theme.hairlineWidth))
            .animation(Theme.snappy, value: focused)
            if let hint {
                Text(hint)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if autofocus { focused = true } }
    }
}

/// Inline validation message under a sheet's fields.
struct SheetNotice: View {
    var message: String

    var body: some View {
        Label(message, icon: .warning)
            .font(.hkCallout)
            .foregroundStyle(Theme.danger)
            .transition(.opacity)
    }
}

extension View {
    /// Inline `TextEditor` field: no stock text-view background, `sheet` fill and a hairline
    /// border at the control radius, so it reads the same in light and dark mode.
    func editorField() -> some View {
        scrollContentBackground(.hidden)
            .padding(Theme.s2)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
    }
}

/// The one inline search field: glyph, plain text field and an optional close button on a
/// `sheet` fill with a hairline, `fieldHeight` tall so it sits level with icon buttons.
struct SearchField: View {
    var prompt: String
    @Binding var text: String
    /// Text width; nil fills the available width.
    var width: CGFloat? = Theme.searchWidth
    var accessibilityLabel: String? = nil
    /// Shown as a trailing ×, and run on Esc.
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.iconGap) {
            Glyph(.search).foregroundStyle(Theme.ink3)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .frame(width: width)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .accessibilityLabel(accessibilityLabel ?? prompt)
                .onExitCommand { onClose?() }
            if let onClose {
                Button("Close search", icon: .close, action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .font(.hkCallout)
        .padding(.horizontal, Theme.s3)
        .frame(height: Theme.fieldHeight)
        .surface(.outlined, radius: Theme.controlRadius)
    }
}
