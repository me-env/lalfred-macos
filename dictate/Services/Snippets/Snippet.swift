
struct Snippet: Hashable, Decodable, Encodable, Equatable {
  var key: String
  var value: String
  var matchEntireSentenceOnly: Bool
  
  init(
    key: String,
    value: String,
    matchEntireSentenceOnly: Bool = false
  ) {
    self.key = key
    self.value = value
    self.matchEntireSentenceOnly = matchEntireSentenceOnly
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    value = try container.decode(String.self, forKey: .value)
    matchEntireSentenceOnly = try container.decodeIfPresent(Bool.self, forKey: .matchEntireSentenceOnly) ?? false
  }
}
