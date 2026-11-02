import SwiftUI

private enum PersonalizationSection: String, CaseIterable, Identifiable {
    case snippets = "Snippets"
    case vocabulary = "Vocabulary"
    case corrections = "Corrections"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .snippets: "text.quote"
        case .vocabulary: "character.book.closed"
        case .corrections: "arrow.left.arrow.right"
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
    @State private var section: PersonalizationSection = .snippets
    @State private var query = ""
    @State private var editor: PersonalizationEditorRequest?
    @State private var notice: String?

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
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "PERSONALIZE",
                    title: "Your words, your shortcuts",
                    subtitle: "Teach HushKey your vocabulary, phrase shortcuts, and preferred spellings. These settings stay on this Mac.")

                HStack(spacing: 12) {
                    summaryCard(title: "Snippets", count: snippets.count, symbol: "text.quote")
                    summaryCard(title: "Vocabulary", count: vocabulary.count, symbol: "character.book.closed")
                    summaryCard(title: "Corrections", count: corrections.count, symbol: "arrow.left.arrow.right")
                }

                GroupBox {
                    HStack(spacing: 14) {
                        Picker("Personalization type", selection: $section) {
                            ForEach(PersonalizationSection.allCases) { item in
                                Label(item.rawValue, systemImage: item.symbol).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 340)

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search \(section.rawValue.lowercased())", text: $query)
                                .textFieldStyle(.plain)
                                .accessibilityLabel("Search \(section.rawValue.lowercased())")
                            if !query.isEmpty {
                                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary, lineWidth: 1))

                        Button("Add", systemImage: "plus") {
                            editor = PersonalizationEditorRequest(section: section, snippet: nil, term: nil)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        if section == .snippets {
                            snippetList
                        } else if section == .vocabulary {
                            vocabularyList
                        } else {
                            correctionList
                        }
                    }
                    .padding(8)
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                }

                if section == .snippets {
                    advancedSnippetEditor
                } else if section == .vocabulary {
                    Label("Your saved terms are prioritized ahead of optional mode, nearby-text, and Silent Lab hints. Up to 100 hints go to on-device Speech per capture; recognition can still misspell unfamiliar names.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    advancedCorrectionEditor
                }

                Label("HushKey uses personalization entries locally. It does not upload your words, corrections, or snippets.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var snippetList: some View {
        if filteredSnippets.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No snippets yet" : "No matching snippets",
                systemImage: query.isEmpty ? "text.quote" : "magnifyingglass",
                description: Text(query.isEmpty ? "Add a short spoken cue and the phrase HushKey should expand it to." : "Try another cue or part of the expanded phrase."))
                .frame(minHeight: 150)
        } else {
            ForEach(filteredSnippets) { entry in
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.cue).font(.headline)
                        Text(entry.expansion).font(.body).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Button("Edit \(entry.cue)", systemImage: "pencil") {
                        editor = PersonalizationEditorRequest(section: .snippets, snippet: entry, term: nil)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Edit snippet")
                    Button("Delete \(entry.cue)", systemImage: "trash", role: .destructive) {
                        removeSnippet(entry.cue)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete snippet")
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var vocabularyList: some View {
        if filteredVocabulary.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No personal words yet" : "No matching words",
                systemImage: query.isEmpty ? "character.book.closed" : "magnifyingglass",
                description: Text(query.isEmpty ? "Add names, product terms, or specialist vocabulary to help recognition." : "Try another search."))
                .frame(minHeight: 150)
        } else {
            ForEach(filteredVocabulary, id: \.self) { term in
                HStack(spacing: 12) {
                    Image(systemName: "character.book.closed").foregroundStyle(.secondary)
                    Text(term).font(.body)
                    Spacer()
                    Button("Edit \(term)", systemImage: "pencil") {
                        editor = PersonalizationEditorRequest(section: .vocabulary, snippet: nil, term: term)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Edit word")
                    Button("Delete \(term)", systemImage: "trash", role: .destructive) {
                        removeTerm(term)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete word")
                }
                .padding(.vertical, 9)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var correctionList: some View {
        if filteredCorrections.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No correction rules yet" : "No matching corrections",
                systemImage: query.isEmpty ? "arrow.left.arrow.right" : "magnifyingglass",
                description: Text(query.isEmpty
                                  ? "Add a recognized phrase and the exact phrase HushKey should use instead."
                                  : "Try another recognized phrase or replacement."))
                .frame(minHeight: 150)
        } else {
            ForEach(filteredCorrections) { rule in
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.cue).font(.headline)
                        Label(rule.expansion, systemImage: "arrow.right")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Button("Edit correction for \(rule.cue)", systemImage: "pencil") {
                        editor = PersonalizationEditorRequest(section: .corrections, snippet: rule, term: nil)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Edit correction")
                    Button("Delete correction for \(rule.cue)", systemImage: "trash", role: .destructive) {
                        removeCorrection(rule.cue)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete correction")
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private var advancedSnippetEditor: some View {
        @Bindable var model = model
        return DisclosureGroup("Advanced snippet list") {
            TextEditor(text: $model.dictationSnippets)
                .font(.body.monospaced())
                .frame(minHeight: 90)
                .padding(5)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)
            Text("One per line: spoken cue => expanded phrase. Use this editor to repair malformed older entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let validation = DictationSnippetExpander.validation(for: model.dictationSnippets)
            Label(validation.invalidLines.isEmpty
                  ? "\(validation.validCount) ready"
                  : "\(validation.validCount) ready · check line\(validation.invalidLines.count == 1 ? "" : "s") \(validation.invalidLines.map(String.init).joined(separator: ", "))",
                  systemImage: validation.invalidLines.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(validation.invalidLines.isEmpty ? Color.secondary : Theme.danger)
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private var advancedCorrectionEditor: some View {
        @Bindable var model = model
        return DisclosureGroup("Advanced correction list") {
            TextEditor(text: $model.dictationCorrectionRules)
                .font(.body.monospaced())
                .frame(minHeight: 90)
                .padding(5)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 8)
            Text("One per line: recognized phrase => corrected phrase. Matches are case-insensitive and respect whole-word boundaries. Raw recognition remains available to restore.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let validation = DictationCorrectionRules.validation(for: model.dictationCorrectionRules)
            Label(validation.invalidLines.isEmpty
                  ? "\(validation.validCount) ready"
                  : "\(validation.validCount) ready · check line\(validation.invalidLines.count == 1 ? "" : "s") \(validation.invalidLines.map(String.init).joined(separator: ", "))",
                  systemImage: validation.invalidLines.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(validation.invalidLines.isEmpty ? Color.secondary : Color.orange)
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryCard(title: String, count: Int, symbol: String) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text("\(count)").font(.title3.weight(.semibold).monospacedDigit())
                }
                Spacer(minLength: 0)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
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
        NavigationStack {
            Form {
                if section != .vocabulary {
                    Section(section == .corrections ? "Recognized phrase" : "Spoken cue") {
                        TextField(section == .corrections ? "For example: Hush Key" : "For example: my email", text: $cue)
                        Text(section == .corrections
                             ? "Corrects complete word or phrase matches in the recognized transcript."
                             : "HushKey matches the full cue at the end of a spoken phrase.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section(section == .corrections ? "Use instead" : "Expanded phrase") {
                        TextField(section == .corrections ? "For example: HushKey" : "Text to insert into the transcript", text: $expansion)
                    }
                } else {
                    Section("Word or phrase") {
                        TextField("For example: HushKey", text: $term)
                    }
                    Text("This stays on this Mac and is provided as an on-device recognition hint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editorTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let message = section == .vocabulary ? onSave(term, nil) : onSave(cue, expansion)
                        if let message { validationMessage = message }
                        else { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 430, minHeight: 300)
    }

    private var editorTitle: String {
        switch section {
        case .snippets: initialSnippet == nil ? "New snippet" : "Edit snippet"
        case .vocabulary: initialTerm == nil ? "Add word" : "Edit word"
        case .corrections: initialSnippet == nil ? "New correction" : "Edit correction"
        }
    }
}
