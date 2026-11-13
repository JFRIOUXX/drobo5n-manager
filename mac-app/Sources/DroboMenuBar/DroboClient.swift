// Collecte de l'état du Drobo 5N2 via SSH (Citadel).
//
// Reflète drobo5n/collect.py côté outil Python :
//   - sudo /usr/bin/esa dnasStatus     -> code de santé global
//   - sudo /usr/bin/esa vxver          -> version du firmware
//   - sudo /usr/bin/esa vxphyscapacity -> capacité physique totale (octets)
//   - sudo /usr/bin/esa vxusedcapacity -> capacité physique utilisée (octets)
//   - sudo /usr/bin/esa vxdiskpackid   -> identifiant du disk pack
//   - df -k                            -> capacité du volume /mnt/DroboFS
//
// `sudo` ne demande pas de mot de passe pour /usr/bin/esa : une règle NOPASSWD
// dédiée a été posée une fois sur l'appareil (voir CLAUDE.md). Tout le reste de
// sudo continue d'exiger un mot de passe — on ne l'utilise jamais ici.
//
// La température par disque n'est pas incluse (phase 2, lecture SCSI sur /dev/sg0).

import Citadel
import Foundation
import NIO

enum DroboClientError: Error, LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Adresse, utilisateur ou mot de passe manquant — vérifie les Réglages (⌘,)."
        }
    }
}

actor DroboClient {
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

            let codeRaw = try await runEsa(client, "dnasStatus")
            status.statusCode = parseFirstInt64(codeRaw).map(Int.init)
            if let code = status.statusCode, let info = dnasStatusTable[code] {
                status.overallHealth = info.health
                status.healthLabel = info.label
            } else {
                status.overallHealth = .unknown
                status.healthLabel = "code inconnu"
            }

            let firmwareRaw = try await runEsa(client, "vxver")
            status.firmware = firmwareRaw.isEmpty ? nil : firmwareRaw

            let diskPackRaw = try await runEsa(client, "vxdiskpackid")
            status.diskPackId = diskPackRaw.isEmpty ? nil : diskPackRaw

            status.physicalTotalBytes = parseFirstInt64(try await runEsa(client, "vxphyscapacity"))
            status.physicalUsedBytes = parseFirstInt64(try await runEsa(client, "vxusedcapacity"))

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

    private func runEsa(_ client: SSHClient, _ subcommand: String) async throws -> String {
        let out = try await execString(client, "sudo /usr/bin/esa \(subcommand)", mergeStreams: true)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func execString(_ client: SSHClient, _ command: String, mergeStreams: Bool = false) async throws -> String {
        let buffer = try await client.executeCommand(command, mergeStreams: mergeStreams)
        return String(buffer: buffer)
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
