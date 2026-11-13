"""Collecte de l'état du Drobo 5N2 via SSH.

Sources (toutes en lecture) découvertes par reconnaissance sur l'appareil :
  - `sudo esa dnasStatus`     -> code de santé global (5/6 = normal)
  - `sudo esa vxver`          -> version du firmware ("4.3.1 8.126.117497")
  - `sudo esa vxphyscapacity` -> capacité physique totale (octets)
  - `sudo esa vxusedcapacity` -> capacité physique utilisée (octets)
  - `sudo esa vxdiskpackid`   -> identifiant du disk pack (hex)
  - `df -k`                   -> capacité du volume /mnt/DroboFS (présentée)

La température/santé PAR DISQUE n'est pas incluse (voir PROGRESS.md, phase 2 :
elle nécessite de lire une page SCSI ESA sur /dev/sg0). La santé globale
`dnasStatus` reste un filet de sécurité : une surchauffe critique la ferait
passer à un code d'erreur.
"""
from __future__ import annotations

from .model import DNAS_STATUS, DroboStatus, Health
from .ssh import DroboSSH


def _to_int(text: str) -> int | None:
    text = (text or "").strip().split()[0] if text.strip() else ""
    try:
        return int(text)
    except (ValueError, IndexError):
        return None


def _parse_volume_df(session: DroboSSH) -> tuple[int | None, int | None]:
    """Capacité totale/utilisée du volume Drobo via `df -k` (point de montage /mnt/DroboFS)."""
    res = session.run_safe("df -k")
    if not res.ok:
        return None, None
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 6 and parts[5] == "/mnt/DroboFS" and parts[0].startswith("/dev/"):
            try:
                return int(parts[1]) * 1024, int(parts[2]) * 1024
            except ValueError:
                return None, None
    return None, None


def collect_status(session: DroboSSH) -> DroboStatus:
    status = DroboStatus(host=session.config.host)

    # Santé globale
    code_raw = session.esa("dnasStatus")
    status.raw["dnasStatus"] = code_raw
    code = _to_int(code_raw)
    status.status_code = code
    if code is not None and code in DNAS_STATUS:
        status.overall_health, status.health_label = DNAS_STATUS[code]
    else:
        status.overall_health, status.health_label = Health.UNKNOWN, "code inconnu"

    # Firmware
    ver = session.esa("vxver")
    status.raw["vxver"] = ver
    status.firmware = ver or None

    # Disk pack id
    dpid = session.esa("vxdiskpackid")
    status.raw["vxdiskpackid"] = dpid
    status.disk_pack_id = dpid or None

    # Capacité physique réelle
    status.physical_total_bytes = _to_int(session.esa("vxphyscapacity"))
    status.physical_used_bytes = _to_int(session.esa("vxusedcapacity"))

    # Capacité du volume (df)
    vt, vu = _parse_volume_df(session)
    status.volume_total_bytes = vt
    status.volume_used_bytes = vu

    return status
