// Flux d'état que le Drobo diffuse sur le port TCP 5000, sans authentification.
//
// C'est le flux que lisait le Drobo Dashboard : un en-tête binaire de 16 octets
// (« DRINASD\0 », puis la longueur du XML sur les 4 derniers octets), suivi d'un
// document XML <ESATMUpdate>, répété à intervalles réguliers. On en lit un seul,
// puis on ferme la connexion.
//
// Ce qu'on y trouve : nom, modèle, firmware, code DNASStatus, capacités, et pour
// chaque baie le voyant, le compteur d'erreurs, le modèle, le numéro de série et
// la taille du disque. Le champ <mTemperature> existe mais vaut 0 pour toutes
// les baies sur le 5N2 (voir PROGRESS.md, MISE À JOUR 9) : pas de °C ici.

import Foundation
import Network

/// Voyant d'une baie, tel que le Drobo l'allume en façade.
///
/// Codes confirmés par observation sur le 5N2 : 3 (vert) et 128 (baie vide).
/// Les codes 0, 1 et 2 suivent la table du projet libre drobo-utils (éteint,
/// rouge, jaune) et n'ont pas été observés ici. Tout autre code est affiché tel
/// quel, comme un état à surveiller.
enum BayLED: Equatable {
    case green
    case yellow
    case red
    case off
    case empty
    case other(Int)

    init(code: Int) {
        switch code {
        case 3: self = .green
        case 2: self = .yellow
        case 1: self = .red
        case 0: self = .off
        case 0x80: self = .empty
        default: self = .other(code)
        }
    }

    /// Description courte, pour l'infobulle et les alertes.
    var label: String {
        switch self {
        case .green: return "voyant vert"
        case .yellow: return "voyant jaune"
        case .red: return "voyant rouge"
        case .off: return "voyant éteint"
        case .empty: return "baie vide"
        case .other(let code): return "état \(code)"
        }
    }

    /// Gravité que ce voyant impose à l'état général.
    var health: Health {
        switch self {
        case .green, .empty: return .good
        case .red: return .critical
        case .yellow, .off, .other: return .warning
        }
    }
}

struct DroboBay: Identifiable, Equatable {
    let slot: Int
    var led: BayLED
    var errorCount: Int
    /// 0 = disque dur, 4 = SSD mSATA (valeurs observées).
    var diskType: Int
    /// Marque et modèle bruts, par exemple « SEAGATE  ST8000VN004-3CP1 ».
    var make: String
    var diskFirmware: String
    var serial: String
    var physicalBytes: Int64
    var ssdLifeRemaining: Int?

    var id: Int { slot }
    var isEmpty: Bool { led == .empty || physicalBytes == 0 }
    var isSSD: Bool { diskType == 4 }

    /// Nom lisible du disque : « Seagate IronWolf », « Seagate ST4000DM004 »…
    var displayName: String {
        let tokens = make.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = tokens.first else { return "Disque" }
        let vendorLike = first.allSatisfy { $0.isLetter } && tokens.count >= 2
        let vendor = vendorLike ? first.capitalized : nil
        let model = modelCode
        if vendor == "Seagate", model.contains("VN") {
            return "Seagate IronWolf"
        }
        return [vendor, model].compactMap { $0 }.joined(separator: " ")
    }

    /// Référence du modèle sans le suffixe d'usine : « ST8000VN004 ».
    var modelCode: String {
        let tokens = make.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = tokens.first else { return "" }
        let vendorLike = first.allSatisfy { $0.isLetter } && tokens.count >= 2
        let raw = vendorLike ? tokens[1] : first
        return raw.split(separator: "-").first.map(String.init) ?? raw
    }
}

struct DroboFeed: Equatable {
    var name: String?
    var model: String?
    var firmware: String?
    var dnasStatus: Int?
    var totalBytes: Int64?
    var usedBytes: Int64?
    var freeBytes: Int64?
    /// Seuils d'alerte de remplissage, en pourcentage (85 et 95 d'origine).
    var yellowThresholdPct: Double?
    var redThresholdPct: Double?
    var slots: [DroboBay] = []
    var receivedAt = Date()

    /// Sur le 5N/5N2, la dernière des 6 entrées est la baie mSATA de l'accélérateur.
    private var hasAcceleratorSlot: Bool { slots.count == 6 }

    /// Les baies de disques, dans l'ordre de la façade.
    var bays: [DroboBay] {
        hasAcceleratorSlot ? Array(slots.dropLast()) : slots
    }

    /// La baie mSATA (accélérateur), si le modèle en a une.
    var accelerator: DroboBay? {
        hasAcceleratorSlot ? slots.last : nil
    }

    var usedPct: Double? {
        guard let total = totalBytes, total > 0, let used = usedBytes else { return nil }
        return Double(used) / Double(total) * 100
    }
}

enum DroboFeedError: Error, LocalizedError {
    case badAddress
    case timeout
    case incomplete
    case connection(String)
    case badXML(String)

    var errorDescription: String? {
        switch self {
        case .badAddress:
            return "Adresse du Drobo invalide."
        case .timeout:
            return "Le Drobo n'a rien envoyé sur le port 5000 dans le délai."
        case .incomplete:
            return "Le Drobo a fermé la connexion du port 5000 avant la fin de l'état."
        case .connection(let detail):
            return "Port 5000 injoignable : \(detail)"
        case .badXML(let detail):
            return "État du port 5000 illisible : \(detail)"
        }
    }
}

enum DroboFeedReader {
    static func fetch(host: String, port: UInt16 = 5000, timeout: TimeInterval = 8) async throws -> DroboFeed {
        let xml = try await readOneUpdate(host: host, port: port, timeout: timeout)
        return try DroboFeedParser.parse(xml)
    }

    /// État partagé entre les rappels réseau ; n'est touché que sur la file série.
    private final class Box: @unchecked Sendable {
        var buffer = Data()
        var done = false
    }

    private static func readOneUpdate(host: String, port: UInt16, timeout: TimeInterval) async throws -> Data {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DroboFeedError.badAddress
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "com.jf.drobo5n-manager.feed")
        let box = Box()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            func finish(_ result: Result<Data, Error>) {
                guard !box.done else { return }
                box.done = true
                connection.cancel()
                continuation.resume(with: result)
            }

            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, isComplete, error in
                    if let chunk { box.buffer.append(chunk) }
                    if let xml = extractUpdate(from: box.buffer) {
                        finish(.success(xml))
                    } else if let error {
                        finish(.failure(DroboFeedError.connection(error.localizedDescription)))
                    } else if isComplete || box.buffer.count > 2_000_000 {
                        finish(.failure(DroboFeedError.incomplete))
                    } else {
                        receive()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    receive()
                case .failed(let error), .waiting(let error):
                    finish(.failure(DroboFeedError.connection(error.localizedDescription)))
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(DroboFeedError.timeout))
            }
            connection.start(queue: queue)
        }
    }

    /// Premier document <ESATMUpdate> complet du tampon, sans l'en-tête binaire.
    private static func extractUpdate(from buffer: Data) -> Data? {
        guard let start = buffer.range(of: Data("<ESATMUpdate>".utf8)),
              let end = buffer.range(of: Data("</ESATMUpdate>".utf8), in: start.upperBound..<buffer.endIndex)
        else { return nil }
        return buffer.subdata(in: start.lowerBound..<end.upperBound)
    }
}

/// Lit le XML <ESATMUpdate> : champs de premier niveau, et une entrée par baie
/// sous <mSlotsExp><n0>…</n0><n1>…</n1>…</mSlotsExp>.
final class DroboFeedParser: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var text = ""
    private var top: [String: String] = [:]
    private var slots: [[String: String]] = []
    private var currentSlot: [String: String]?

    static func parse(_ data: Data) throws -> DroboFeed {
        let delegate = DroboFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DroboFeedError.badXML(parser.parserError?.localizedDescription ?? "erreur inconnue")
        }
        return delegate.build()
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        path.append(elementName)
        text = ""
        if path.count == 3, path[1] == "mSlotsExp" {
            currentSlot = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count == 2 {
            if top[elementName] == nil { top[elementName] = value }
        } else if path.count == 4, path[1] == "mSlotsExp" {
            currentSlot?[elementName] = value
        } else if path.count == 3, path[1] == "mSlotsExp", let slot = currentSlot {
            slots.append(slot)
            currentSlot = nil
        }
        path.removeLast()
        text = ""
    }

    private func build() -> DroboFeed {
        func text(_ key: String) -> String? {
            top[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        func int64(_ key: String) -> Int64? { top[key].flatMap { Int64($0) } }
        // Les seuils sont en centièmes de pour cent (8500 = 85 %).
        func threshold(_ key: String) -> Double? { top[key].flatMap { Double($0) }.map { $0 / 100 } }

        var feed = DroboFeed()
        feed.name = text("mName") ?? text("mDroboName")
        feed.model = text("mModel")
        // « 4.3.1-8.126.117497 » -> « 4.3.1 »
        feed.firmware = text("mVersion").map { String($0.split(separator: "-").first ?? Substring($0)) }
        feed.dnasStatus = top["DNASStatus"].flatMap { Int($0) }
        feed.totalBytes = int64("mTotalCapacityProtected")
        feed.usedBytes = int64("mUsedCapacityProtected")
        feed.freeBytes = int64("mFreeCapacityProtected")
        feed.yellowThresholdPct = threshold("mYellowThreshold")
        feed.redThresholdPct = threshold("mRedThreshold")
        feed.slots = slots.enumerated().map { index, fields in
            DroboBay(
                slot: fields["mSlotNumber"].flatMap { Int($0) } ?? index,
                led: BayLED(code: fields["mStatus"].flatMap { Int($0) } ?? -1),
                errorCount: fields["mErrorCount"].flatMap { Int($0) } ?? 0,
                diskType: fields["mDiskType"].flatMap { Int($0) } ?? 0,
                make: fields["mMake"] ?? "",
                diskFirmware: fields["mDiskFwRev"] ?? "",
                serial: fields["mSerial"] ?? "",
                physicalBytes: fields["mPhysicalCapacity"].flatMap { Int64($0) } ?? 0,
                ssdLifeRemaining: fields["SSDLifeRemaining"].flatMap { Int($0) }
            )
        }
        .sorted { $0.slot < $1.slot }
        return feed
    }
}
