// Collecte de l'état du Drobo 5N2 via SSH (Citadel).
//
// Reflète drobo5n/collect.py côté outil Python :
//   - esa dnasStatus     -> code de santé global
//   - esa vxver          -> version du firmware
//   - esa vxphyscapacity -> capacité physique totale (octets)
//   - esa vxusedcapacity -> capacité physique utilisée (octets)
//   - esa vxdiskpackid   -> identifiant du disk pack
//   - df -k              -> capacité du volume /mnt/DroboFS
//
// `esa` exige root. Deux chemins, essayés dans cet ordre (voir PROGRESS.md, MISE À JOUR 9) :
//   1. `sudo -n` : passe si la règle NOPASSWD ciblée sur /usr/bin/esa est présente
//      (/tmp/sudo/sudoers.d/admin). Aucun mot de passe n'est envoyé à sudo.
//   2. `sudo -S` : la règle a disparu (elle vit sur un tmpfs et saute à chaque
//      redémarrage du Drobo). L'app donne alors elle-même le mot de passe admin à
//      sudo, sur son entrée standard, via un here-document.
// L'app ne dépend donc plus de la règle NOPASSWD.
//
// La température par disque n'est pas incluse (le Drobo la rapporte à 0, voir PROGRESS.md).

import Citadel
import Foundation
import NIO

enum DroboClientError: Error, LocalizedError {
    case notConfigured
    case passwordNotUsable
    case sudoRefused(exitCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Adresse, utilisateur ou mot de passe manquant — vérifie les Réglages (⌘,)."
        case .passwordNotUsable:
            return "Le mot de passe contient un saut de ligne : impossible de le donner à sudo."
        case .sudoRefused(let exitCode):
            return "Connexion SSH réussie, mais sudo a refusé le mot de passe sur le Drobo (code \(exitCode))."
        }
    }
}

/// Comment sudo a été satisfait lors de la dernière lecture.
enum SudoPath: String {
    case noPassword = "règle NOPASSWD"
    case password = "mot de passe"
}

/// Message d'erreur complet et lisible (le `localizedDescription` par défaut des
/// erreurs Swift donne « The operation couldn't be completed », qui ne dit rien).
func describeError(_ error: Error) -> String {
    if let known = error as? DroboClientError {
        return known.errorDescription ?? "\(known)"
    }
    if let failure = error as? SSHClient.CommandFailed {
        return "Le Drobo a refusé une commande (code de sortie \(failure.exitCode))."
    }
    if error is AuthenticationFailed {
        return "Connexion SSH refusée : utilisateur ou mot de passe incorrect."
    }
    if let localized = error as? LocalizedError, let text = localized.errorDescription {
        return text
    }
    return "\(String(reflecting: type(of: error))) : \(error)"
}

actor DroboClient {
    private static let esaSubcommands = ["dnasStatus", "vxver", "vxdiskpackid", "vxphyscapacity", "vxusedcapacity"]
    /// Code de sortie maison : « sudo -n ne passe pas, il faut le mot de passe ».
    private static let needsPasswordExitCode = 97

    func fetchStatus(host: String, username: String, password: String) async throws -> DroboStatus {
        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            throw DroboClientError.notConfigured
        }

        let settings = SSHClientSettings(
            host: host,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            // Réseau local de confiance ; la clé d'hôte du Drobo change au reflash
            // du firmware (même choix que AutoAddPolicy côté outil Python).
            hostKeyValidator: .acceptAnything()
        )

        let client = try await SSHClient.connect(to: settings)
        do {
            var status = DroboStatus(host: host)

            let (esa, sudoPath) = try await readEsa(client, password: password)
            status.sudoPath = sudoPath

            status.statusCode = parseFirstInt64(esa["dnasStatus"] ?? "").map(Int.init)
            if let code = status.statusCode, let info = dnasStatusTable[code] {
                status.overallHealth = info.health
                status.healthLabel = info.label
            } else {
                status.overallHealth = .unknown
                status.healthLabel = "code inconnu"
            }

            status.firmware = esa["vxver"].flatMap { $0.isEmpty ? nil : $0 }
            status.diskPackId = esa["vxdiskpackid"].flatMap { $0.isEmpty ? nil : $0 }
            status.physicalTotalBytes = parseFirstInt64(esa["vxphyscapacity"] ?? "")
            status.physicalUsedBytes = parseFirstInt64(esa["vxusedcapacity"] ?? "")

            let dfOutput = try await execString(client, "df -k")
            let (volumeTotal, volumeUsed) = Self.parseVolumeDf(dfOutput)
            status.volumeTotalBytes = volumeTotal
            status.volumeUsedBytes = volumeUsed

            status.lastUpdated = Date()
            try await client.close()
            return status
        } catch {
            try? await client.close()
            throw error
        }
    }

    /// Lance toutes les sous-commandes `esa` en une seule commande SSH et renvoie
    /// leurs sorties par nom, avec le chemin sudo qui a fonctionné.
    private func readEsa(_ client: SSHClient, password: String) async throws -> ([String: String], SudoPath) {
        let list = Self.esaSubcommands.joined(separator: " ")
        // Crochet de test : DROBO_SUDO_MODE=password force le chemin 2.
        let forcePassword = ProcessInfo.processInfo.environment["DROBO_SUDO_MODE"] == "password"

        if !forcePassword {
            let script = "sudo -n /usr/bin/esa dnasStatus >/dev/null 2>&1 || exit \(Self.needsPasswordExitCode); "
                + "for c in \(list); do echo \"@@$c\"; sudo -n /usr/bin/esa $c 2>&1; done; true"
            do {
                let output = try await execString(client, script)
                return (Self.parseSections(output), .noPassword)
            } catch let failure as SSHClient.CommandFailed where failure.exitCode == Self.needsPasswordExitCode {
                // Règle NOPASSWD absente : on continue avec le mot de passe.
            }
        }

        guard !password.contains("\n"), !password.contains("\r") else {
            throw DroboClientError.passwordNotUsable
        }
        // Le mot de passe arrive à sudo par son entrée standard (here-document à
        // délimiteur cité : aucune expansion par le shell). Il n'apparaît jamais
        // dans les arguments de sudo.
        let delimiter = "DROBO_EOF_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let script = "sudo -S -p '' sh -c 'for c in \(list); do echo \"@@$c\"; /usr/bin/esa $c 2>&1; done; true' "
            + "<<'\(delimiter)'\n\(password)\n\(delimiter)\n"
        do {
            let output = try await execString(client, script)
            return (Self.parseSections(output), .password)
        } catch let failure as SSHClient.CommandFailed {
            throw DroboClientError.sudoRefused(exitCode: failure.exitCode)
        }
    }

    private func execString(_ client: SSHClient, _ command: String, mergeStreams: Bool = false) async throws -> String {
        let buffer = try await client.executeCommand(command, mergeStreams: mergeStreams)
        return String(buffer: buffer)
    }

    /// Découpe une sortie balisée par des lignes `@@nom` en dictionnaire nom -> texte.
    static func parseSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        var current: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                current = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                sections[current!] = ""
            } else if let key = current {
                sections[key, default: ""] += line + "\n"
            }
        }
        return sections.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Capacité totale/utilisée du volume Drobo via `df -k` (point de montage /mnt/DroboFS).
    static func parseVolumeDf(_ output: String) -> (Int64?, Int64?) {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 6 else { continue }
            if parts[5] == "/mnt/DroboFS" && parts[0].hasPrefix("/dev/") {
                let total = Int64(parts[1]).map { $0 * 1024 }
                let used = Int64(parts[2]).map { $0 * 1024 }
                return (total, used)
            }
        }
        return (nil, nil)
    }
}
