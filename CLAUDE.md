# Notes de reprise — pour Claude Code

Contexte : remplacer le Drobo Dashboard (cassé sur Mac récents / macOS 27) pour
un **Drobo 5N**. Approche : SSH vers l'appareil (Linux embarqué), lecture de
l'état, puis actions de gestion. Cible = **macOS 27**, outil de bureau. Pas
d'app iOS pour l'instant.

## Où on en est

Squelette complet et fonctionnel pour : connexion (`ping`), reconnaissance
(`recon`), capacité (`status`), dashboard web (`serve`). Ce qui reste à décoder :
santé + température + modèle/série **par baie**, et la santé globale.

## Plan des prochaines étapes (dans l'ordre)

1. **Faire passer la connexion.** Activer SSH sur le 5N (OpenSSH DroboApps ou
   accès root communautaire), puis `python -m drobo5n ping`.

2. **Lancer la recon.** `python -m drobo5n recon` → produit `recon-*.md`.
   Lis ce rapport. On cherche : la commande/le fichier qui expose l'état des
   disques. Pistes à examiner en priorité dans la sortie :
   - le point de montage exact du volume protégé (section `stockage` → `df`,
     `mount`) — corriger `_parse_df_bytes` dans `collect.py` pour cibler ce FS
     précis plutôt que « le plus gros ».
   - les binaires trouvés par la « chasse » (`*drobo*`, `nasd`, `mdm`, `esa`,
     `tdps`, `smart`…) — en tester un en lecture (`--help`, sortie sans args)
     pour voir s'il crache un statut.
   - les ports en écoute (section `reseau` → `netstat`) : si un démon expose une
     API TCP locale, ça peut être une source plus propre que du scraping.
   - `dmesg` et `/sys/block/sd*/device/` pour modèle/série des disques.

3. **Remplir les parseurs.** Dans `drobo5n/collect.py` :
   - `parse_bays()` : slot → présent/modèle/série/capacité/santé/température.
   - `parse_health()` : santé globale (mapper vers l'enum `Health`).
   Garder chaque sortie brute dans `status.raw[...]` pour tracer d'où vient
   chaque valeur.

4. **Valider l'affichage.** `status`, `status --json`, puis `serve` (le
   dashboard lit le même `collect_status`).

5. **Actions de gestion (phase 2, prudence).** Seulement après une lecture
   fiable. Commencer par des actions réversibles/inertes. Chaque commande
   d'écriture : confirmation explicite + log. Ne PAS déclencher de dialogue
   destructif sans garde-fou.

## Conventions

- Tout ce qui touche l'appareil passe par `DroboSSH` (`ssh.py`). Phase actuelle
  = lecture seule ; `run_safe()` n'exception jamais.
- Compat macOS 27 : rester en Python pur, pas d'extension noyau, pas de
  dépendance à des binaires Apple. Python 3.11+ (tomllib).
- Secrets/rapports git-ignorés.

## Évolution possible (plus tard)

- Enveloppe **app barre de menus native** (SwiftUI, ou rumps/py2app en Python) :
  réutiliser tel quel `collect_status()` comme coeur.
- Rebrancher le **4 baies DAS** via `drobo-utils` (SCSI) tournant dans un Docker
  sur la machine où il est branché — module séparé, même modèle de données.
```
