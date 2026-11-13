"""Reconnaissance de l'appareil.

Le firmware du Drobo 5N n'est pas documenté publiquement. La toute première
étape utile, une fois SSH actif, est de DÉCOUVRIR où l'appareil expose son
état : quels démons tournent, quels fichiers/pseudo-fichiers contiennent la
capacité, la santé des disques, la température, l'état des baies, etc.

Ce module exécute une batterie de commandes EN LECTURE SEULE et écrit un
rapport complet. On analyse ensuite ce rapport (toi + ton Claude Code natif)
pour écrire des parseurs ciblés dans collect.py.

Aucune commande ici ne modifie l'appareil.
"""
from __future__ import annotations

import datetime as _dt
from pathlib import Path

from .ssh import DroboSSH

# Chaque entrée : (catégorie, commande). Toutes en lecture seule.
# Les chemins « candidats » sont des pistes basées sur la structure connue du
# firmware Drobo (Linux embarqué + écosystème DroboApps). Certaines renverront
# « No such file » — c'est normal et utile : ça cartographie ce qui existe.
RECON_COMMANDS: list[tuple[str, str]] = [
    # --- Identité / firmware -------------------------------------------------
    ("systeme", "uname -a"),
    ("systeme", "cat /etc/version 2>/dev/null; cat /etc/issue 2>/dev/null"),
    ("systeme", "cat /proc/version"),
    ("systeme", "uptime"),
    ("systeme", "busybox 2>&1 | head -20"),   # nombre d'utilitaires souvent = busybox
    # --- Stockage / capacité -------------------------------------------------
    ("stockage", "df -h"),
    ("stockage", "mount"),
    ("stockage", "cat /proc/mounts"),
    ("stockage", "ls -la /mnt 2>/dev/null"),
    ("stockage", "ls -la /mnt/DroboFS 2>/dev/null"),
    ("stockage", "ls -la /mnt/DroboFS/Shares 2>/dev/null"),
    ("stockage", "cat /proc/partitions"),
    ("stockage", "ls -la /dev/sd* 2>/dev/null"),
    # --- Disques / santé (pistes) -------------------------------------------
    ("disques", "cat /proc/scsi/scsi 2>/dev/null"),
    ("disques", "ls -la /sys/block 2>/dev/null"),
    ("disques", "dmesg | grep -i -E 'drobo|disk|sata|scsi' | tail -40"),
    # --- Démons / processus Drobo -------------------------------------------
    ("processus", "ps 2>/dev/null | head -60"),
    ("processus", "ps aux 2>/dev/null | head -60"),
    ("processus", "ls -la /etc/init.d 2>/dev/null"),
    # --- Chasse aux binaires/fichiers 'drobo' -------------------------------
    # Limité en profondeur pour rester rapide et non intrusif.
    ("chasse", "find / -maxdepth 4 -iname '*drobo*' 2>/dev/null | head -80"),
    ("chasse", "find /usr /sbin /bin -maxdepth 3 -type f 2>/dev/null | "
               "grep -i -E 'nas|drobo|mdm|esa|tdps|smart' | head -60"),
    ("chasse", "ls -la /tmp 2>/dev/null"),
    ("chasse", "ls -la /var 2>/dev/null"),
    # --- Réseau / découverte -------------------------------------------------
    ("reseau", "ifconfig 2>/dev/null; ip addr 2>/dev/null"),
    ("reseau", "netstat -ltnp 2>/dev/null | head -40"),  # ports d'écoute = API potentielle
]


def run_recon(session: DroboSSH) -> list[tuple[str, str, str]]:
    """Exécute toutes les commandes de recon. Retourne (categorie, commande, sortie)."""
    results: list[tuple[str, str, str]] = []
    for category, command in RECON_COMMANDS:
        res = session.run_safe(command, timeout=30)
        blob = res.stdout
        if res.stderr.strip():
            blob += f"\n[stderr] {res.stderr.strip()}"
        if res.exit_status not in (0, 1) and not blob.strip():
            blob += f"\n[exit={res.exit_status}]"
        results.append((category, command, blob.rstrip()))
    return results


def write_report(results: list[tuple[str, str, str]], out_dir: str = ".") -> Path:
    """Écrit un rapport Markdown horodaté et renvoie son chemin."""
    ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = Path(out_dir) / f"recon-{ts}.md"
    lines: list[str] = [
        f"# Rapport de reconnaissance Drobo 5N — {ts}",
        "",
        "Commandes en lecture seule. Analyse la sortie pour repérer les sources",
        "de statut (capacité, santé disques, température, baies) puis écris les",
        "parseurs ciblés dans `drobo5n/collect.py`.",
        "",
    ]
    current_cat = None
    for category, command, output in results:
        if category != current_cat:
            lines += ["", f"## {category}", ""]
            current_cat = category
        lines += [f"### `{command}`", "", "```", output or "(vide)", "```", ""]
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return out_path
