// Modèle de données pour l'état du Drobo 5N2.
// Reflète drobo5n/model.py côté outil Python (même grille de codes dnasStatus).

import Foundation

enum Health {
    case good, warning, critical, unknown

    /// Ordre de gravité, pour retenir le pire de plusieurs états.
    var severity: Int {
        switch self {
        case .good: return 0
        case .unknown: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    func worst(_ other: Health) -> Health {
        other.severity > severity ? other : self
    }
}

struct DnasStatusInfo {
    let health: Health
    let label: String
}

// Grille des codes `esa dnasStatus`.
let dnasStatusTable: [Int: DnasStatusInfo] = [
    0:  DnasStatusInfo(health: .unknown,  label: "ESA absent / ne répond pas"),
    1:  DnasStatusInfo(health: .warning,  label: "pas encore monté"),
    2:  DnasStatusInfo(health: .warning,  label: "pas encore monté"),
    3:  DnasStatusInfo(health: .warning,  label: "montage en cours"),
    4:  DnasStatusInfo(health: .critical, label: "échec de montage"),
    5:  DnasStatusInfo(health: .good,     label: "fonctionnement normal"),
    6:  DnasStatusInfo(health: .good,     label: "fonctionnement normal"),
    7:  DnasStatusInfo(health: .warning,  label: "réparation en cours"),
    8:  DnasStatusInfo(health: .warning,  label: "réparation en cours"),
    9:  DnasStatusInfo(health: .warning,  label: "réparation en cours"),
    10: DnasStatusInfo(health: .critical, label: "erreur de configuration"),
    11: DnasStatusInfo(health: .critical, label: "erreur de domaine"),
    12: DnasStatusInfo(health: .critical, label: "erreur de domaine"),
    13: DnasStatusInfo(health: .critical, label: "erreur de domaine"),
    14: DnasStatusInfo(health: .critical, label: "erreur de configuration"),
    99: DnasStatusInfo(health: .good,     label: "iSCSI"),
]

struct DroboStatus {
    var host: String
    var firmware: String?
    var diskPackId: String?
    var statusCode: Int?
    var overallHealth: Health = .unknown
    var healthLabel: String?

    // Capacité physique réelle (esa vx*capacity) — pas les 64 To virtuels.
    var physicalTotalBytes: Int64?
    var physicalUsedBytes: Int64?

    // Capacité du volume telle que présentée (df /mnt/DroboFS) — inclut le thin-provisioning.
    var volumeTotalBytes: Int64?
    var volumeUsedBytes: Int64?

    var lastUpdated: Date = Date()

    /// Chemin sudo utilisé pour lire `esa` (règle NOPASSWD ou mot de passe).
    var sudoPath: SudoPath?

    var physicalFreeBytes: Int64? {
        guard let total = physicalTotalBytes, let used = physicalUsedBytes else { return nil }
        return total - used
    }

    var physicalUsedPct: Double? {
        guard let total = physicalTotalBytes, total > 0, let used = physicalUsedBytes else { return nil }
        return (Double(used) / Double(total) * 1000).rounded() / 10
    }

    var volumeFreeBytes: Int64? {
        guard let total = volumeTotalBytes, let used = volumeUsedBytes else { return nil }
        return total - used
    }
}

/// Parse le premier jeton numérique d'une sortie de commande (ex: "6\n" -> 6).
func parseFirstInt64(_ text: String) -> Int64? {
    guard let token = text.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
    return Int64(token)
}

/// Taille lisible, à la française (virgule décimale).
/// decimal=true -> To (base 1000, comme les fabricants) ; false -> Tio (base 1024).
func humanBytes(_ n: Int64?, decimal: Bool = true) -> String {
    guard let n else { return "—" }
    let step = decimal ? 1000.0 : 1024.0
    let units = decimal
        ? ["o", "Ko", "Mo", "Go", "To", "Po"]
        : ["o", "Kio", "Mio", "Gio", "Tio", "Pio"]
    var val = Double(n)
    var unit = units[0]
    for candidate in units {
        unit = candidate
        if val < step { break }
        if candidate != units.last { val /= step }
    }
    return formatFrench(val, decimals: 1) + " " + unit
}

/// Taille d'un disque telle qu'on la lit sur l'étiquette : « 8 To », « 256 Go ».
func diskSizeLabel(_ n: Int64) -> String {
    guard n > 0 else { return "—" }
    let gigabytes = Double(n) / 1e9
    if gigabytes >= 1000 {
        let terabytes = gigabytes / 1000
        let rounded = terabytes.rounded()
        // 8,0016 To -> « 8 To » ; 1,5 To reste « 1,5 To ».
        return formatFrench(abs(terabytes - rounded) < 0.06 ? rounded : terabytes,
                            decimals: abs(terabytes - rounded) < 0.06 ? 0 : 1) + " To"
    }
    return formatFrench(gigabytes.rounded(), decimals: 0) + " Go"
}

func formatFrench(_ value: Double, decimals: Int) -> String {
    String(format: "%.\(decimals)f", locale: Locale(identifier: "fr_CA"), value)
}
