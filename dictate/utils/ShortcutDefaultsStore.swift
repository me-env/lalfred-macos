//
//  ShortcutDefaultsStore.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Foundation

struct ShortcutDefaultsStore {
    private let store: UserDefaultsCodableStore<Shortcut>

    init(key: String, userDefaults: UserDefaults = .standard) {
        self.store = UserDefaultsCodableStore<Shortcut>(key: key, userDefaults: userDefaults)
    }

    func load() -> Shortcut? {
        store.load()
    }

    func save(_ shortcut: Shortcut) {
        store.save(shortcut)
    }

    func remove() {
        store.remove()
    }
}
