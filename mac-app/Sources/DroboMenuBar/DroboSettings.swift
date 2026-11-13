// Réglages de connexion : adresse/utilisateur en UserDefaults (non sensibles),
// mot de passe dans le Trousseau (jamais en clair sur disque).

import Foundation
import SwiftUI

@MainActor
final class DroboSettings: ObservableObject {
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "drobo.host") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "drobo.username") }
    }
    @Published var password: String {
        didSet {
            try? KeychainStore.savePassword(password)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: "drobo.host") ?? "Drobo5NV2.local"
        username = defaults.string(forKey: "drobo.username") ?? "admin"
        password = KeychainStore.loadPassword() ?? ""
    }
}

@MainActor
final class DroboViewModel: ObservableObject {
    @Published var status: DroboStatus?
    @Published var isRefreshing = false
    @Published var lastErrorMessage: String?

    let settings: DroboSettings
    private let client = DroboClient()
    private var timer: Timer?

    init(settings: DroboSettings) {
        self.settings = settings
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await client.fetchStatus(
                host: settings.host,
                username: settings.username,
                password: settings.password
            )
            status = result
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
