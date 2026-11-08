import SwiftUI

private enum PersonalizationSection: String, CaseIterable, Identifiable {
    case vocabulary = "Vocabulary"
    case snippets = "Snippets"
    case corrections = "Corrections"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .snippets: "text.quote"
        case .vocabulary: "character.book.closed"
        case .corrections: "arrow.left.arrow.right"
        }
    }

    var addTitle: String {
        switch self {
        case .vocabulary: "Add word"
        case .snippets: "Add snippet"
        case .corrections: "Add correction"
        }
    }
}

private struct SnippetEntry: Identifiable, Equatable {
    var cue: String
    var expansion: String
    var id: String { cue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

private struct PersonalizationEditorRequest: Identifiable {
    var id = UUID()
    var section: PersonalizationSection
    var snippet: SnippetEntry?
    var term: String?
}

struct PersonalizationView: View {
    @Environment(AppModel.self) private var model
    @State private var section: PersonalizationSection = .vocabulary
    @State private var searching = false
    @State private var query = ""
    @State private var editor: PersonalizationEditorRequest?
    @State private var notice: String?
    @State private var wordListMessage: String?

    private var snippets: [SnippetEntry] {
        model.dictationSnippets
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let parts = rawLine.components(separatedBy: "=>")
                guard parts.count >= 2 else { return nil }
                let cue = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let expansion = parts.dropFirst().joined(separator: "=>")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cue.isEmpty, !expansion.isEmpty else { return nil }
                return SnippetEntry(cue: cue, expansion: expansion)
            }
            .sorted { $0.cue.localizedStandardCompare($1.cue) == .orderedAscending }
    }

    private var vocabulary: [String] {
        DictationVocabulary.terms(from: model.dictationTerms)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var corrections: [SnippetEntry] {
        model.dictationCorrectionRules
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let parts = rawLine.components(separatedBy: "=>")
                guard parts.count >= 2 else { return nil }
                let cue = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = parts.dropFirst().joined(separator: "=>")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cue.isEmpty, !replacement.isEmpty else { return nil }
                return SnippetEntry(cue: cue, expansion: replacement)
            }
            .sorted { $0.cue.localizedStandardCompare($1.cue) == .orderedAscending }
    }

    private var filteredSnippets: [SnippetEntry] {
        guard !query.isEmpty else { return snippets }
        return snippets.filter { $0.cue.localizedCaseInsensitiveContains(query) || $0.expansion.localizedCaseInsensitiveContains(query) }
    }

    private var filteredVocabulary: [String] {
        guard !query.isEmpty else { return vocabulary }
        return vocabulary.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var filteredCorrections: [SnippetEntry] {
        guard !query.isEmpty else { return corrections }
        return corrections.filter {
            $0.cue.localizedCaseInsensitiveContains(query) || $0.expansion.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Vocabulary", subtitle: "") {
                    if section == .vocabulary {
                        Button("Import…", icon: .download) {
                            wordListMessage = model.importVocabularyWordList()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Add words from a text or CSV file, one per line or separated by commas")
                        Button("Export…", icon: .share) {
                            wordListMessage = model.exportVocabularyWordList()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(vocabulary.isEmpty)
                        .help("Save your vocabulary as a text file, one word per line")
                    }
                    Button(section.addTitle, icon: .plus) {
                        editor = PersonalizationEditorRequest(section: section, snippet: nil, term: nil)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                HStack(alignment: .bottom, spacing: Theme.s3) {
                    UnderlineTabs(selection: $section,
                                  options: PersonalizationSection.allCases.map { ($0, $0.rawValue) },
                                  count: { count(for: $0) })
                    .onChange(of: section) { _, _ in query = "" }
                }
                .overlay(alignment: .topTrailing) { searchControl }

                hero

                Group {
                    switch section {
                    case .snippets: snippetList
                    case .vocabulary: vocabularyList
                    case .corrections: correctionList
                    }
                }
                .animation(Theme.gentle, value: section)

                switch section {
                case .snippets: advancedSnippetEditor
                case .corrections: advancedCorrectionEditor
                case .vocabulary: EmptyView()
                }
            }
            .pageLayout()
        }
        .sheet(item: $editor) { request in
            PersonalizationEntryEditor(
                section: request.section,
                initialSnippet: request.snippet,
                initialTerm: request.term,
                onSave: { primary, secondary in
                    save(primary: primary, secondary: secondary, request: request)
                })
        }
        .alert("Couldn’t save that entry", isPresented: Binding(
            get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "Please try again.")
        }
        .alert("Word list", isPresented: Binding(
            get: { wordListMessage != nil }, set: { if !$0 { wordListMessage = nil } })) {
            Button("OK", role: .cancel) { wordListMessage = nil }
        } message: {
            Text(wordListMessage ?? "")
        }
    }

    private func count(for section: PersonalizationSection) -> Int {
        switch section {
        case .snippets: snippets.count
        case .vocabulary: vocabulary.count
        case .corrections: corrections.count
        }
    }

    private var searchControl: some View {
        HStack(spacing: Theme.s2) {
            if searching || !query.isEmpty {
                TextField("Search \(section.rawValue.lowercased())", text: $query)
                    .textFieldStyle(.plain)
                    .font(.hkCallout)
                    .frame(width: 180)
                    .accessibilityLabel("Search \(section.rawValue.lowercased())")
                    .onExitCommand { query = ""; searching = false }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            Button(searching ? "Close search" : "Search", icon: searching ? .close : .search) {
                withAnimation(Theme.snappy) {
                    if searching { query = "" }
                    searching.toggle()
                }
            }
            .buttonStyle(IconButtonStyle())
            .help(searching ? "Close search" : "Search")
        }
    }

    /// One-time explanation in Wispr's banner position, with live examples from your own list.
    private var hero: some View {
        let examples: [String] = switch section {
        case .vocabulary: Array(vocabulary.prefix(5))
        case .snippets: snippets.prefix(3).map(\.cue)
        case .corrections: corrections.prefix(3).map { "\($0.cue) → \($0.expansion)" }
        }
        let title = switch section {
        case .vocabulary: "HushKey spells the way you do."
        case .snippets: "Say a cue, get the whole thing."
        case .corrections: "Fix a mishearing once."
        }
        let detail = switch section {
        case .vocabulary: "Names, product terms and jargon are passed to on-device recognition, so they come out right."
        case .snippets: "Your email, a sign-off or a long prompt, dropped in when you say its cue."
        case .corrections: "When HushKey keeps hearing a phrase wrong, replace it with the one you meant."
        }
        return VStack(alignment: .leading, spacing: Theme.s3) {
            Text(title)
                .font(.hkTitle2)
                .tracking(-0.3)
            Text(detail)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !examples.isEmpty {
                HStack(spacing: Theme.s2) {
                    ForEach(examples, id: \.self) { example in
                        Text(example)
                            .font(.hkControl)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.s3)
                            .frame(height: Theme.controlHeight)
                            .background(Theme.sheet.opacity(0.7),
                                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }
                .padding(.top, Theme.s1)
            }
        }
        .padding(Theme.s6 - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
        .lineLimit(1)
    }

    @ViewBuilder
    private var snippetList: some View {
        if filteredSnippets.isEmpty {
            listEmpty(query.isEmpty ? "No snippets yet" : "No matching snippets",
                      query.isEmpty ? "Add a short cue and the text it should become." : "Try another cue or phrase.")
        } else {
            ListGroup {
                ForEach(filteredSnippets) { entry in
                    ListRow {
                        HStack(spacing: Theme.s2) {
                            Text(entry.cue).font(.hkBody.weight(.medium))
                            Glyph(.arrowRight).hushIconSize(15).foregroundStyle(Theme.ink3)
                            Text(entry.expansion).font(.hkBody).foregroundStyle(Theme.ink2).lineLimit(1)
                        }
                    } actions: {
                        rowAction("Edit \(entry.cue)", "pencil") {
                            editor = PersonalizationEditorRequest(section: .snippets, snippet: entry, term: nil)
                        }
                        rowAction("Delete \(entry.cue)", "trash") { removeSnippet(entry.cue) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var vocabularyList: some View {
        if filteredVocabulary.isEmpty {
            listEmpty(query.isEmpty ? "No words yet" : "No matching words",
                      query.isEmpty ? "Add names, product terms or jargon." : "Try another search.")
        } else {
            ListGroup {
                ForEach(filteredVocabulary, id: \.self) { term in
                    ListRow {
                        Text(term).font(.hkBody)
                    } actions: {
                        rowAction("Edit \(term)", "pencil") {
                            editor = PersonalizationEditorRequest(section: .vocabulary, snippet: nil, term: term)
                        }
                        rowAction("Delete \(term)", "trash") { removeTerm(term) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var correctionList: some View {
        if filteredCorrections.isEmpty {
            listEmpty(query.isEmpty ? "No corrections yet" : "No matching corrections",
                      query.isEmpty ? "Add what HushKey hears and what you meant." : "Try another phrase.")
        } else {
            ListGroup {
                ForEach(filteredCorrections) { rule in
                    ListRow {
                        HStack(spacing: Theme.s2) {
                            Text(rule.cue).font(.hkBody).foregroundStyle(Theme.ink2).strikethrough(color: Theme.ink3)
                            Glyph(.arrowRight).hushIconSize(15).foregroundStyle(Theme.ink3)
                            Text(rule.expansion).font(.hkBody.weight(.medium)).lineLimit(1)
                        }
                    } actions: {
                        rowAction("Edit correction for \(rule.cue)", "pencil") {
                            editor = PersonalizationEditorRequest(section: .corrections, snippet: rule, term: nil)
                        }
                        rowAction("Delete correction for \(rule.cue)", "trash") { removeCorrection(rule.cue) }
                    }
                }
            }
        }
    }

    private func listEmpty(_ title: String, _ message: String) -> some View {
        EmptyState(icon: query.isEmpty ? HushIcon(symbol: section.symbol) ?? .vocabulary : .search, title: title, message: message)
            .card(padding: 0, style: .outlined)
    }

    private func rowAction(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(title, icon: HushIcon(symbol: symbol) ?? .more, action: perform)
            .buttonStyle(IconButtonStyle())
            .help(title)
    }

    private var advancedSnippetEditor: some View {
        @Bindable var model = model
        return DisclosureGroup("Edit as text") {
            TextEditor(text: $model.dictationSnippets)
                .font(.hkBody.monospaced())
                .frame(minHeight: 90)
                .editorField()
                .padding(.top, Theme.s2)
            Text("One per line: spoken cue => expanded phrase. Use this editor to repair malformed older entries.")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
            let validation = DictationSnippetExpander.validation(for: model.dictationSnippets)
            Label(validation.invalidLines.isEmpty
                  ? "\(validation.validCount) ready"
                  : "\(validation.validCount) ready · check line\(validation.invalidLines.count == 1 ? "" : "s") \(validation.invalidLines.map(String.init).joined(separator: ", "))",
                  icon: validation.invalidLines.isEmpty ? .checkCircle : .warning)
                .font(.hkCaption)
                .foregroundStyle(validation.invalidLines.isEmpty ? Theme.ink2 : Theme.danger)
        }
        .font(.hkCallout)
        .tint(Theme.ink2)
        .padding(Theme.s4)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
    }

    private var advancedCorrectionEditor: some View {
        @Bindable var model = model
        return DisclosureGroup("Edit as text") {
            TextEditor(text: $model.dictationCorrectionRules)
                .font(.hkBody.monospaced())
                .frame(minHeight: 90)
                .editorField()
                .padding(.top, Theme.s2)
            Text("One per line: recognized phrase => corrected phrase. Matches are case-insensitive and respect whole-word boundaries. Raw recognition remains available to restore.")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
            let validation = DictationCorrectionRules.validation(for: model.dictationCorrectionRules)
            Label(validation.invalidLines.isEmpty
                  ? "\(validation.validCount) ready"
                  : "\(validation.validCount) ready · check line\(validation.invalidLines.count == 1 ? "" : "s") \(validation.invalidLines.map(String.init).joined(separator: ", "))",
                  icon: validation.invalidLines.isEmpty ? .checkCircle : .warning)
                .font(.hkCaption)
                .foregroundStyle(validation.invalidLines.isEmpty ? Theme.ink2 : Theme.finishing)
        }
        .font(.hkCallout)
        .tint(Theme.ink2)
        .padding(Theme.s4)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
    }

    private func save(primary: String, secondary: String?, request: PersonalizationEditorRequest) -> String? {
        if request.section == .vocabulary {
            let term = primary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !term.contains(","), !term.contains(where: \.isNewline) else {
                return "Enter one word or phrase without commas or line breaks."
            }
            let original = request.term
            let existing = vocabulary.first {
                $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                    $0.compare(original ?? "", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
            }
            guard existing == nil else { return "That word is already in your vocabulary." }
            var terms = DictationVocabulary.terms(from: model.dictationTerms)
            if let original {
                terms.removeAll { $0.compare(original, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }
            terms.append(term)
            model.dictationTerms = DictationVocabulary.encode(terms)
            return nil
        }

        let cue = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let expansion = (secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = "\(cue) => \(expansion)"
        let isCorrection = request.section == .corrections
        let validation = isCorrection
            ? DictationCorrectionRules.validation(for: candidate)
            : DictationSnippetExpander.validation(for: candidate)
        guard validation.validCount == 1, validation.invalidLines.isEmpty else {
            return isCorrection
                ? "Enter a recognized phrase and its correction on one line."
                : "Enter a cue and its expanded phrase on one line."
        }
        let existingEntries = isCorrection ? corrections : snippets
        let duplicate = existingEntries.contains {
            $0.cue.compare(cue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                $0.cue.compare(request.snippet?.cue ?? "", options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        guard !duplicate else {
            return isCorrection ? "A correction for that phrase already exists." : "A snippet with that cue already exists."
        }

        let currentDefinitions = isCorrection ? model.dictationCorrectionRules : model.dictationSnippets
        var lines = currentDefinitions.components(separatedBy: .newlines)
        if let oldCue = request.snippet?.cue {
            lines.removeAll { line in
                let parts = line.components(separatedBy: "=>")
                return parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(oldCue, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
        lines.append(candidate)
        let updated = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        if isCorrection { model.dictationCorrectionRules = updated }
        else { model.dictationSnippets = updated }
        return nil
    }

    private func removeSnippet(_ cue: String) {
        let lines = model.dictationSnippets.components(separatedBy: .newlines).filter { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count >= 2 else { return true }
            return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(cue, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        model.dictationSnippets = lines.joined(separator: "\n")
    }

    private func removeTerm(_ term: String) {
        model.dictationTerms = DictationVocabulary.encode(
            DictationVocabulary.terms(from: model.dictationTerms).filter {
                $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
            })
    }

    private func removeCorrection(_ cue: String) {
        let lines = model.dictationCorrectionRules.components(separatedBy: .newlines).filter { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count >= 2 else { return true }
            return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(cue, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        model.dictationCorrectionRules = lines.joined(separator: "\n")
    }
}

private struct PersonalizationEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let section: PersonalizationSection
    let initialSnippet: SnippetEntry?
    let initialTerm: String?
    let onSave: (String, String?) -> String?

    @State private var cue: String
    @State private var expansion: String
    @State private var term: String
    @State private var validationMessage: String?

    init(section: PersonalizationSection, initialSnippet: SnippetEntry?, initialTerm: String?,
         onSave: @escaping (String, String?) -> String?) {
        self.section = section
        self.initialSnippet = initialSnippet
        self.initialTerm = initialTerm
        self.onSave = onSave
        _cue = State(initialValue: initialSnippet?.cue ?? "")
        _expansion = State(initialValue: initialSnippet?.expansion ?? "")
        _term = State(initialValue: initialTerm ?? "")
    }

    var body: some View {
        EditorSheet(title: editorTitle, subtitle: editorSubtitle,
                    note: section == .vocabulary ? "Stays on this Mac." : nil,
                    primaryTitle: "Save", canSave: canSave, width: 480, onSave: save) {
            if section == .vocabulary {
                SheetField(label: "Word or phrase", prompt: "For example: HushKey", text: $term,
                           hint: "Used as an on-device recognition hint.", autofocus: true)
            } else {
                SheetField(label: section == .corrections ? "Recognized phrase" : "Spoken cue",
                           prompt: section == .corrections ? "For example: Hush Key" : "For example: my email",
                           text: $cue,
                           hint: section == .corrections
                               ? "Replaces whole-word matches in the transcript."
                               : "Matched when you say it at the end of a phrase.",
                           autofocus: true)
                SheetField(label: section == .corrections ? "Use instead" : "Expanded phrase",
                           prompt: section == .corrections ? "For example: HushKey" : "Text to insert into the transcript",
                           text: $expansion, multiline: section == .snippets)
            }
            if let validationMessage {
                SheetNotice(message: validationMessage)
            }
        }
        .animation(Theme.snappy, value: validationMessage)
    }

    private var canSave: Bool {
        section == .vocabulary
            ? !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let message = section == .vocabulary ? onSave(term, nil) : onSave(cue, expansion)
        if let message { validationMessage = message } else { dismiss() }
    }

    private var editorSubtitle: String {
        switch section {
        case .snippets: "Say a cue and HushKey types the full text."
        case .vocabulary: "Names and terms HushKey should spell your way."
        case .corrections: "Fix a word recognition keeps getting wrong."
        }
    }

    private var editorTitle: String {
        switch section {
        case .snippets: initialSnippet == nil ? "New snippet" : "Edit snippet"
        case .vocabulary: initialTerm == nil ? "Add word" : "Edit word"
        case .corrections: initialSnippet == nil ? "New correction" : "Edit correction"
        }
    }
}
