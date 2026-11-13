# drobo5n-manager

Outil de gestion / monitoring d'un **Drobo 5N** via SSH — un remplacement du
Drobo Dashboard, qui ne fonctionne plus proprement sur les Mac récents.

Le Drobo 5N tourne sur du **Linux embarqué**. Plutôt que de reverse-engineerer
le protocole binaire propriétaire du Dashboard, cet outil ouvre une session SSH
sur l'appareil et lit son état directement. **100 % compatible macOS 27** :
c'est du Python pur, aucune extension noyau, aucune notarisation, rien qui
dépende de la version de macOS.

> ✅ **État actuel : MVP fonctionnel.** Affiche la santé globale, la capacité
> physique réelle, l'espace du volume, la version du firmware et l'ID du disk
> pack — le tout via SSH + `sudo esa …`. La température **par disque** n'est pas
> incluse (voir `PROGRESS.md`, phase 2 : elle nécessite une lecture SCSI ESA sur
> `/dev/sg0`). La santé globale `dnasStatus` sert de filet anti-surchauffe : une
> surchauffe critique la ferait passer à un code d'erreur.

---

## Prérequis

1. **Python 3.11+** sur ton Mac (nécessaire pour `tomllib`).
   Le plus simple : `brew install python@3.12` — ou `uv` si tu l'utilises déjà.
2. **Accès SSH activé sur le Drobo 5N.** Ce n'est pas actif d'origine :
   - Installe l'app **OpenSSH** depuis DroboApps / DroboPorts, **ou**
   - Active l'accès root documenté par la communauté (voir *Sources* plus bas).
   - Vérifie ensuite : `ssh root@<ip-du-drobo>` doit t'ouvrir un shell.

## Installation

```bash
cd drobo5n-manager
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp config.example.toml config.toml
# édite config.toml : mets l'IP de ton 5N
```

## Utilisation

```bash
# 1. Vérifie que la connexion SSH passe
python -m drobo5n ping

# 2. Affiche l'état complet (santé, capacité physique réelle, firmware, disk pack)
python -m drobo5n status
python -m drobo5n status --json

# 3. Mini dashboard web local (auto-refresh, ouvre-le dans le navigateur)
python -m drobo5n serve      # http://127.0.0.1:8765

# (optionnel) Reconnaissance : re-dumpe l'état brut de l'appareil dans un rapport
python -m drobo5n recon
```

> Le mot de passe du compte `admin` sert à la fois pour SSH et pour `sudo esa …`.
> Mets-le dans `config.toml` ou, mieux, via `export DROBO5N_PASSWORD="…"`.

Le mot de passe peut être passé sans l'écrire dans le fichier :

```bash
export DROBO5N_PASSWORD="..."
python -m drobo5n status
```

---

## La prochaine étape : la recon

Le firmware du 5N n'est pas documenté publiquement, donc on ne sait pas encore
quelle commande donne la santé/température des disques. `recon` lance une
batterie de commandes **en lecture seule** (identité, montages, `/proc`,
processus, chasse aux binaires `*drobo*`, ports en écoute…) et dump tout dans un
rapport Markdown.

Une fois le rapport en main : repère les sources de statut, puis remplis les
parseurs `parse_bays()` / `parse_health()` dans `drobo5n/collect.py`. Le fichier
`CLAUDE.md` donne le plan détaillé pour faire ça avec ton Claude Code natif.

## Structure

```
drobo5n-manager/
├── README.md            ← tu es ici
├── CLAUDE.md            ← plan de reprise pour Claude Code natif
├── requirements.txt
├── config.example.toml
└── drobo5n/
    ├── config.py        # chargement config TOML / env
    ├── ssh.py           # session SSH (paramiko), commandes lecture seule
    ├── recon.py         # sweep de découverte -> rapport
    ├── model.py         # DroboStatus, DiskBay, Health
    ├── collect.py       # collecte + parsing  ← À COMPLÉTER après recon
    ├── format.py        # affichage texte
    ├── web.py           # mini dashboard Flask
    └── cli.py           # entrypoint (ping / recon / status / serve)
```

## Sécurité

- `config.toml` et les rapports `recon-*.md` sont git-ignorés (ils peuvent
  contenir IP internes / secrets).
- Toutes les commandes de la phase actuelle sont en **lecture seule**. Les
  actions d'écriture (config, mise à jour) seront ajoutées explicitement et avec
  confirmation, une fois le protocole de lecture solide.

## Sources / références

- drobo-utils (fork Python 3) : https://github.com/n3gwg/drobo-utils
- drobo-utils original : https://github.com/petersilva/drobo-utils
- OpenSSH pour Drobo (DroboPorts) : https://www.droboports.com/app-repository/openssh/
- Accès SSH au 5N : http://blog.chisel.pm/2014/03/how-to-ssh-onto-drobo-5n-from-microsoft.html
