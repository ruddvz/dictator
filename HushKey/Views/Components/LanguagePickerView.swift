import SwiftUI

/// Shows the current language and opens the grid to change it.
struct LanguageButton: View {
    @Binding var selection: String
    @State private var choosing = false
    @State private var hovering = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            MenuPickerLabel(title: DictationLanguage.named(selection).name, icon: .globe, width: nil, hovering: hovering)
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityHint("Opens the language list")
        .sheet(isPresented: $choosing) {
            LanguagePickerSheet(selection: $selection)
        }
    }
}

/// The dictation language as a searchable grid, each language shown in your language and its own.
/// One language at a time: on-device recognition has no auto-detect.
struct LanguagePickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var choice: String
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.s2), count: 3)

    init(selection: Binding<String>) {
        _selection = selection
        _choice = State(initialValue: selection.wrappedValue)
    }

    private var results: [DictationLanguage] {
        DictationLanguage.onDevice.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    Text("Language").font(.display(26))
                    Text("Recognized on this Mac. One language at a time.")
                        .font(.hkCaption).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button("Close", icon: .close) { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            searchField
            selectedRow
            // Short result lists size the sheet to fit; long ones scroll inside 300 pt.
            ViewThatFits(in: .vertical) {
                languageGrid
                ScrollView { languageGrid }
            }
            .frame(maxHeight: 300, alignment: .top)
            HStack {
                Text("Missing a language? Add it in System Settings › Keyboard › Dictation.")
                    .font(.hkCaption).foregroundStyle(Theme.ink3)
                Spacer()
                Button("Save and close") {
                    selection = choice
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.s5)
        .frame(width: 620)
        .background(Theme.sheet)
        .onAppear { searchFocused = true }
    }

    private var languageGrid: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.s2) {
                ForEach(results) { language in
                    LanguageTile(language: language, isSelected: language.identifier == choice) {
                        choice = language.identifier
                    }
                }
            }
            .padding(1)
            if results.isEmpty {
                Text("No on-device language matches “\(query)”.")
                    .font(.hkCallout).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.s6)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.s2) {
            Glyph(.search).foregroundStyle(Theme.ink3)
            TextField("Search languages", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search languages")
            if !query.isEmpty {
                Button("Clear search", icon: .close) { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .font(.hkCallout)
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var selectedRow: some View {
        let language = DictationLanguage.named(choice)
        return HStack(spacing: Theme.s2) {
            Text("SELECTED").font(.hkMeta.weight(.medium)).tracking(0.8).foregroundStyle(Theme.ink2)
            Label(language.name, icon: .check)
                .font(.hkCaption.weight(.medium))
                .foregroundStyle(Theme.signal)
                .padding(.horizontal, Theme.s2)
                .padding(.vertical, Theme.s1)
                .background(Capsule().fill(Theme.signalSoft))
            if choice != selection {
                Text("was \(DictationLanguage.named(selection).name)")
                    .font(.hkCaption).foregroundStyle(Theme.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LanguageTile: View {
    var language: DictationLanguage
    var isSelected: Bool
    var select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.languageName)
                        .font(.hkCallout.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if !language.detail.isEmpty {
                        Text(language.detail)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Glyph(.check).foregroundStyle(Theme.signal)
                }
            }
            .padding(.horizontal, Theme.s3)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                .fill(isSelected ? Theme.signalSoft : hovering ? Theme.hover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous)
                .strokeBorder(isSelected ? Theme.signal : Theme.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(language.nativeName) (\(language.identifier))")
        .accessibilityLabel(language.nativeName == language.name ? language.name : "\(language.name), \(language.nativeName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
