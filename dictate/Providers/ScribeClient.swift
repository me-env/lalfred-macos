//
//  ScribeClient.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation

struct ScribeClient {
  enum ScribeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyTranscript
    
    var errorDescription: String? {
      switch self {
      case .missingAPIKey:
        return "Missing ElevenLabs API key"
      case .invalidResponse:
        return "Unexpected API response"
      case let .requestFailed(statusCode, message):
        return "Scribe request failed (\(statusCode)): \(message)"
      case .emptyTranscript:
        return "No speech recognized"
      }
    }
  }
  
  private let apiKeyStore: APIKeyDefaultsStore
  private let session: URLSession
  private let endpoint: URL
  private let userDefaults: UserDefaults
  
  init(
    apiKeyStore: APIKeyDefaultsStore = APIKeyDefaultsStore(key: AppDefaultsKey.apiKeyElevenLabs),
    session: URLSession = .shared,
    endpoint: URL = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
    userDefaults: UserDefaults = .standard
  ) {
    self.apiKeyStore = apiKeyStore
    self.session = session
    self.endpoint = endpoint
    self.userDefaults = userDefaults
  }
  
  func transcribeAudio(at fileURL: URL) async throws -> String {
    let apiKey = try loadAPIKey()
    let boundary = "Boundary-\(UUID().uuidString)"
    let body = try makeMultipartBody(fileURL: fileURL, boundary: boundary)
    
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    let (data, response) = try await session.upload(for: request, from: body)
    let httpResponse = try unwrapHTTPResponse(response)
    
    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = parseServerMessage(from: data) ?? "Unknown server error"
      throw ScribeError.requestFailed(statusCode: httpResponse.statusCode, message: message)
    }
    
    let transcript = try parseTranscript(from: data)
    guard !transcript.isEmpty else {
      throw ScribeError.emptyTranscript
    }

    let processedTranscript = applySnippetPostProcessing(to: transcript)
    return processedTranscript
  }
  
  private func loadAPIKey() throws -> String {
    guard let rawKey = apiKeyStore.load() else {
      throw ScribeError.missingAPIKey
    }
    
    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      throw ScribeError.missingAPIKey
    }
    
    return key
  }
  
  private func unwrapHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ScribeError.invalidResponse
    }
    
    return httpResponse
  }
  
  private func parseTranscript(from data: Data) throws -> String {
    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private func parseServerMessage(from data: Data) -> String? {
    if let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
      return response.detail
    }
    
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private func makeMultipartBody(fileURL: URL, boundary: String) throws -> Data {
    var body = Data()
    let lineBreak = "\r\n"
    let model = "scribe_v2"
    
    appendField("model_id", value: model, boundary: boundary, lineBreak: lineBreak, body: &body)
    appendField("no_verbatim", value: "true", boundary: boundary, lineBreak: lineBreak, body: &body)
    
    let keyterms = loadKeyterms()
    keyterms.forEach { keyterm in
      appendField("keyterms", value: keyterm, boundary: boundary, lineBreak: lineBreak, body: &body)
    }
    
    let filename = fileURL.lastPathComponent
    let mimeType = mimeType(for: fileURL.pathExtension)
    let fileData = try Data(contentsOf: fileURL)
    
    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)")
    body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
    body.append(fileData)
    body.append(lineBreak)
    body.append("--\(boundary)--\(lineBreak)")
    
    return body
  }
  
  private func appendField(
    _ name: String,
    value: String,
    boundary: String,
    lineBreak: String,
    body: inout Data
  ) {
    body.append("--\(boundary)\(lineBreak)")
    body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
    body.append("\(value)\(lineBreak)")
  }
  
  private func mimeType(for pathExtension: String) -> String {
    switch pathExtension.lowercased() {
    case "m4a":
      return "audio/m4a"
    case "wav":
      return "audio/wav"
    case "mp3":
      return "audio/mpeg"
    default:
      return "application/octet-stream"
    }
  }
  
  private func loadKeyterms() -> [String] {
    guard let data = userDefaults.data(forKey: AppDefaultsKey.savedWords),
          let rawWords = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    
    var seen = Set<String>()
    return rawWords
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .filter { $0.count <= 50 }
      .filter {
        let normalized = $0.lowercased()
        if seen.contains(normalized) {
          return false
        }
        seen.insert(normalized)
        return true
      }
      .prefix(1000)
      .map { $0 }
  }

  private func applySnippetPostProcessing(to transcript: String) -> String {
    let snippets = loadProcessedSnippets()
    guard !snippets.isEmpty else {
      return transcript
    }

    let normalizedText = makeNormalizedText(from: transcript)
    guard !normalizedText.characters.isEmpty else {
      return transcript
    }

    let normalizedTranscript = String(normalizedText.characters)
    if let exactSnippet = snippets.first(where: {
      $0.matchEntireSentenceOnly && $0.normalizedKey == normalizedTranscript
    }) {
      return exactSnippet.replacement
    }

    let inlineSnippets = snippets.filter { !$0.matchEntireSentenceOnly }
    guard !inlineSnippets.isEmpty else {
      return transcript
    }

    let matches = findSnippetMatches(in: normalizedText.characters, snippets: inlineSnippets)
    guard !matches.isEmpty else {
      return transcript
    }

    var result = transcript
    for match in matches.reversed() {
      let startOriginalIndex = normalizedText.originalIndices[match.start]
      let endCharacterOriginalIndex = normalizedText.originalIndices[match.end - 1]
      let endOriginalIndex = result.index(after: endCharacterOriginalIndex)
      result.replaceSubrange(startOriginalIndex..<endOriginalIndex, with: match.replacement)
    }

    return result
  }

  private func loadProcessedSnippets() -> [ProcessedSnippet] {
    let store = UserDefaultsCodableStore<[Snippet]>(
      key: AppDefaultsKey.savedSnippets,
      userDefaults: userDefaults
    )

    guard let snippets = store.load() else {
      return []
    }

    return snippets
      .map { snippet in
        let key = snippet.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = snippet.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessedSnippet(
          rawKey: key,
          replacement: value,
          matchEntireSentenceOnly: snippet.matchEntireSentenceOnly
        )
      }
      .filter { !$0.replacement.isEmpty }
      .compactMap { snippet in
        let normalizedKey = normalizeForMatching(snippet.rawKey)
        guard !normalizedKey.isEmpty else {
          return nil
        }

        return ProcessedSnippet(
          rawKey: snippet.rawKey,
          replacement: snippet.replacement,
          matchEntireSentenceOnly: snippet.matchEntireSentenceOnly,
          normalizedKey: normalizedKey,
          normalizedKeyCharacters: Array(normalizedKey)
        )
      }
      .sorted { lhs, rhs in
        if lhs.normalizedKeyCharacters.count == rhs.normalizedKeyCharacters.count {
          return lhs.rawKey.count > rhs.rawKey.count
        }
        return lhs.normalizedKeyCharacters.count > rhs.normalizedKeyCharacters.count
      }
  }

  private func findSnippetMatches(
    in normalizedText: [Character],
    snippets: [ProcessedSnippet]
  ) -> [SnippetMatch] {
    var matches: [SnippetMatch] = []
    var index = 0

    while index < normalizedText.count {
      var bestMatch: SnippetMatch?

      for snippet in snippets {
        let keyCharacters = snippet.normalizedKeyCharacters
        let keyLength = keyCharacters.count

        guard keyLength > 0 else {
          continue
        }

        guard index + keyLength <= normalizedText.count else {
          continue
        }

        if !matchesPrefix(
          normalizedText,
          at: index,
          prefix: keyCharacters
        ) {
          continue
        }

        if !hasWordBoundaries(
          normalizedText,
          start: index,
          end: index + keyLength
        ) {
          continue
        }

        bestMatch = SnippetMatch(
          start: index,
          end: index + keyLength,
          replacement: snippet.replacement
        )
        break
      }

      if let bestMatch {
        matches.append(bestMatch)
        index = bestMatch.end
      } else {
        index += 1
      }
    }

    return matches
  }

  private func makeNormalizedText(from text: String) -> NormalizedText {
    var characters: [Character] = []
    var originalIndices: [String.Index] = []
    var previousWasWhitespace = true

    var currentIndex = text.startIndex
    while currentIndex < text.endIndex {
      let character = text[currentIndex]
      let folded = String(character)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

      for scalar in folded.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
          characters.append(Character(String(scalar).lowercased()))
          originalIndices.append(currentIndex)
          previousWasWhitespace = false
          continue
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar), !previousWasWhitespace {
          characters.append(" ")
          originalIndices.append(currentIndex)
          previousWasWhitespace = true
        }
      }

      currentIndex = text.index(after: currentIndex)
    }

    while characters.last == " " {
      characters.removeLast()
      originalIndices.removeLast()
    }

    return NormalizedText(characters: characters, originalIndices: originalIndices)
  }

  private func normalizeForMatching(_ value: String) -> String {
    let normalized = makeNormalizedText(from: value)
    return String(normalized.characters)
  }

  private func matchesPrefix(
    _ text: [Character],
    at start: Int,
    prefix: [Character]
  ) -> Bool {
    for offset in 0..<prefix.count where text[start + offset] != prefix[offset] {
      return false
    }

    return true
  }

  private func hasWordBoundaries(
    _ text: [Character],
    start: Int,
    end: Int
  ) -> Bool {
    if start > 0, isWordCharacter(text[start - 1]) {
      return false
    }

    if end < text.count, isWordCharacter(text[end]) {
      return false
    }

    return true
  }

  private func isWordCharacter(_ character: Character) -> Bool {
    character != " "
  }
}

private struct ProcessedSnippet {
  let rawKey: String
  let replacement: String
  let matchEntireSentenceOnly: Bool
  let normalizedKey: String
  let normalizedKeyCharacters: [Character]

  init(
    rawKey: String,
    replacement: String,
    matchEntireSentenceOnly: Bool = false,
    normalizedKey: String = "",
    normalizedKeyCharacters: [Character] = []
  ) {
    self.rawKey = rawKey
    self.replacement = replacement
    self.matchEntireSentenceOnly = matchEntireSentenceOnly
    self.normalizedKey = normalizedKey
    self.normalizedKeyCharacters = normalizedKeyCharacters
  }
}

private struct NormalizedText {
  let characters: [Character]
  let originalIndices: [String.Index]
}

private struct SnippetMatch {
  let start: Int
  let end: Int
  let replacement: String
}

private struct TranscriptionResponse: Decodable {
  let text: String
}

private struct ServerErrorResponse: Decodable {
  let detail: String
}

private extension Data {
  mutating func append(_ string: String) {
    if let encoded = string.data(using: .utf8) {
      append(encoded)
    }
  }
}
