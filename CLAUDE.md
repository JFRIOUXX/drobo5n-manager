# Notes pour Claude Code (et pour quiconque reprend le projet)

Remplaçant du Drobo Dashboard pour un **Drobo 5N2**. Deux outils : l'app de barre
de menus `mac-app/` (SwiftUI, l'outil principal) et l'outil Python `drobo5n/`.
Le journal de la rétro-ingénierie est dans `PROGRESS.md` : le lire avant de
chercher une information sur l'appareil, les impasses y sont notées.

## Sources de données

- **Port 5000** (`mac-app/Sources/DroboMenuBar/DroboFeed.swift`) : XML
  `<ESATMUpdate>` diffusé sans mot de passe. État général, capacité, détail de
  chaque baie. C'est la source principale de l'app.
- **SSH + `sudo esa …`** (`DroboClient.swift`, `drobo5n/ssh.py`) :
  contre-vérification et volume présenté. `esa` exige root ; l'app essaie
  `sudo -n`, puis `sudo -S` avec le mot de passe.
- **Température** : le Drobo ne la publie pas (`<mTemperature>` vaut 0). Ne pas
  recommencer la recherche sans lire les MISES À JOUR 4, 5 et 9 de `PROGRESS.md`.

## Règles

- **Lecture seule sur l'appareil.** Ne jamais lancer `esa vxreboot`,
  `vxshutdown`, `update`, `vxcmd` ni `testDNASClearConfig`.
- Les secrets ne vont ni dans le dépôt ni dans les journaux : le mot de passe
  vit dans le Trousseau (app) ou dans `DROBO5N_PASSWORD` (Python).
  `config.toml` et `recon-*.md` sont ignorés par git.
- Un commit par cause.
- Interface et commentaires en français.

## Compiler, installer, vérifier

- `mac-app/install.sh` compile, signe (ad hoc), installe dans `~/Applications` et
  relance le LaunchAgent. Détails et pièges dans `mac-app/BUILD.md`.
- Journal de l'app : `/tmp/drobo-menubar.log` (une ligne par changement d'état).
- Rendu du panneau sans capture d'écran :
  `DROBO_RENDER_PNG=/dossier DroboMenuBar.app/Contents/MacOS/DroboMenuBar`
  écrit `panneau-clair.png` et `panneau-sombre.png`. Regarder ces images après
  toute modification de `PanelViews.swift`.
- Il n'y a pas de tests automatisés. Vérifier contre un vrai Drobo.

## Pistes

- Interface en anglais (les textes sont en dur, en français).
- Confirmer les codes de voyant autres que 3 et 128, et l'ordre physique des baies.
- Historique de la capacité dans le temps.
