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
        // DROBO_NO_KEYCHAIN=1 : ne touche pas au Trousseau (essais de rendu avec un
        // binaire fraîchement compilé, pour éviter la demande d'accès de macOS).
        let skipKeychain = ProcessInfo.processInfo.environment["DROBO_NO_KEYCHAIN"] == "1"
        password = skipKeychain ? "" : (KeychainStore.loadPassword() ?? "")
    }
}

/// État affiché par l'app. Deux sources, lues en parallèle toutes les 30 s :
///   - le flux du port 5000 (`DroboFeed`) : sans mot de passe, donne l'état
///     général, la capacité et le détail de chaque baie ;
///   - SSH + `esa` (`DroboStatus`) : contre-vérification, et capacité du volume.
/// Le flux passe en premier ; SSH prend le relais s'il manque.
@MainActor
final class DroboViewModel: ObservableObject {
    @Published var status: DroboStatus?
    @Published var feed: DroboFeed?
    @Published var isRefreshing = false
    /// Erreur de la lecture SSH (nil si elle a réussi).
    @Published var lastErrorMessage: String?
    /// Erreur de la lecture du port 5000 (nil si elle a réussi).
    @Published var feedErrorMessage: String?

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

        let host = settings.host
        let username = settings.username
        let password = settings.password
        let client = self.client

        async let sshResult: Result<DroboStatus, Error> = {
            do {
                return .success(try await client.fetchStatus(host: host, username: username, password: password))
            } catch {
                return .failure(error)
            }
        }()
        async let feedResult: Result<DroboFeed, Error> = {
            do {
                return .success(try await DroboFeedReader.fetch(host: host))
            } catch {
                return .failure(error)
            }
        }()

        switch await feedResult {
        case .success(let value):
            feed = value
            feedErrorMessage = nil
        case .failure(let error):
            feedErrorMessage = describeError(error)
        }
        switch await sshResult {
        case .success(let value):
            status = value
            lastErrorMessage = nil
        case .failure(let error):
            lastErrorMessage = describeError(error)
        }

        logState(stateSummary)
    }

    // MARK: - Valeurs affichées (flux d'abord, SSH en relais)

    /// Vrai si au moins une des deux sources a déjà répondu.
    var hasData: Bool { feed != nil || status != nil }

    /// Vrai si les deux sources viennent d'échouer.
    var isUnreachable: Bool { feedErrorMessage != nil && lastErrorMessage != nil }

    var dnasCode: Int? {
        if feedErrorMessage == nil, let code = feed?.dnasStatus { return code }
        if lastErrorMessage == nil, let code = status?.statusCode { return code }
        return feed?.dnasStatus ?? status?.statusCode
    }

    /// État général : le code du Drobo, aggravé par le pire voyant et par tout
    /// compteur d'erreurs non nul.
    var overallHealth: Health {
        if isUnreachable { return .unknown }
        var health = dnasCode.flatMap { dnasStatusTable[$0]?.health } ?? .unknown
        for bay in feed?.slots ?? [] {
            health = health.worst(bay.led.health)
            if bay.errorCount > 0 { health = health.worst(.warning) }
        }
        return health
    }

    var healthTitle: String {
        if isUnreachable { return "Injoignable" }
        switch overallHealth {
        case .good: return "Tout va bien"
        case .warning: return "À surveiller"
        case .critical: return "Critique"
        case .unknown: return "Inconnu"
        }
    }

    /// Phrase qui dit pourquoi l'état n'est pas « tout va bien » (nil sinon).
    var healthDetail: String? {
        if isUnreachable { return "Le Drobo ne répond ni sur le port 5000 ni en SSH." }
        let lines = alertLines
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    var displayName: String { feed?.name ?? "Drobo 5N2" }
    var modelName: String? { feed?.model }
    var firmware: String? { feed?.firmware ?? status?.firmware }

    var totalBytes: Int64? { feed?.totalBytes ?? status?.physicalTotalBytes }
    var usedBytes: Int64? { feed?.usedBytes ?? status?.physicalUsedBytes }
    var freeBytes: Int64? {
        guard let total = totalBytes, let used = usedBytes else { return nil }
        return total - used
    }
    var usedPct: Double? {
        guard let total = totalBytes, total > 0, let used = usedBytes else { return nil }
        return Double(used) / Double(total) * 100
    }

    var lastUpdated: Date? {
        [feed?.receivedAt, status?.lastUpdated].compactMap { $0 }.max()
    }

    // MARK: - Alertes

    /// Tout ce qui s'écarte de la normale, une ligne par constat.
    var alertLines: [String] {
        var lines: [String] = []
        if let code = dnasCode, let info = dnasStatusTable[code], info.health != .good {
            lines.append("État général : \(info.label) (code \(code))")
        }
        for bay in feed?.slots ?? [] {
            let name = bay.slot == feed?.accelerator?.slot ? "Accélérateur" : "Baie \(bay.slot + 1)"
            if bay.led.health != .good {
                lines.append("\(name) : \(bay.led.label)")
            }
            if bay.errorCount > 0 {
                lines.append("\(name) : \(bay.errorCount) erreur\(bay.errorCount > 1 ? "s" : "")")
            }
        }
        return lines
    }

    // MARK: - Journal

    private var stateSummary: String {
        var parts: [String] = []
        if let feedErrorMessage {
            parts.append("flux 5000 en erreur (\(feedErrorMessage))")
        } else if let feed {
            let disks = feed.bays.filter { !$0.isEmpty }.count
            parts.append("flux 5000 : état \(feed.dnasStatus.map(String.init) ?? "?"), \(disks) disque\(disks > 1 ? "s" : "")")
        }
        if let lastErrorMessage {
            parts.append("SSH en erreur (\(lastErrorMessage))")
        } else if let status {
            parts.append("SSH : état \(status.statusCode.map(String.init) ?? "?"), sudo par \(status.sudoPath?.rawValue ?? "?")")
        }
        let alerts = alertLines
        if !alerts.isEmpty {
            parts.append("constats : " + alerts.joined(separator: " ; "))
        }
        let prefix = isUnreachable ? "ERREUR" : (alerts.isEmpty && feedErrorMessage == nil && lastErrorMessage == nil ? "OK" : "ATTENTION")
        return "\(prefix) — " + parts.joined(separator: " | ")
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
