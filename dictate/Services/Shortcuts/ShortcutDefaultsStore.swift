//
//  ShortcutDefaultsStore.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Foundation

struct ShortcutDefaultsStore {
    private let store: UserDefaultsCodableStore<Shortcut>
    private let userDefaults: UserDefaults
    private let disabledKey: String

    init(key: String, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.disabledKey = "\(key).disabled"
        self.store = UserDefaultsCodableStore<Shortcut>(key: key, userDefaults: userDefaults)
    }

    func load() -> Shortcut? {
        guard !isDisabled else { return nil }
        return store.load()
    }

    func save(_ shortcut: Shortcut) {
        userDefaults.set(false, forKey: disabledKey)
        store.save(shortcut)
    }

    func remove() {
        userDefaults.set(true, forKey: disabledKey)
        store.remove()
    }

    func ensureDefault(_ fallbackShortcut: Shortcut) {
        guard !isDisabled, store.load() == nil else { return }
        store.save(fallbackShortcut)
    }

    private var isDisabled: Bool {
        userDefaults.bool(forKey: disabledKey)
    }
}
