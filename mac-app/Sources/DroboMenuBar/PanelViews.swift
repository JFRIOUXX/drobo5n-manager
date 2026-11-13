// Panneau affiché au clic sur « DR » dans la barre de menus.
//
// Idée directrice : le panneau ressemble au Drobo lui-même. La capacité reprend
// la rangée de dix voyants bleus du bas de l'appareil (un voyant = 10 %), et les
// baies sont dessinées comme sa façade noire, un voyant de couleur par disque.

import AppKit
import SwiftUI

// MARK: - Couleurs

enum PanelColor {
    static let ledGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let ledYellow = Color(red: 1.0, green: 0.78, blue: 0.04)
    static let ledRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let capacityBlue = Color(red: 0.16, green: 0.50, blue: 1.0)
    static let faceplateTop = Color(red: 0.115, green: 0.118, blue: 0.128)
    static let faceplateBottom = Color(red: 0.065, green: 0.067, blue: 0.075)
}

func healthColor(_ health: Health) -> Color {
    switch health {
    case .good: return PanelColor.ledGreen
    case .warning: return PanelColor.ledYellow
    case .critical: return PanelColor.ledRed
    case .unknown: return .gray
    }
}

func ledColor(_ led: BayLED) -> Color? {
    switch led {
    case .green: return PanelColor.ledGreen
    case .yellow, .other: return PanelColor.ledYellow
    case .red: return PanelColor.ledRed
    case .off, .empty: return nil
    }
}

// MARK: - Petits composants

/// Pastille d'état : la couleur est portée par le point, le texte reste lisible
/// dans les deux thèmes.
struct StatusPill: View {
    var health: Health
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(healthColor(health))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(healthColor(health).opacity(0.18)))
    }
}

/// Dix voyants, comme au bas du Drobo : chacun vaut 10 % de la capacité.
struct CapacityLights: View {
    var usedPct: Double
    var yellowThreshold: Double
    var redThreshold: Double

    private var color: Color {
        if usedPct >= redThreshold { return PanelColor.ledRed }
        if usedPct >= yellowThreshold { return PanelColor.ledYellow }
        return PanelColor.capacityBlue
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                let fraction = min(max(usedPct / 10 - Double(index), 0), 1)
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(color)
                                .frame(width: geo.size.width * fraction)
                        }
                        .clipShape(Capsule())
                }
                .frame(height: 7)
            }
        }
    }
}

/// Voyant d'une baie, avec son halo.
struct LEDLight: View {
    var led: BayLED

    var body: some View {
        if let color = ledColor(led) {
            Circle()
                .fill(color)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 3, height: 3)
                        .offset(x: -1.5, y: -1.5)
                )
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.85), radius: 4)
        } else {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 9, height: 9)
        }
    }
}

struct ErrorBadge: View {
    var count: Int

    var body: some View {
        Text("\(count) erreur\(count > 1 ? "s" : "")")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(PanelColor.ledYellow))
    }
}

// MARK: - Façade

/// Une baie de la façade : numéro, disque, voyant.
struct BayRow: View {
    var bay: DroboBay

    private var tooltip: String {
        if bay.isEmpty { return "Baie \(bay.slot + 1) : vide" }
        var parts = ["Baie \(bay.slot + 1) : \(bay.led.label)"]
        if !bay.serial.isEmpty { parts.append("n° de série \(bay.serial)") }
        if !bay.diskFirmware.isEmpty { parts.append("micrologiciel \(bay.diskFirmware)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(bay.slot + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(width: 12)

            if bay.isEmpty {
                Text("Baie vide")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.36))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bay.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.93))
                    Text("\(diskSizeLabel(bay.physicalBytes)) · \(bay.modelCode)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.52))
                }
            }

            Spacer(minLength: 6)

            if bay.errorCount > 0 {
                ErrorBadge(count: bay.errorCount)
            }
            LEDLight(led: bay.led)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(bay.isEmpty ? 0.03 : 0.065))
        )
        .help(tooltip)
    }
}

/// La baie mSATA de l'accélérateur, plus discrète.
struct AcceleratorRow: View {
    var bay: DroboBay

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.34))
                .frame(width: 12)

            if bay.isEmpty {
                Text("Accélérateur : aucun SSD")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.36))
            } else {
                (Text("Accélérateur")
                    .foregroundColor(Color.white.opacity(0.80))
                    + Text("  SSD \(diskSizeLabel(bay.physicalBytes))")
                    .foregroundColor(Color.white.opacity(0.50)))
                    .font(.system(size: 11))
            }

            Spacer(minLength: 6)

            if bay.errorCount > 0 {
                ErrorBadge(count: bay.errorCount)
            }
            LEDLight(led: bay.led)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .help(bay.isEmpty ? "Baie mSATA vide" : "\(bay.modelCode) · \(bay.led.label) · n° de série \(bay.serial)")
    }
}

/// La façade noire du Drobo : une rangée par baie.
struct Faceplate: View {
    var feed: DroboFeed

    var body: some View {
        VStack(spacing: 5) {
            ForEach(feed.bays) { bay in
                BayRow(bay: bay)
            }
            if let accelerator = feed.accelerator {
                AcceleratorRow(bay: accelerator)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(
                    colors: [PanelColor.faceplateTop, PanelColor.faceplateBottom],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

// MARK: - Boutons et lignes

struct PanelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.20 : 0.09))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

struct LabeledRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption)
        }
    }
}

// MARK: - Panneau

struct DroboMenuContent: View {
    @ObservedObject var viewModel: DroboViewModel
    @ObservedObject var settings: DroboSettings

    private var subtitle: String {
        [viewModel.modelName, viewModel.settings.host].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let detail = viewModel.healthDetail {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(healthColor(viewModel.overallHealth).opacity(0.16))
                    )
            }

            if viewModel.hasData {
                capacity
                if let feed = viewModel.feed {
                    Faceplate(feed: feed)
                }
                details
            } else if !viewModel.isUnreachable {
                Text("Lecture du Drobo…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            sourceErrors
            buttons
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(health: viewModel.overallHealth, title: viewModel.healthTitle)
        }
    }

    private var capacity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(viewModel.usedPct.map { formatFrench($0, decimals: 0) } ?? "—")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                Text("%")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(humanBytes(viewModel.usedBytes)) utilisés")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("\(humanBytes(viewModel.freeBytes)) libres sur \(humanBytes(viewModel.totalBytes))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            CapacityLights(
                usedPct: viewModel.usedPct ?? 0,
                yellowThreshold: viewModel.feed?.yellowThresholdPct ?? 85,
                redThreshold: viewModel.feed?.redThresholdPct ?? 95
            )
        }
    }

    private var details: some View {
        VStack(spacing: 4) {
            if let firmware = viewModel.firmware {
                LabeledRow(label: "Micrologiciel", value: firmware)
            }
            if let status = viewModel.status, status.volumeTotalBytes != nil {
                LabeledRow(
                    label: "Volume présenté",
                    value: "\(humanBytes(status.volumeUsedBytes)) sur \(humanBytes(status.volumeTotalBytes))"
                )
            }
            if let updated = viewModel.lastUpdated {
                LabeledRow(
                    label: "Mis à jour",
                    value: updated.formatted(date: .omitted, time: .standard)
                )
            }
        }
    }

    /// Erreurs de chaque source, en entier et sélectionnables pour les copier.
    @ViewBuilder
    private var sourceErrors: some View {
        if let error = viewModel.feedErrorMessage {
            sourceError(label: "Port 5000", message: error)
        }
        if let error = viewModel.lastErrorMessage {
            sourceError(label: "SSH", message: error)
        }
    }

    private func sourceError(label: String, message: String) -> some View {
        Text("\(label) : \(message)")
            .font(.system(size: 11))
            .foregroundStyle(viewModel.isUnreachable ? PanelColor.ledRed : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label(viewModel.isRefreshing ? "Lecture…" : "Rafraîchir", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)

            Spacer()

            Button("Réglages…") {
                SettingsWindowController.shared.show(settings: settings, viewModel: viewModel)
            }
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(PanelButtonStyle())
    }
}

// MARK: - Capture du panneau en image

/// Écrit le panneau en PNG (thème clair et thème sombre), sans passer par une
/// capture d'écran. Sert à vérifier le rendu et à illustrer le README :
///   DROBO_RENDER_PNG=/chemin/du/dossier DroboMenuBar.app/Contents/MacOS/DroboMenuBar
@MainActor
enum PanelSnapshot {
    static func write(viewModel: DroboViewModel, settings: DroboSettings, to directory: String) {
        let variants: [(name: String, scheme: ColorScheme, background: Color)] = [
            ("panneau-clair", .light, Color(white: 0.955)),
            ("panneau-sombre", .dark, Color(white: 0.145)),
        ]
        for variant in variants {
            let view = DroboMenuContent(viewModel: viewModel, settings: settings)
                .background(variant.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .environment(\.colorScheme, variant.scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(variant.name).png")
            try? png.write(to: url)
        }
    }
}
