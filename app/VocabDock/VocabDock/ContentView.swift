//
//  ContentView.swift
//  VocabDock
//
//  Created by nrshima on 2026/02/22.
//

import SwiftUI
import SwiftData

@Model
final class VocabularyEntry {
    @Attribute(.unique) var normalizedTerm: String
    var term: String
    var meaning: String
    var explanationText: String
    var exampleSentence: String
    var tagsCSV: String
    var memo: String
    var updatedAt: Date

    init(
        term: String,
        normalizedTerm: String,
        meaning: String,
        explanationText: String,
        exampleSentence: String,
        tagsCSV: String = "",
        memo: String = "",
        updatedAt: Date = .now
    ) {
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.meaning = meaning
        self.explanationText = explanationText
        self.exampleSentence = exampleSentence
        self.tagsCSV = tagsCSV
        self.memo = memo
        self.updatedAt = updatedAt
    }
}

struct LookupResult {
    let term: String
    let meaning: String
    let explanation: String
    let example: String
}

protocol DictionaryService {
    func lookup(term: String) async throws -> LookupResult
}

enum DictionaryError: Error {
    case emptyInput
}

struct MockDictionaryService: DictionaryService {
    func lookup(term: String) async throws -> LookupResult {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.emptyInput }

        try await Task.sleep(for: .milliseconds(400))
        return LookupResult(
            term: trimmed,
            meaning: "\(trimmed) の意味（モック）",
            explanation: "\(trimmed) に関する簡単な解説（モック）です。",
            example: "I learned the word \"\(trimmed)\" today."
        )
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyEntry.updatedAt, order: .reverse) private var history: [VocabularyEntry]

    @State private var query: String = ""
    @State private var historySearchText: String = ""
    @State private var selectedTag: String = "すべて"
    @State private var selectedEntry: VocabularyEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service: DictionaryService = MockDictionaryService()
    private let allTagOption = "すべて"

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                TextField("履歴を検索", text: $historySearchText)
                    .textFieldStyle(.roundedBorder)

                Picker("タグ", selection: $selectedTag) {
                    ForEach(tagOptions, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .pickerStyle(.menu)

                List(filteredHistory) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.term).font(.headline)
                            Text(entry.meaning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !entry.tagsCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(entry.tagsCSV)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: history, initial: true) { _, _ in
                if !tagOptions.contains(selectedTag) {
                    selectedTag = allTagOption
                }
            }
            .navigationTitle("履歴")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        TextField("調べたい英単語・表現", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await search() }
                            }
                        Button("検索") {
                            Task { await search() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }

                    if isLoading {
                        ProgressView("検索中...")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    if let selectedEntry {
                        EntryDetailCard(
                            entry: selectedEntry,
                            availableTags: tagOptions.filter { $0 != allTagOption }
                        )
                    } else {
                        Text("単語を検索するとここに結果が表示されます。")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("VocabDock")
        }
    }

    private var tagOptions: [String] {
        let allTags = history.flatMap { parseTags(from: $0.tagsCSV) }
        let unique = Array(Set(allTags)).sorted()
        return [allTagOption] + unique
    }

    private var filteredHistory: [VocabularyEntry] {
        history.filter { entry in
            let keyword = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesText = keyword.isEmpty
                || entry.term.lowercased().contains(keyword)
                || entry.meaning.lowercased().contains(keyword)

            let matchesTag = selectedTag == allTagOption
                || parseTags(from: entry.tagsCSV).contains(selectedTag)

            return matchesText && matchesTag
        }
    }

    private func parseTags(from csv: String) -> [String] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func search() async {
        errorMessage = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard !normalized.isEmpty else { return }

        do {
            let descriptor = FetchDescriptor<VocabularyEntry>(
                predicate: #Predicate { $0.normalizedTerm == normalized }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.updatedAt = .now
                try modelContext.save()
                selectedEntry = existing
                return
            }

            isLoading = true
            let result = try await service.lookup(term: trimmed)
            let newEntry = VocabularyEntry(
                term: result.term,
                normalizedTerm: normalized,
                meaning: result.meaning,
                explanationText: result.explanation,
                exampleSentence: result.example
            )
            modelContext.insert(newEntry)
            try modelContext.save()
            selectedEntry = newEntry
        } catch {
            errorMessage = "検索または保存に失敗しました: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

private struct EntryDetailCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: VocabularyEntry
    let availableTags: [String]
    @State private var initialExampleSentence: String = ""
    @State private var initialMemo: String = ""
    @State private var initialTagsCSV: String = ""
    @State private var saveStatusMessage: String = ""

    private var hasUnsavedChanges: Bool {
        entry.exampleSentence != initialExampleSentence
            || entry.memo != initialMemo
            || entry.tagsCSV != initialTagsCSV
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.term)
                .font(.title2)
                .bold()

            Group {
                Text("意味").font(.headline)
                Text(entry.meaning)
                Text("解説").font(.headline)
                Text(entry.explanationText)
                Text("例文").font(.headline)
                TextEditor(text: $entry.exampleSentence)
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3))
                    )
            }

            Text("タグ（カンマ区切り）").font(.headline)
            TextField("例: article, youtube", text: $entry.tagsCSV)
                .textFieldStyle(.roundedBorder)

            if !availableTags.isEmpty {
                Text("既存タグを追加").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            Button(tag) {
                                addTag(tag)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Text("メモ").font(.headline)
            TextEditor(text: $entry.memo)
                .frame(minHeight: 88)
                .padding(6)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                )

            Button("変更を保存する") {
                entry.updatedAt = .now
                do {
                    try modelContext.save()
                    syncInitialValues()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm:ss"
                    saveStatusMessage = "保存完了: \(formatter.string(from: .now))"
                } catch {
                    saveStatusMessage = "保存失敗: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.bordered)
            .disabled(!hasUnsavedChanges)

            if hasUnsavedChanges {
                Text("未保存の変更があります")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if !saveStatusMessage.isEmpty {
                Text(saveStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            syncInitialValues()
        }
        .onChange(of: entry.normalizedTerm) { _, _ in
            syncInitialValues()
        }
    }

    private func addTag(_ tag: String) {
        let currentTags = parseTags(entry.tagsCSV)
        guard !currentTags.contains(tag) else { return }
        entry.tagsCSV = (currentTags + [tag]).joined(separator: ", ")
    }

    private func parseTags(_ csv: String) -> [String] {
        csv.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncInitialValues() {
        initialExampleSentence = entry.exampleSentence
        initialMemo = entry.memo
        initialTagsCSV = entry.tagsCSV
    }
}
