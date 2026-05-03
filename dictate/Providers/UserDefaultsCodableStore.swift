import Foundation

struct UserDefaultsCodableStore<Value: Codable> {
    private let key: String
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        key: String,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.key = key
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> Value? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? encoder.encode(value) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    func remove() {
        userDefaults.removeObject(forKey: key)
    }
}
