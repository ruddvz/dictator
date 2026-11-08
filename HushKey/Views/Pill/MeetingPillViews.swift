import SwiftUI

/// The meeting's input level for the pill's ribbon. Only this view reads the level, so the
/// rest of the pill doesn't redraw with every audio buffer.
struct MeetingLevel<Content: View>: View {
    let meeting: MeetingNotesService
    @ViewBuilder var content: (Float) -> Content

    var body: some View { content(meeting.activeAudioLevel) }
}

/// The meeting's running clock on the pill: "0:07", "12:03", "1:02:03".
struct MeetingClock: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(MeetingDigest.clock(context.date.timeIntervalSince(startedAt ?? context.date)))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
        .accessibilityHidden(true)
    }
}

/// After a meeting stops: what was said, what to do next, and the note one click away.
/// Sits above the pill like the transcript card and stays until it is closed, opened or
/// replaced, because the note is the point of the meeting.
struct MeetingResultCard: View {
    let note: MeetingNote
    let isDigesting: Bool
    /// The summary was picked from the transcript, without a language model.
    let isFallback: Bool
    var onOpen: () -> Void
    var onCopy: () -> Bool
    var onExport: () -> Void
    var onClose: () -> Void
    @Binding var isHovering: Bool

    @State private var copied = false
    @State private var copyToken = 0
    private static let shownActionItems = 3

    private var items: [String] { MeetingDigest.actionItems(from: note.actionItems) }
    private var tooShort: Bool { !isDigesting && note.summary.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            header
            Text(note.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            summary
            if !isDigesting, !items.isEmpty { actionItems }
            footer
        }
        .padding(Theme.s4)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .onHover { isHovering = $0 }
        .animation(Theme.snappy, value: isDigesting)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting saved")
    }

    private var header: some View {
        HStack(spacing: Theme.s2) {
            MorphIcon(phase: .done, lineWidth: 1.6)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.signal)
            Text("Meeting saved")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            Text("· \(MeetingDigest.lengthLabel(note.duration))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: Theme.s2)
            CountdownCloseButton(duration: nil, size: 22, help: "Close (Esc)", action: onClose)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if isDigesting {
            HStack(spacing: Theme.s2) {
                // The same working ribbon as the pill while it transcribes.
                BreathRibbon(level: 0, mode: .working, tint: Theme.signal)
                    .frame(width: 34, height: 12)
                Text("Writing the summary on this Mac…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.vertical, 2)
            .transition(.opacity)
        } else if tooShort {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Too short to summarize. The transcript is saved.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            }
            .transition(.opacity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                Text(Self.display(note.summary))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 112)
            .transition(.opacity)
        }
    }

    private var actionItems: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Action items")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ink2)
            ForEach(Array(items.prefix(Self.shownActionItems).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                    Circle()
                        .strokeBorder(Theme.signal, lineWidth: 1.2)
                        .frame(width: 9, height: 9)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(Self.display(item))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if items.count > Self.shownActionItems {
                Text("+\(items.count - Self.shownActionItems) more in the note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                    .padding(.leading, 17)
            }
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous).fill(Theme.well))
        .transition(.opacity)
    }

    private var footer: some View {
        HStack(spacing: Theme.s2) {
            if isFallback, !isDigesting, !tooShort {
                Text("Picked from the transcript")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
                    .help("Apple Intelligence isn't available, so these lines come straight from what was said.")
            }
            Spacer(minLength: 0)
            Button {
                guard onCopy() else { return }
                copied = true
                copyToken += 1
                let token = copyToken
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    if token == copyToken { copied = false }
                }
            } label: {
                Text(copied ? "Copied" : "Copy").frame(minWidth: 40)
            }
            .buttonStyle(CardOutlineButtonStyle())
            .help("Copy summary, action items and transcript as Markdown")
            Button("Export…", action: onExport)
                .buttonStyle(CardOutlineButtonStyle())
                .help("Save as a Markdown file")
            Button("Open", action: onOpen)
                .buttonStyle(CardOutlineButtonStyle(prominent: true))
                .help("Open this note in HushKey")
        }
    }

    /// Model output can carry Markdown headings and bold; show it as plain, readable lines.
    static func display(_ text: String) -> AttributedString {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { line -> String in
                var line = line
                while line.hasPrefix("#") { line.removeFirst() }
                if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
                return line.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return (try? AttributedString(markdown: lines, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(lines)
    }
}

/// A one-line problem beside the pill: a meeting that couldn't start, or one where nothing was
/// heard. It closes itself; Open goes to Meeting notes, where the fix is.
struct MeetingNoticeCard: View {
    let message: String
    var onOpen: () -> Void
    var onClose: () -> Void
    @Binding var isHovering: Bool

    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.signal)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.s2)
            Button("Open", action: onOpen)
                .buttonStyle(CardOutlineButtonStyle())
            CountdownCloseButton(duration: 10, paused: isHovering, size: 22, help: "Dismiss", action: onClose)
                .id(message)
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2 + 2)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// Compact actions on the pill's cards: filled sage for the one main action, outlined otherwise.
struct CardOutlineButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Theme.paper : Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? Theme.signal.opacity(hovering ? 0.88 : 1)
                                       : Theme.ink.opacity(hovering ? 0.12 : 0.06)))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(prominent ? 0 : 0.18), lineWidth: 0.5))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
