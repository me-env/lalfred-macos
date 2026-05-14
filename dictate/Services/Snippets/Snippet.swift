
struct Snippet: Hashable, Decodable, Encodable, Equatable {
  var key: String
  var value: String
  var fullMatch: Bool
  
  init(
    key: String,
    value: String,
    fullMatch: Bool = false
  ) {
    self.key = key
    self.value = value
    self.fullMatch = fullMatch
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = try container.decode(String.self, forKey: .key)
    value = try container.decode(String.self, forKey: .value)
    fullMatch = try container.decodeIfPresent(Bool.self, forKey: .fullMatch)
      ?? container.decodeIfPresent(Bool.self, forKey: .legacyFullMatch)
      ?? false
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key, forKey: .key)
    try container.encode(value, forKey: .value)
    try container.encode(fullMatch, forKey: .fullMatch)
  }
  
  private enum CodingKeys: String, CodingKey {
    case key
    case value
    case fullMatch
    case legacyFullMatch = "matchEntireSentenceOnly"
  }
}
