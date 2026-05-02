//
//  DictionaryTabView.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/27/26.
//

import SwiftUI

struct DictionaryTabView: View {
  @State private var words: [String]
  @State private var newWord: String = ""

  private let keyTermsStore: KeyTermsStore

  init(keyTermsStore: KeyTermsStore = KeyTermsStore()) {
    self.keyTermsStore = keyTermsStore
    _words = State(initialValue: keyTermsStore.load())
  }
  
  private var sanitizedInput: String {
    newWord.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  var body: some View {
    SectionBox("Dictionary", caption: "Press Return to add. Use the trash icon to remove.") {
      inputField
      wordContent
    }
    .padding()
  }
  
  private var inputField: some View {
    InlineInputField(
      title: "Add a word",
      text: $newWord,
      onSubmit: addWord
    )
  }
  
  @ViewBuilder
  private var wordContent: some View {
    if words.isEmpty {
      emptyState
    } else {
      wordList
    }
  }
  
  private var emptyState: some View {
    VStack {
      Spacer()
      ContentUnavailableView(
        "No words yet",
        systemImage: "text.book.closed",
        description: Text("Add names, tools, or jargon you want to transcribe accurately.")
      )
      .frame(maxWidth: .infinity, minHeight: 200)
      .padding(.vertical, 8)
      Spacer()
    }
  }
  
  private var wordList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(words, id: \.self) { word in
          WordRow(word: word) {
            removeWord(word)
          }
        }
      }
      .padding(.vertical, 2)
    }
    .frame(minHeight: 220)
  }
  
  private func addWord() {
    let trimmed = sanitizedInput
    guard !trimmed.isEmpty else {
      return
    }

    words = keyTermsStore.add(trimmed)
    newWord = ""
  }

  private func removeWord(_ word: String) {
    words = keyTermsStore.remove(word)
  }
}

private struct WordRow: View {
  let word: String
  let onRemove: () -> Void
  
  var body: some View {
    HStack(spacing: 10) {
      Text(word)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      Button(role: .destructive, action: onRemove) {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Remove \(word)")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(0.35), lineWidth: 1)
    )
    .contextMenu {
      Button(role: .destructive, action: onRemove) {
        Label("Remove", systemImage: "trash")
      }
    }
  }
}

#Preview {
  DictionaryTabView()
}
