# DroboMenuBar — build & run

App SwiftUI de barre de menu (macOS 13+) pour le Drobo 5N2 : pastille de santé
colorée + % utilisé dans la barre de menu, panneau détaillé au clic, réglages
via ⌘,. Réutilise le même modèle de collecte que l'outil Python
(`drobo5n/collect.py`) : `sudo esa {dnasStatus,vxver,vxphyscapacity,
vxusedcapacity,vxdiskpackid}` + `df -k`, via SSH.

## Pourquoi Swift Package Manager (et pas un `.xcodeproj`)

La machine n'a que les **Command Line Tools** installées (`xcodebuild`
indisponible, pas d'Xcode.app). Un projet Xcode ne peut donc pas être construit
ni ouvert ici. L'app est donc structurée comme un **Swift Package exécutable**,
qui se construit et se lance entièrement en ligne de commande :

```bash
cd mac-app
swift build            # première fois : télécharge Citadel + dépendances (NIOSSH, swift-crypto, BigInt…)
swift run               # compile si besoin, puis lance l'app
```

L'app apparaît dans la barre de menu (pas d'icône dans le Dock — c'est
volontaire, `NSApplication.shared.setActivationPolicy(.accessory)` dans
`MenuBarApp.swift`).

Si tu installes Xcode plus tard : ouvre simplement le dossier `mac-app/` dans
Xcode (`File > Open…` sur `Package.swift`) — Xcode reconnaît un Swift Package et
génère un schéma de build automatiquement. Tu peux aussi glisser ces fichiers
`.swift` dans un nouveau projet **App macOS** si tu préfères un vrai `.app`
signé avec un onglet Signing & Capabilities classique.

## App Sandbox

Ce build (`swift build`/`swift run`) produit un binaire **non signé** (ou signé
ad-hoc) : il n'est **pas sandboxé** par défaut — aucune capacité App Sandbox
n'est appliquée puisqu'il n'y a pas d'entitlements. C'est l'équivalent de
« Sandbox désactivé », adapté à un usage personnel sur ta seule machine.

## Prérequis côté Drobo

Les DroboApps **OpenSSH** et **sudo** installées, et le compte `admin` autorisé à
utiliser sudo avec son mot de passe (`admin ALL=(ALL) ALL`, régénéré par le Drobo à
chaque démarrage).

La règle `NOPASSWD` ciblée sur `/usr/bin/esa` (`PROGRESS.md`, MISE À JOUR 7) n'est
**plus nécessaire** depuis le 12 nov. 2026 : si elle est là, l'app s'en sert
(`sudo -n`) ; si elle a sauté après un redémarrage du Drobo, l'app donne elle-même
le mot de passe admin à sudo (`sudo -S`). Voir `PROGRESS.md`, MISE À JOUR 9.

En cas d'erreur : `tail /tmp/drobo-menubar.log` (une ligne par changement d'état).

## Premier lancement — saisir tes identifiants

1. Lance l'app (`swift run`, ou double-clique le binaire dans
   `.build/debug/DroboMenuBar` une fois construit).
2. Clique sur la pastille dans la barre de menu → **Réglages…** (ou ⌘, si la
   fenêtre a le focus).
3. Renseigne :
   - **Adresse** : `Drobo5NV2.local` (ou l'IP si le mDNS ne résout pas)
   - **Utilisateur** : `admin`
   - **Mot de passe** : ton mot de passe admin actuel
4. Clique **Tester la connexion**. Le mot de passe est stocké dans le
   **Trousseau macOS** (jamais en clair sur disque) dès que tu le tapes.

### À propos d'une éventuelle demande du Trousseau

Comme le binaire est reconstruit (donc re-signé ad-hoc) à chaque `swift build`,
macOS peut occasionnellement demander une autorisation d'accès au Trousseau
(« DroboMenuBar veut accéder à... ») après une recompilation. C'est normal pour
un binaire non signé par un compte développeur — clique **Toujours autoriser**.

## Un vrai bundle `.app`

`swift build` ne produit qu'un binaire Mach-O nu (pas de bundle). Pour avoir un
vrai `.app` double-cliquable (icône Finder, `Info.plist`, pas de fenêtre Terminal,
gérable depuis Réglages Système), il est empaqueté à la main — pas besoin
d'Xcode pour ça :

```bash
cd mac-app
swift build -c release

# dist/DroboMenuBar.app/Contents/Info.plist existe déjà et est versionné avec
# le code — seul le binaire à l'intérieur doit être rafraîchi.
mkdir -p dist/DroboMenuBar.app/Contents/MacOS   # le binaire n'est pas versionné
cp .build/release/DroboMenuBar dist/DroboMenuBar.app/Contents/MacOS/DroboMenuBar
codesign --force --deep --sign - dist/DroboMenuBar.app   # signature ad-hoc (pas de compte développeur)

rm -rf ~/Applications/DroboMenuBar.app
ditto dist/DroboMenuBar.app ~/Applications/DroboMenuBar.app
```

Le bundle vit dans `mac-app/dist/DroboMenuBar.app` (gabarit versionné avec le
code, `Info.plist` inclus) et la copie **installée** dans
`~/Applications/DroboMenuBar.app` (celle que macOS lance réellement — via le
LaunchAgent ou un double-clic).

**Gatekeeper** : `codesign` produit une signature *ad-hoc* (pas de compte
développeur Apple, usage perso). `spctl --assess` la rejette en théorie, mais
comme le bundle est construit **localement** (jamais téléchargé), il ne porte
aucun attribut de quarantaine (`xattr -l` vide) — testé avec `open
~/Applications/DroboMenuBar.app`, lancement direct sans blocage. Si un jour
macOS refuse de l'ouvrir (« développeur non identifié » — ça peut arriver si le
bundle transite par AirDrop/Zip/téléchargement et hérite d'un attribut de
quarantaine) : clic droit → Ouvrir, ou Réglages Système → Confidentialité et
sécurité → « Ouvrir quand même ».

## Lancement automatique à la connexion

Un LaunchAgent est installé à `~/Library/LaunchAgents/com.jf.drobo5n-manager.plist`,
qui pointe vers le binaire à l'intérieur du bundle installé :

```
~/Applications/DroboMenuBar.app/Contents/MacOS/DroboMenuBar
```

`RunAtLoad` est activé : l'app démarre à chaque connexion, sans action manuelle.

**Après une modification du code**, il faut reconstruire le binaire, régénérer
le bundle (étapes ci-dessus), puis relancer l'agent :

```bash
launchctl kickstart -k gui/501/com.jf.drobo5n-manager   # -k = redémarre le process existant
```

Logs de l'instance lancée par launchd : `/tmp/drobo-menubar.log`.

**Premier lancement après un remplacement du bundle** : macOS refuse une fois le
démarrage par launchd (`last exit reason = OS_REASON_CODESIGNING`, visible avec
`launchctl print gui/501/com.jf.drobo5n-manager`). Relancer la même commande
`kickstart` : le deuxième essai passe (constaté deux fois le 12 nov. 2026).

Pour désactiver le lancement automatique :

```bash
launchctl bootout gui/501/com.jf.drobo5n-manager
rm ~/Library/LaunchAgents/com.jf.drobo5n-manager.plist
```

Alternative visible dans l'UI : puisque c'est maintenant un vrai `.app`, tu peux
aussi le gérer depuis **Réglages Système → Général → Ouverture** (Login Items) —
glisse `~/Applications/DroboMenuBar.app` dans la liste, à la place du LaunchAgent
si tu préfères cette interface.

## Structure

```
mac-app/
├── Package.swift              # dépendance Citadel épinglée 0.11.x (macOS 12+ ; la 0.12+ exige macOS 14)
├── BUILD.md                   # ce fichier
├── dist/
│   └── DroboMenuBar.app/      # gabarit du bundle .app (Info.plist versionné, binaire régénéré à chaque build)
└── Sources/DroboMenuBar/
    ├── DroboCore.swift        # DroboStatus, Health, grille dnasStatus, tailles à la française
    ├── DroboFeed.swift        # port 5000 : lecture du flux, XML <ESATMUpdate>, baies et voyants
    ├── DroboClient.swift      # SSH (Citadel) : esa (sudo -n puis sudo -S) et df
    ├── Keychain.swift         # lecture/écriture du mot de passe dans le Trousseau
    ├── DroboSettings.swift    # DroboSettings + DroboViewModel (les deux sources, alertes, journal)
    ├── Notifier.swift         # notifications macOS
    ├── PanelViews.swift       # le panneau : capacité, façade, boutons, capture en PNG
    └── MenuBarApp.swift       # icône de la barre de menus, fenêtre Réglages, @main
```

Copie installée (celle réellement lancée) : `~/Applications/DroboMenuBar.app`.

## Variables d'environnement pour les essais

| Variable | Effet |
|---|---|
| `DROBO_RENDER_PNG=/dossier` | lit le Drobo une fois, écrit `panneau-clair.png` et `panneau-sombre.png` dans le dossier, puis quitte (c'est ainsi que sont faites les images de `docs/`) |
| `DROBO_NO_KEYCHAIN=1` | ne touche pas au Trousseau (pas de demande d'accès de macOS) ; la lecture SSH est alors sautée |
| `DROBO_SUDO_MODE=password` | force le chemin `sudo -S` (mot de passe), même si la règle NOPASSWD est présente |

## Hors périmètre

Température par disque : le Drobo 5N2 ne la publie pas (`<mTemperature>` vaut 0 sur
le port 5000 comme dans `nasd.log`). Resterait la lecture SCSI sur `/dev/sg0`
(`PROGRESS.md`, MISES À JOUR 4-5), sans garantie. L'état général et les voyants
servent de filet : une protection thermique du Drobo les ferait changer.
