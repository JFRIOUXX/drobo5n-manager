"""Structures de données pour l'état du Drobo 5N2.

Rempli par collect.py à partir des commandes `esa` (via SSH+sudo) et de `df`.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Health(str, Enum):
    GOOD = "good"
    WARNING = "warning"
    CRITICAL = "critical"
    UNKNOWN = "unknown"


# Grille des codes `esa dnasStatus` (extraite du firmware, getstatus.sh)
DNAS_STATUS = {
    0:  (Health.UNKNOWN,  "ESA absent / ne répond pas"),
    1:  (Health.WARNING,  "pas encore monté"),
    2:  (Health.WARNING,  "pas encore monté"),
    3:  (Health.WARNING,  "montage en cours"),
    4:  (Health.CRITICAL, "échec de montage"),
    5:  (Health.GOOD,     "fonctionnement normal"),
    6:  (Health.GOOD,     "fonctionnement normal"),
    7:  (Health.WARNING,  "réparation en cours"),
    8:  (Health.WARNING,  "réparation en cours"),
    9:  (Health.WARNING,  "réparation en cours"),
    10: (Health.CRITICAL, "erreur de configuration"),
    11: (Health.CRITICAL, "erreur de domaine"),
    12: (Health.CRITICAL, "erreur de domaine"),
    13: (Health.CRITICAL, "erreur de domaine"),
    14: (Health.CRITICAL, "erreur de configuration"),
    99: (Health.GOOD,     "iSCSI"),
}


@dataclass
class DroboStatus:
    host: str
    firmware: str | None = None          # esa vxver
    disk_pack_id: str | None = None      # esa vxdiskpackid
    status_code: int | None = None       # esa dnasStatus (brut)
    overall_health: Health = Health.UNKNOWN
    health_label: str | None = None      # texte lisible du code

    # Capacité PHYSIQUE réelle (esa vx*capacity) — la vraie, pas les 64 To virtuels
    physical_total_bytes: int | None = None
    physical_used_bytes: int | None = None

    # Capacité du VOLUME telle que présentée (df /mnt/DroboFS) — inclut le thin-prov.
    volume_total_bytes: int | None = None
    volume_used_bytes: int | None = None

    raw: dict[str, str] = field(default_factory=dict)

    # --- Physique ---
    @property
    def physical_free_bytes(self) -> int | None:
        if self.physical_total_bytes is None or self.physical_used_bytes is None:
            return None
        return self.physical_total_bytes - self.physical_used_bytes

    @property
    def physical_used_pct(self) -> float | None:
        if not self.physical_total_bytes or self.physical_used_bytes is None:
            return None
        return round(100 * self.physical_used_bytes / self.physical_total_bytes, 1)

    # --- Volume ---
    @property
    def volume_free_bytes(self) -> int | None:
        if self.volume_total_bytes is None or self.volume_used_bytes is None:
            return None
        return self.volume_total_bytes - self.volume_used_bytes
