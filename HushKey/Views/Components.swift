import SwiftUI

struct PageHeader<Actions: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: 6) {
                // Only lab steps carry a visible eyebrow; elsewhere the sidebar already says where you are.
                if eyebrow.hasPrefix("Step") {
                    SectionLabel(title: eyebrow)
                }
                Text(title)
                    .font(.hkTitle1)
                    .tracking(-0.3)
                    .accessibilityIdentifier("page.header")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                        .frame(maxWidth: 560, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.s4)
            HStack(spacing: Theme.s2) { actions }
        }
        .padding(.bottom, Theme.s2)
    }
}

extension PageHeader where Actions == EmptyView {
    init(eyebrow: String, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// The one page layout: a centered 800 pt column, 48 pt from the top of the sheet.
    func pageLayout() -> some View {
        frame(maxWidth: Theme.pageWidth, alignment: .leading)
            .padding(.horizontal, Theme.s7 - 8)
            .padding(.top, Theme.s7)
            .padding(.bottom, Theme.s6)
            .frame(maxWidth: .infinity, alignment: .top)
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
        .card(padding: Theme.s5 - 4)
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
        VStack(alignment: .leading, spacing: Theme.s2 + 2) {
            if let title {
                Text(title)
                    .font(.hkTitle3)
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -1)
                .padding(.horizontal, Theme.s5 - 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hairline that separates rows inside a `SettingsGroup` or `ListGroup`.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
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
            VStack(alignment: .leading, spacing: 3) {
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
            Spacer(minLength: Theme.s4)
            control
        }
        .padding(.vertical, 18)
        .frame(minHeight: 64)
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
        VStack(alignment: .leading, spacing: Theme.s3) { content }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { RowDivider() }
    }
}

/// Outlined list on the sheet (Wispr's history and dictionary lists): 52 pt rows split by hairlines.
struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.top, -1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
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
            HStack(spacing: 2) { actions }
                .opacity(hovering ? 1 : 0)
                .offset(x: hovering ? 0 : 6)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s3)
        .frame(minHeight: Theme.listRow)
        .background(hovering ? Theme.well.opacity(0.7) : .clear)
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
            HStack(spacing: Theme.s2) {
                Text(options.first(where: { $0.value == selection })?.title ?? "Choose")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.s3 + 2)
            .frame(width: width, height: Theme.controlHeight)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(hovering ? Theme.ink3.opacity(0.6) : Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
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
                        Text(option.title)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                        ZStack {
                            Capsule().fill(.clear).frame(height: 2)
                            if selected {
                                Capsule().fill(Theme.ink).frame(height: 2)
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

/// Centered empty state: a soft glyph, one line of title, one line of help.
struct EmptyState<Action: View>: View {
    var systemImage: String
    var title: String
    var message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Theme.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.signal)
                .frame(width: 48, height: 48)
                .background(Theme.signalSoft, in: Circle())
                .padding(.bottom, Theme.s1)
            Text(title).font(.hkHeadline)
            Text(message)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            action.padding(.top, Theme.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s6 + 8)
    }
}

extension EmptyState where Action == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
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
        Channel(name: "x", color: .red, value: \.ax),
        Channel(name: "y", color: .green, value: \.ay),
        Channel(name: "z", color: .blue, value: \.az),
    ]
    static let rotation = [
        Channel(name: "x", color: .red, value: \.rx),
        Channel(name: "y", color: .green, value: \.ry),
        Channel(name: "z", color: .blue, value: \.rz),
    ]
    static let attitude = [
        Channel(name: "pitch", color: .orange, value: \.pitch),
        Channel(name: "roll", color: .purple, value: \.roll),
        Channel(name: "yaw", color: .teal, value: \.yaw),
    ]

    var body: some View {
        let range = span ?? ((samples.first?.t ?? 0)...(samples.last?.t ?? 1))
        let visible = samples.filter { range.contains($0.t) }
        let scale = max(minScale, channels.flatMap { c in visible.map { abs($0[keyPath: c.value]) } }.max() ?? 0)

        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                HStack(spacing: 10) {
                    Text(title).font(.hkCaption.weight(.semibold))
                    ForEach(channels, id: \.name) { channel in
                        Label(channel.name, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.hkMeta)
                            .foregroundStyle(channel.color)
                    }
                    Spacer()
                    Text("±\(scale, specifier: "%.3f")")
                        .font(.hkMeta.monospacedDigit())
                        .foregroundStyle(.secondary)
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
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct LevelMeter: View {
    var value: Double
    var marker: Double?
    var tint: Color = .green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
                if let marker {
                    Rectangle().fill(.primary)
                        .frame(width: 2)
                        .offset(x: geo.size.width * min(max(marker, 0), 1) - 1)
                }
            }
        }
        .frame(height: 8)
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
        VStack(spacing: 6) {
            Image(systemName: isCapturing ? "record.circle.fill" : "hand.tap")
                .font(.system(size: 30, weight: .medium))
                .symbolEffect(.pulse, isActive: isCapturing)
            Text(isCapturing ? "Capturing…" : title)
                .font(.hkHeadline)
            Text("Hold \(shortcut) or press and hold here")
                .font(.hkCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isCapturing ? Theme.signalSoft : Theme.ink.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isCapturing ? Theme.signal : Theme.hairline, lineWidth: isCapturing ? 2 : 1))
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.4)
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
            Image(systemName: symbol)
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
        case .streaming: .green
        case .waiting: .orange
        default: .red
        }
    }
}
