// App SwiftUI barre de menu (MenuBarExtra, macOS 13+) pour le Drobo 5N2.

import AppKit
import SwiftUI

func healthColor(_ health: Health) -> Color {
    switch health {
    case .good: return .green
    case .warning: return .orange
    case .critical: return .red
    case .unknown: return .gray
    }
}

func healthLine(_ status: DroboStatus) -> String {
    let label: String
    switch status.overallHealth {
    case .good: label = "OK"
    case .warning: label = "ATTENTION"
    case .critical: label = "CRITIQUE"
    case .unknown: label = "inconnu"
    }
    var text = label
    if let detail = status.healthLabel { text += " — \(detail)" }
    if let code = status.statusCode { text += " (code \(code))" }
    return text
}

/// Pastille + % affichés dans la barre de menu elle-même.
struct DroboMenuBarLabel: View {
    @ObservedObject var viewModel: DroboViewModel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthColor(viewModel.status?.overallHealth ?? .unknown))
                .frame(width: 8, height: 8)
            Text("DR")
        }
    }
}

struct CapacityBar: View {
    var usedPct: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25))
                RoundedRectangle(cornerRadius: 4).fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(usedPct, 0), 100)) / 100)
            }
        }
        .frame(height: 8)
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

/// Panneau détaillé affiché au clic sur l'icône de la barre de menu.
struct DroboMenuContent: View {
    @ObservedObject var viewModel: DroboViewModel
    @ObservedObject var settings: DroboSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Drobo 5N2").font(.headline)
                Spacer()
                Text(viewModel.settings.host).font(.caption).foregroundStyle(.secondary)
            }

            if let status = viewModel.status {
                HStack(spacing: 6) {
                    Circle().fill(healthColor(status.overallHealth)).frame(width: 10, height: 10)
                    Text(healthLine(status)).font(.subheadline)
                }

                Divider()

                Text("Capacité physique réelle").font(.caption).foregroundStyle(.secondary)
                CapacityBar(usedPct: status.physicalUsedPct ?? 0, color: healthColor(status.overallHealth))
                HStack {
                    Text("\(humanBytes(status.physicalUsedBytes)) / \(humanBytes(status.physicalTotalBytes))")
                        .font(.caption)
                    if let pct = status.physicalUsedPct {
                        Text("(\(String(format: "%.1f", pct))%)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("libre \(humanBytes(status.physicalFreeBytes))").font(.caption).foregroundStyle(.secondary)
                }

                Divider()

                Text("Volume présenté (thin-provisioning)").font(.caption).foregroundStyle(.secondary)
                Text("\(humanBytes(status.volumeUsedBytes)) / \(humanBytes(status.volumeTotalBytes))")
                    .font(.caption)

                Divider()

                LabeledRow(label: "Firmware", value: status.firmware ?? "—")
                LabeledRow(label: "Disk pack", value: status.diskPackId ?? "—")

                Text("Mis à jour à \(status.lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)

                if let error = viewModel.lastErrorMessage {
                    Text("Dernière erreur : \(error)")
                        .font(.caption2).foregroundStyle(.red)
                }
            } else if let error = viewModel.lastErrorMessage {
                Text("Erreur : \(error)")
                    .font(.callout).foregroundStyle(.red)
            } else {
                Text("Chargement…").foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(viewModel.isRefreshing ? "Rafraîchissement…" : "Rafraîchir") {
                    Task { await viewModel.refresh() }
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

            Text("Température par disque : non incluse (phase 2).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: DroboSettings
    @ObservedObject var viewModel: DroboViewModel
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("Connexion Drobo 5N2") {
                TextField("Adresse (IP ou nom .local)", text: $settings.host)
                TextField("Utilisateur SSH", text: $settings.username)
                SecureField("Mot de passe", text: $settings.password)
            }

            Section {
                HStack {
                    Button(isTesting ? "Test en cours…" : "Tester la connexion") {
                        Task {
                            isTesting = true
                            await viewModel.refresh()
                            isTesting = false
                            testResult = viewModel.lastErrorMessage ?? "Connexion OK ✓"
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("Connexion OK") ? .green : .red)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Fenêtre Réglages gérée directement en AppKit.
///
/// La technique standard pré-macOS 14 (scène `Settings { }` + envoi de l'action
/// `showSettingsWindow:`) suppose une vraie barre de menus avec un item "Réglages…"
/// pour établir la chaîne de responders. Une app `.accessory` pilotée uniquement
/// par un `MenuBarExtra` en style `.window` n'a pas cette chaîne : l'action ne
/// trouve jamais sa cible. On gère donc la fenêtre nous-mêmes.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(settings: DroboSettings, viewModel: DroboViewModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, viewModel: viewModel)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Réglages Drobo 5N2"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@main
struct DroboMenuBarApp: App {
    @StateObject private var settings: DroboSettings
    @StateObject private var viewModel: DroboViewModel

    init() {
        let sharedSettings = DroboSettings()
        _settings = StateObject(wrappedValue: sharedSettings)
        _viewModel = StateObject(wrappedValue: DroboViewModel(settings: sharedSettings))
        // Pas d'icône dans le Dock : c'est une app de barre de menu uniquement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            DroboMenuContent(viewModel: viewModel, settings: settings)
        } label: {
            DroboMenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
