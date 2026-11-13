// App SwiftUI barre de menu (MenuBarExtra, macOS 13+) pour le Drobo 5N2.
// Le panneau lui-même est dans PanelViews.swift.

import AppKit
import SwiftUI

/// Icône de la barre de menus : une pastille de couleur et « DR ».
///
/// Une forme SwiftUI (Circle) n'est pas dessinée dans une barre de menus : seuls
/// le texte et les images le sont. La pastille est donc une petite image, marquée
/// non « template » pour garder sa couleur.
struct DroboMenuBarLabel: View {
    @ObservedObject var viewModel: DroboViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.dot(for: viewModel.overallHealth))
            Text("DR")
        }
    }

    static func dot(for health: Health) -> NSImage {
        let color: NSColor
        switch health {
        case .good: color = .systemGreen
        case .warning: color = .systemYellow
        case .critical: color = .systemRed
        case .unknown: color = .systemGray
        }
        let size = NSSize(width: 9, height: 9)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
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
                VStack(alignment: .leading, spacing: 6) {
                    Button(isTesting ? "Test en cours…" : "Tester la connexion") {
                        Task {
                            isTesting = true
                            await viewModel.refresh()
                            isTesting = false
                            let errors = [
                                viewModel.feedErrorMessage.map { "Port 5000 : \($0)" },
                                viewModel.lastErrorMessage.map { "SSH : \($0)" },
                            ].compactMap { $0 }
                            testResult = errors.isEmpty ? "Connexion OK ✓" : errors.joined(separator: "\n")
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("Connexion OK") ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 400)
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
        let sharedViewModel = DroboViewModel(settings: sharedSettings)
        _settings = StateObject(wrappedValue: sharedSettings)
        _viewModel = StateObject(wrappedValue: sharedViewModel)
        // Pas d'icône dans le Dock : c'est une app de barre de menu uniquement.
        NSApplication.shared.setActivationPolicy(.accessory)

        // Mode capture : écrit le panneau en PNG puis quitte (voir PanelSnapshot).
        if let directory = ProcessInfo.processInfo.environment["DROBO_RENDER_PNG"], !directory.isEmpty {
            Task { @MainActor in
                await sharedViewModel.refresh()
                PanelSnapshot.write(viewModel: sharedViewModel, settings: sharedSettings, to: directory)
                exit(0)
            }
        }
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
