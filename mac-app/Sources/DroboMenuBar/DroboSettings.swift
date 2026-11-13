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
            let code = result.statusCode.map(String.init) ?? "?"
            logState("OK — état \(code), sudo par \(result.sudoPath?.rawValue ?? "?")")
        } catch {
            let message = describeError(error)
            lastErrorMessage = message
            logState("ERREUR — \(message)")
        }
    }

    /// Journal minimal sur la sortie d'erreur (→ /tmp/drobo-menubar.log quand
    /// l'app est lancée par launchd). Une ligne seulement quand l'état change,
    /// pour pouvoir diagnostiquer une panne sans ouvrir le panneau.
    private var lastLoggedState: String?

    private func logState(_ state: String) {
        guard state != lastLoggedState else { return }
        lastLoggedState = state
        let stamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("\(stamp) \(state)\n".utf8))
    }
}
