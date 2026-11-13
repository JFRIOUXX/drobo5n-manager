# Projet Drobo 5N2 — Journal de progression

> Récap de tout ce qu'on a découvert, pour reprendre sans repartir de zéro si la
> conversation est perdue. Dernière mise à jour : 12 novembre 2026 (voir MISES À JOUR 9 et 10).

## Objectif

Remplacer le Drobo Dashboard (cassé sur Mac récents / macOS 27) par un outil
maison pour gérer/surveiller le **Drobo 5N2**. Approche retenue : SSH vers
l'appareil (Linux embarqué), lecture de l'état, puis affichage. Squelette Python
déjà livré (projet `drobo5n-manager`, voir README.md et CLAUDE.md).

## L'appareil

- Modèle : **Drobo 5N2** (network/NAS). Nom Bonjour sur le réseau : **`Drobo5NV2`**.
- Ancien iMac : fait encore tourner le Drobo Dashboard officiel (utile pour créer
  des comptes, redémarrer proprement, etc.).

## ✅ Accès SSH — CE QUI MARCHE (acquis)

1. SSH activé en installant l'app **OpenSSH** de DroboPorts : on dépose le fichier
   `openssh.tgz` dans le partage réseau **`DroboApps`** (Finder → Cmd+K →
   `smb://Drobo5NV2.local`), puis **redémarrage** du Drobo (fait via le Dashboard
   sur l'iMac). Au reboot, OpenSSH s'installe et démarre sur le port 22.
2. Découverte de l'appareil : `dns-sd -B _ssh._tcp` → nom `Drobo5NV2`.
3. Connexion : **`ssh admin@Drobo5NV2.local`**
   - Compte : **`admin`** en **minuscules** (le `Admin` majuscule ne marche pas —
     casse sensible). `root` est **désactivé** par défaut.
   - Mot de passe : celui du compte admin du Drobo (défini dans le Dashboard).
   - Le WARNING « post-quantum » à la connexion est sans conséquence (vieille
     version d'OpenSSH côté Drobo). On l'ignore.

## ✅ Ce qu'on sait lire (acquis)

**Capacité** — via `df -h` :

```
/dev/sda1   63.9T   7.8T   56.1T   12%   /mnt/DroboFS
```

- Volume protégé monté sur **`/mnt/DroboFS`**, périphérique **`/dev/sda1`**.
- 63,9 To = taille *virtuelle* max que le Drobo affiche toujours (thin
  provisioning) ; l'important, l'espace **utilisé (7,8 To)**, est réel.
- Le parseur `_parse_df_bytes` du projet cible déjà « le plus gros FS non-tmpfs » →
  fonctionne ici. On peut le fixer explicitement sur `/mnt/DroboFS`.

## ⏳ Ce qui reste à décoder : santé + température par disque

**Contrainte clé découverte** : `ls /sys/block` ne montre qu'**un seul disque,
`sda`**. Le Drobo cache les disques physiques derrière son RAID maison
(BeyondRAID) et ne présente que le volume agrégé. → **Impossible de lire la
santé/température de chaque disque via SMART** comme sur un NAS normal. Cette info
ne peut venir que de l'**interface de gestion interne du Drobo (ESA)**.

**Outils internes trouvés** (via `ls /usr/sbin /usr/bin /sbin /bin | grep -i …`) :

- `getstatus.sh` → renvoie juste `0` sans argument (code « OK » ? attend des args ?)
- **`esactl`** → **contrôle seulement** : `esactl [flush|goingdown|shutdown] /dev/sdX`.
  Envoie des ordres (vider les disques / arrêt). **Ne lit pas** le statut.
- `esa` (symlink) → l'agent ESA (probablement le daemon qui parle au matériel).
- `esa_color.sh` → gestion des LED.
- `LXdiskGraph.sh`, `LXdiskHistory.sh` → graphes/historique disques (à explorer).
- `cnid_dbd`, `DroboApps.sh`, `DroboAppsValidate.sh`, `DroboAppsAnalytics.sh`.

## 🔜 Prochaines étapes (là où on en est)

1. **Lire le contenu des scripts** pour trouver la vraie source de statut — un
   script shell révèle d'où il tire ses données. Priorité :
   ```
   cat $(which getstatus.sh)
   cat $(which LXdiskHistory.sh)
   ```
   Chercher : un fichier de statut, un socket, ou un appel à `esa`/`/dev/sda`.
2. Explorer l'agent **`esa`** (probable lecteur d'état de l'enceinte : disques,
   températures, LED).
3. Chercher un fichier de statut écrit par le daemon : `ls -la /tmp /var/log`.
4. **Plan B** si rien de lisible directement : reproduire la requête SCSI de
   **drobo-utils** vers `/dev/sda` (le protocole Drobo), exécutée *sur* le Drobo
   (c'est là que vit `/dev/sda`). C'est la méthode qui donne l'état complet du
   « disk pack », mais plus de travail.
5. Une fois la source trouvée → remplir `parse_bays()` / `parse_health()` dans
   `drobo5n/collect.py`, puis valider avec `status` et `serve`.

## ⚠️ Sécurité / prudence

- Changer le mot de passe SSH si jamais on active root.
- `esactl shutdown/goingdown` sont des commandes **actives** (arrêt) — ne pas les
  lancer par curiosité. On reste en **lecture seule** tant que l'état n'est pas
  solide.

---

## MISE À JOUR — on a trouvé l'interface de statut (et le dernier verrou)

En lisant le code de `getstatus.sh`, on a trouvé LA commande de gestion :

```
esa dnasStatus     # renvoie un code d'état global du NAS
```

**Grille des codes d'état** (extraite des commentaires de `getstatus.sh`) :

| Code    | Signification                          |
|---------|----------------------------------------|
| 0       | ESA absent / ne répond pas             |
| 1-4     | pas encore monté / échec de montage    |
| **5, 6**| **fonctionnement normal ✅**            |
| 7-9     | réparation en cours                    |
| 10, 14  | erreurs de configuration               |
| 11-13   | erreurs de domaine                     |
| 99      | iSCSI                                  |

→ `esa` est LE programme qui parle au matériel ; `dnasStatus` n'est qu'une de ses
sous-commandes (il y en a d'autres pour disques/température/LED, à lister une fois
qu'on aura les droits).

**Dernier verrou : il faut root.** `esa dnasStatus` en tant que `admin` renvoie
`DebugInterface: failed to connect socket: Permission denied` — `esa` passe par un
socket réservé à root.

**La solution (à faire) : installer l'app `sudo` de DroboPorts.**
1. Télécharger `sudo` (v1.8.11p2 pour Drobo5N) depuis
   https://www.droboports.com/app-repository/sudo/
2. Déposer le `.tgz` dans le partage **DroboApps** (comme OpenSSH).
3. **Redémarrer** le Drobo (via le Dashboard sur l'iMac).
4. Par défaut, l'app autorise `sudo` **sans mot de passe** pour tous les comptes.
5. Ensuite : `sudo esa dnasStatus` → devrait renvoyer 5 ou 6 (normal).
6. Puis lister les sous-commandes : `sudo esa` (ou `sudo esa help`) pour trouver
   celles qui donnent la santé/température par disque → remplir `collect.py`.

**Prochaine action concrète = installer l'app sudo, rebooter, puis `sudo esa`.**

---

## MISE À JOUR 2 — root OK, interface ESA cartographiée

- App **sudo** installée. `sudo esa dnasStatus` → **6** (= fonctionnement normal). ✅
  (sudo demande le mot de passe du compte `admin` la 1re fois, puis le mémorise
  quelques minutes.)

### Commandes `esa` utilisables (lecture seule) — À UTILISER pour l'outil

| Commande                 | Donne                                              |
|--------------------------|----------------------------------------------------|
| `sudo esa dnasStatus`    | code de santé global (5/6 = normal — voir grille)  |
| `sudo esa vxver`         | version du firmware                                |
| `sudo esa vxphyscapacity`| capacité **physique réelle** (pas les 64 To virt.) |
| `sudo esa vxusedcapacity`| capacité utilisée                                  |
| `sudo esa vxdiskpackid`  | identifiant du disk pack                           |
| `sudo esa vxcapacity`    | capacité dispo + utilisée (combiné)                |

### ⛔ Commandes actives/destructrices — NE JAMAIS lancer par curiosité
`esa vxreboot`, `esa vxshutdown`, `esa update`, `esa vxcmd`, `testDNASClearConfig`.

### Infos par disque (santé/température) — présentes mais plus profondes
Le binaire `esa`/`nasd` gère un protocole ESA complet avec, PAR SLOT :
`mSlotNumber, mSledName, mDiskManufacturer, mDiskModel, mDiskFwRev, mSerial,
mDiskType (HDD/SSD), mDiskState, mStatus, mTemperature, mPhysicalCapacity,
Slot lifeRemaining, Slot rotationalSpeed, Slot Error count` + `Number Of Slots`.
Il existe même une commande interne **`eCmdGetAllDevicesStatusXML`** qui sort TOUT
en XML (c'est ce que le Dashboard récupère par le réseau).
→ MAIS ces infos par slot ne sont pas exposées par une sous-commande `esa` simple :
le daemon `nasd` les lit (via `doPollESAUpdate`, `getLUNsInfoEx`) et les pousse au
Dashboard par le réseau (agents Sled/NetAgent). Pistes phase 2 pour les récupérer :
1. Regarder `/var/log/nasd.log` (peut contenir des dumps de statut slot).
2. Explorer `esa vxcmd` (passe-commande générique — **à manipuler avec prudence**,
   en lecture seulement).
3. Reproduire la requête réseau que fait le Dashboard vers `nasd` (protocole
   Sled/NetAgent) — plus de travail, mais donne le XML complet par disque.

### MVP réaliste (ce qu'on affiche tout de suite)
Santé globale (`dnasStatus`) + capacité réelle (`vxphyscapacity`/`vxusedcapacity`)
+ firmware (`vxver`) + capacité du volume (`df`). La température/santé par disque =
phase 2.

**Prochaine action = tester les commandes de lecture `esa vx*` pour voir leur
format de sortie, puis les brancher dans `collect.py`.**

---

## MISE À JOUR 3 — formats de sortie confirmés (prêt à coder)

Sortie réelle des commandes (chaque commande = une valeur, facile à parser) :

```
sudo esa vxver          → 4.3.1 8.126.117497        (version  build)
sudo esa vxphyscapacity → 27798829793280            (octets → ~27,8 To physiques)
sudo esa vxusedcapacity → 8641437265920             (octets → ~8,64 To utilisés)
sudo esa vxdiskpackid   → 0123456789ABCDEF          (hex)
sudo esa dnasStatus     → 6                          (5/6 = normal)
```

**Parsing** : `vxphyscapacity`/`vxusedcapacity` = entier en **octets** (diviser par
1000⁴ pour des To « disque », ou 1024⁴ pour des Tio). `vxver` = « version build » à
splitter sur l'espace. `dnasStatus` = code entier → mapper via la grille.

**Détail sudo pour un outil automatisé** : chaque exec SSH est une session neuve,
donc `sudo` redemande le mot de passe. Solution : `sudo -S esa …` en fournissant le
mot de passe admin sur stdin (l'outil a déjà ce mot de passe via sa config), ou
configurer un NOPASSWD ciblé pour `esa`.

### État = MVP entièrement débloqué ✅
On peut coder le collecteur : SSH `admin@Drobo5NV2.local` → `sudo -S esa {dnasStatus,
vxver, vxphyscapacity, vxusedcapacity, vxdiskpackid}` + `df` → afficher. Reste en
option/phase 2 : température & santé par disque (voir MISE À JOUR 2).

---

## MISE À JOUR 4 — chasse à la température par disque (phase 2)

Investigué. Résultats :
- `/var/log/nasd.log` contient des blocs XML `<mSlotsExp>` avec `<mSlotNumber>` +
  `<mTemperature>` PAR baie, et `<mSlotCountExp>6</mSlotCountExp>` (5 baies + 1 slot
  accélérateur mSATA). **MAIS** ces blocs datent du boot et toutes les temps = 0.
- `sudo grep '<mTemperature>[1-9]' /var/log/nasd.log` → **vide** : aucune température
  vivante n'est jamais journalisée.
- `LXdiskGraph.sh` / `LXdiskHistory.sh` : ne font que grapher les I/O Linux de
  `/sys/class/block/sd*` (gnuplot) → pas de température disque.
- Aucune sous-commande `esa` simple n'expose l'info par slot.

**Conclusion** : les temps/états par disque vivent dans la mémoire de `nasd` et ne
sortent que vers le Dashboard par le réseau. Trois voies possibles :

- **A — Expérience rapide (incertaine, réversible)** : monter le niveau de debug de
  sled/nasd (`/etc/sledd_debug.lvl`) pour voir si `nasd` se met à logger les temps
  vivantes, puis grep le journal. Faible effort, résultat non garanti.
- **B — Voie robuste (vrai dev)** : lire directement la page SCSI « slot info » de
  l'ESA sur `/dev/sda` (le protocole que fait déjà **drobo-utils**). Exécuté SUR le
  Drobo. Donne les temps/états/modèles/séries par disque de façon fiable. Nécessite
  un outil SCSI sur le Drobo (Python+sg, `sg_raw`, ou un petit binaire) → à mettre en
  place, mais c'est LA bonne source.
- **C — Protocole réseau du Dashboard** : capturer/rejouer la requête
  `eCmdGetAllDevicesStatusXML` que le Dashboard envoie à `nasd` (socket `/tmp/nasd.sock`
  ou réseau). Donne le XML complet identique au Dashboard, mais reverse le plus lourd.

### Recommandation
Livrer le **MVP maintenant** (santé + capacité réelle + firmware + nb de baies, tout
via `esa`, déjà plus riche que l'info de base du Dashboard), et traiter la température
par disque comme un **sous-projet phase 2** (voie B = la plus fiable).

---

## MISE À JOUR 5 — reconnaissance pour la voie B (SCSI direct)

Voie B retenue (température = priorité : le Drobo est dans un endroit
chaud). Reconnaissance de l'outillage :

- `/tmp/nasd/` : que des `*.conf.scratch` + `initialized` + `shares/`. **Pas** de
  fichier d'état vivant.
- `update_diags.sh` : ne fait que **concaténer des configs** (liste des fichiers à
  inclure dans un diag). Ne récolte pas l'état live. Dead end.
- **`/dev/sg0` EXISTE** (SCSI generic) → SCSI brut possible. ✅
- **Pas de** `python`/`python2`/`python3`/`perl`/`sg_raw`/`sdparm` sur le système base.
- DroboApps installées : **apache, crashplan, java8, openssh, sudo, transmission**.

### Protocole SCSI de référence (drobo-utils, vieux modèles)
MODE SENSE 10 (opcode `0x5a`), page vendeur `0x3a`, sous-pages :
- sous-page `0x09` = status ; sous-page `0x03` = slot info.
- CDB : `struct.pack(">BBBBBBBHB", 0x5a,0,0x3a,sub_page,0,0,0,paklen,0)`.
- Slot record (ancien) : `'HBQQB32s16sL'` = slotID, physCap, mgdCap, LED, fab(32s),
  modèle(16s), … (⚠️ **pas de température** dans l'ancien format — le 5N2 a une
  version ESA plus récente qui, elle, contient `mTemperature`. La page/offset exacts
  du 5N2 sont à trouver par sondage.)
- Transport : SG_IO ioctl (via `fcntl`/`struct` en Python).

### Plan voie B
1. (en cours) Tester `sudo esa vxcmd` (usage) — raccourci éventuel via l'outil Drobo.
2. Sinon : installer une **DroboApp Python** (drop tgz + reboot, comme sudo), puis
   je fournis un **script de sondage SG_IO en lecture seule** sur `/dev/sg0` qui vide
   en hexa les sous-pages `0x3a` → je repère les octets de température (valeurs ~20-45
   près des structures de slot) en corrélant avec les baies connues.
3. Une fois la page/offset température identifiés → parser propre dans `collect.py`.

---

## MISE À JOUR 6 — MVP LIVRÉ ✅

Le long-shot debug (niveau `/etc/sledd_debug.lvl`) n'a rien donné (journal figé à
771 lignes, temps toujours à 0). Décision : livrer le MVP, température par disque =
phase 2 (voie B SCSI, quand on voudra).

**L'outil `drobo5n-manager` est maintenant fonctionnel.** Il se connecte en SSH
(`admin@Drobo5NV2.local`), lance `sudo -S esa …` (mot de passe fourni via stdin) et
affiche :
- santé globale (`dnasStatus` → code + libellé + couleur),
- capacité **physique réelle** (`vxphyscapacity`/`vxusedcapacity`),
- capacité du volume présenté (`df /mnt/DroboFS`),
- firmware (`vxver`), disk pack id (`vxdiskpackid`).

Pour l'utiliser (dans ton Claude Code natif, sur le Mac) :
```
pip install -r requirements.txt
cp config.example.toml config.toml   # host=Drobo5NV2.local, username=admin
export DROBO5N_PASSWORD="…"           # mot de passe du compte admin
python -m drobo5n status              # ou : serve (dashboard web), ping, recon
```

Testé : parsing des vraies valeurs OK (santé 6=OK, 8,6/27,8 To physiques, 31 %).

### Filet de sécurité surchauffe
Pas de température chiffrée par disque, MAIS `dnasStatus` passe à un code d'erreur si
le Drobo détecte une surchauffe critique (protection thermique intégrée). Le MVP
surveille ce code → alerte en cas de vrai problème.

### Reste en phase 2 (si un jour on veut les °C par disque)
Voie B (SCSI) : installer une DroboApp Python → script SG_IO lecture seule sur
`/dev/sg0` → décoder la page ESA slot-info (champ `mTemperature`). Tout est balisé
dans les MISES À JOUR 4-5 ci-dessus.

---

## MISE À JOUR 7 — sudo NOPASSWD pour `esa` (posé, avec une réserve)

Prérequis posé pour l'app macOS (voir MISE À JOUR 8) : `sudo esa …` sans mot de passe.

**Piège découvert** : le `/etc/sudoers` du DroboApps sudo package référence
`#includedir /mnt/DroboFS/Shares/DroboApps/sudo/etc/sudoers.d` dans son propre
fichier `.../sudo/etc/sudoers`, mais ce **n'est pas le fichier actif**. Le vrai
`/etc/sudoers` chargé par le `sudo` en cours d'exécution inclut plutôt
`#includedir /tmp/sudo/sudoers.d`, où vit déjà `admin` (accès `(ALL) ALL` avec
mot de passe, posé manuellement lors de l'activation SSH initiale). C'est donc
**dans ce fichier-là** (`/tmp/sudo/sudoers.d/admin`) qu'il faut ajouter la règle
ciblée, pas dans le dossier DroboApps.

Contenu actuel de `/tmp/sudo/sudoers.d/admin` :
```
admin ALL=(ALL) ALL
admin ALL=(root) NOPASSWD: /usr/bin/esa
```
Vérifié : `sudo -n /usr/bin/esa dnasStatus` répond sans mot de passe ; `sudo -n true`
continue d'exiger le mot de passe (pas d'ouverture générale).

**⚠️ Réserve : `/tmp` est presque certainement un tmpfs.** Cette règle NOPASSWD
(et l'accès sudo général d'`admin` lui-même) risque de **disparaître au prochain
reboot du Drobo**. Pas encore identifié quel mécanisme (script de démarrage de la
DroboApp `sudo` ?) régénère `/tmp/sudo/sudoers.d/admin` au boot — si un reboot
casse l'accès NOPASSWD, il faudra soit republier la règle à la main via SSH, soit
retrouver et modifier le script de démarrage qui peuple ce dossier pour qu'il
inclue la ligne NOPASSWD dès l'origine.

---

## MISE À JOUR 8 — app macOS native « DroboMenuBar » (SwiftUI, MenuBarExtra)

Livrée dans `mac-app/` : app de barre de menu (macOS 13+), pastille de santé
colorée + % utilisé, panneau détaillé au clic (santé, barre de capacité physique
réelle, firmware, disk pack id, volume présenté), rafraîchissement auto 30 s +
bouton, fenêtre Réglages (⌘,) pour adresse/utilisateur/mot de passe.

- SSH via **Citadel** (Swift), épinglé en `0.11.0..<0.12.0` : la série 0.12+
  exige macOS 14, incompatible avec la cible macOS 13+ demandée.
- Mot de passe dans le **Trousseau** (jamais en clair), adresse/utilisateur dans
  `UserDefaults`.
- Aucun mot de passe sudo à gérer côté app : elle appelle directement
  `sudo /usr/bin/esa …`, qui passe grâce à la règle NOPASSWD de la MISE À JOUR 7.
  Si un reboot du Drobo a fait sauter cette règle, l'app remontera une erreur de
  connexion SSH normale (mauvais mdp/timeout) plutôt qu'un blocage sudo silencieux
  — à surveiller.
- Construite en Swift Package Manager (pas de Xcode.app installé sur la machine,
  seulement les Command Line Tools) : `swift build` / `swift run` depuis `mac-app/`.
  Voir `mac-app/BUILD.md`.
- Testé : compile proprement, tourne sans crash, hérite l'icône dans la barre de
  menu. Le test de connexion réel (identifiants + `sudo -n esa …` sans mot de
  passe) reste à confirmer manuellement par l'utilisateur.

---

## MISE À JOUR 9 — connexion confirmée, réglages corrigés, lancement auto

**Connexion testée et validée par l'utilisateur** (Réglages → identifiants →
« Tester la connexion » → OK).

**Bug trouvé et corrigé** : le bouton « Réglages… » ne faisait rien. La technique
standard pré-macOS 14 (scène SwiftUI `Settings { }` + envoi de l'action
`showSettingsWindow:`) suppose une vraie barre de menus pour établir la chaîne de
responders — une app `.accessory` pilotée uniquement par un `MenuBarExtra` en
style `.window` n'en a pas, donc l'action ne trouve jamais sa cible. Remplacé par
une fenêtre **AppKit gérée directement** (`SettingsWindowController` dans
`MenuBarApp.swift`, `NSWindow` + `NSHostingController`), déclenchée par le bouton.
Plus fiable, et de toute façon ⌘, n'était pas atteignable sans barre de menus.

**Label de la barre de menu** : remplacé le `%` utilisé par le texte fixe **« DR »**
à côté de la pastille de santé (préférence utilisateur — le % reste visible dans
le panneau détaillé au clic).

**Lancement automatique à la connexion** : ajouté via un **LaunchAgent**
(`~/Library/LaunchAgents/com.jf.drobo5n-manager.plist`, `RunAtLoad`), pas via
`SMAppService` (nécessite un bundle signé par un compte développeur pour
l'auto-enregistrement propre). Détails dans `mac-app/BUILD.md`.

---

## MISE À JOUR 10 — vrai bundle `.app`

Toujours sans Xcode installé, mais un vrai bundle macOS a été construit à la
main (pas besoin d'Xcode pour ça) :

- `mac-app/dist/DroboMenuBar.app/` : `Info.plist` (bundle id
  `com.jf.drobo5n-manager`, `LSUIElement=true` pour rester une pure app de barre
  de menu sans icône Dock, `LSMinimumSystemVersion=13.0`) + le binaire release
  dans `Contents/MacOS/`.
- Signé **ad-hoc** (`codesign --force --deep --sign -`) — pas de compte
  développeur Apple, usage perso. `spctl --assess` le rejette (attendu pour du
  non-notarié), mais comme le bundle est construit **localement** (jamais
  téléchargé), il ne porte aucun attribut de quarantaine → testé avec
  `open DroboMenuBar.app` (= équivalent d'un double-clic Finder), lancement
  direct sans blocage Gatekeeper.
- Installé dans `~/Applications/DroboMenuBar.app` — un vrai `.app` listé dans
  Finder/Spotlight, plus un binaire nu planqué dans `.build/`.
- Le LaunchAgent (MISE À JOUR 9) a été mis à jour pour pointer vers
  `~/Applications/DroboMenuBar.app/Contents/MacOS/DroboMenuBar` au lieu du
  binaire brut dans `.build/release/` — plus robuste (le chemin ne bouge plus
  au gré des rebuilds) et gérable aussi depuis Réglages Système → Général →
  Ouverture (Login Items) si préféré au LaunchAgent.
- Procédure de reconstruction (code modifié → nouveau binaire → régénérer le
  bundle → relancer l'agent) documentée dans `mac-app/BUILD.md`.

---

## MISE À JOUR 9 — panne du 12 nov. 2026 : l'app ne dépend plus de la règle NOPASSWD

**Symptôme** : panneau « Erreur : The operation couldn't be completed… » (texte
tronqué). **Cause** : le Drobo a redémarré le 3 oct. 2026 ; `/tmp/sudo/sudoers.d/admin`
a été régénéré avec la seule ligne `admin ALL=(ALL) ALL`, donc `sudo -n /usr/bin/esa`
répondait « a password is required » (code 1), ce que Citadel remonte en
`SSHClient.CommandFailed`. La réserve de la MISE À JOUR 7 s'est réalisée. Ce n'était
ni macOS 27.2 ni la permission Réseau local (pistes écartées ce soir-là).

**Réparation immédiate** : ligne `admin ALL=(root) NOPASSWD: /usr/bin/esa` reposée à
la main (copie de l'ancien fichier dans `/tmp/admin.sudoers.bak` sur le Drobo). Elle
sautera encore au prochain redémarrage du Drobo, sans conséquence désormais.

**Changement dans l'app** (`DroboClient.swift`) : toutes les sous-commandes `esa`
partent en une seule commande SSH, par deux chemins essayés dans l'ordre :
1. `sudo -n` (règle NOPASSWD présente) : aucun mot de passe envoyé à sudo ;
2. sinon `sudo -S -p ''` : l'app donne le mot de passe admin (celui du Trousseau) à
   sudo sur son entrée standard, par here-document à délimiteur cité.
Vérifié le 12 nov. : chemin 1 au lancement normal, chemin 2 avec le crochet de test
`DROBO_SUDO_MODE=password` (variable d'environnement). Le chemin 2 n'a pas été testé
en retirant réellement la règle sur le Drobo.

**Diagnostic plus rapide la prochaine fois** :
- l'app écrit une ligne dans `/tmp/drobo-menubar.log` à chaque changement d'état
  (`OK — état 6, sudo par …` ou `ERREUR — …`) : `tail /tmp/drobo-menubar.log` ;
- le panneau et les Réglages affichent maintenant l'erreur en entier (`describeError`).

**Piège macOS vu à l'installation** : la première relance par launchd juste après le
remplacement du bundle a été refusée une fois (`OS_REASON_CODESIGNING`, Launch
Constraint Violation) ; les relances suivantes sont passées. Si l'app ne démarre pas
après une réinstallation : relancer `launchctl kickstart -k gui/501/com.jf.drobo5n-manager`.

**Découverte : flux d'état sur le port 5000, sans mot de passe.** `nc Drobo5NV2.local 5000`
renvoie un en-tête `DRINASD` puis le XML `<ESATMUpdate>` complet (celui du Dashboard) :
nom, firmware, `mStatus`, capacités, et par baie (`mSlotsExp`, 6 entrées dont le slot
mSATA) `mStatus`, `mErrorCount`, `mDiskState`, `mMake`, `mDiskFwRev`, `mSerial`,
`mPhysicalCapacity`, `SSDLifeRemaining`, `RotationalSpeed`. **`mTemperature` vaut 0 pour
toutes les baies** : pas de °C par cette voie non plus. C'est en revanche la source
la plus simple pour un état par disque (erreurs, modèle, série) sans SSH ni sudo.


---

## MISE À JOUR 10 — état par baie, panneau redessiné, alertes (12 nov. 2026)

**Source** : `DroboFeed.swift` lit un document `<ESATMUpdate>` sur le port 5000
(Network.framework, délai de 8 s), puis ferme. En-tête de 16 octets : `DRINASD\0`,
`01 01 00 00`, puis la longueur du XML sur 4 octets gros-boutiste (0x1BF0 = 7152 ici).
Le Drobo répète le document tant que la connexion reste ouverte.

**Ce que le flux donne** (valeurs du 12 nov.) : `mName`, `mModel` (« Drobo 5N »),
`mVersion`, `DNASStatus` (6), capacités protégées, seuils `mYellowThreshold` /
`mRedThreshold` (8500 / 9500 = 85 % / 95 %), et 6 entrées sous `mSlotsExp` :
5 baies (la première vide, deux ST8000VN004, deux ST12000VN0008) et la baie mSATA
(256 Go, `mDiskType` 4).

**Voyants** (`mStatus` d'une baie) : 3 = vert et 128 = baie vide sont **observés**.
0, 1, 2 = éteint, rouge, jaune suivent la table de drobo-utils, **non observés** ici.
Tout autre code s'affiche « état N » en jaune. `mDiskState` : 16 pour les disques
du groupe, 32 pour l'accélérateur, 0 pour la baie vide (sens non confirmé, non affiché).

**App** : le flux passe en premier pour l'état général, la capacité et le firmware ;
SSH + `esa` reste en contre-vérification et pour le volume présenté (`df`). Si une
source tombe, l'autre suffit ; les deux erreurs s'affichent en entier.
- Panneau (`PanelViews.swift`) : capacité sur dix voyants, façade noire avec une
  rangée par baie, accélérateur, pastille d'état. Numéro de série en infobulle.
- Barre de menus : la pastille est une image non « template » (une forme SwiftUI
  n'y est pas dessinée, d'où l'ancienne icône sans couleur).
- Alertes (`Notifier.swift`, `checkAlerts`) : notification quand la liste des
  constats change, au retour à la normale, ou après 4 lectures ratées de suite.
  **Non vérifié en conditions réelles** (aucun voyant n'a changé) : essayer avec
  Réglages → « Envoyer une notification d'essai ».
- Numérotation : `mSlotNumber` 0 à 4 est affiché « baie 1 à 5 ». La correspondance
  avec l'ordre physique (haut/bas) reste à confirmer en regardant la façade.
