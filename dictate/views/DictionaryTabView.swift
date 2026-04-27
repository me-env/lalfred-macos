//
//  DictionaryTabView.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/27/26.
//

import SwiftUI

struct DictionaryTabView: View {
    @AppStorage("savedWords") private var savedWordsData: Data = Data()
    @State private var newWord: String = ""

    private var words: [String] {
        (try? JSONDecoder().decode([String].self, from: savedWordsData)) ?? []
    }

    private func saveWords(_ words: [String]) {
        savedWordsData = (try? JSONEncoder().encode(words)) ?? Data()
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = words
        current.append(trimmed)
        saveWords(current)
        newWord = ""
    }

    private func deleteWords(at offsets: IndexSet) {
        var current = words
        current.remove(atOffsets: offsets)
        saveWords(current)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Add a word…", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            if words.isEmpty {
                Spacer()
                Text("No words yet")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: deleteWords)
                }
            }
        }
    }
}
