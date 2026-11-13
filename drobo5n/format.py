"""Utilitaires d'affichage."""
from __future__ import annotations

from .model import DroboStatus, Health

_HEALTH_LABEL = {
    Health.GOOD: "OK",
    Health.WARNING: "ATTENTION",
    Health.CRITICAL: "CRITIQUE",
    Health.UNKNOWN: "inconnu",
}


def human_bytes(n: int | None, decimal: bool = True) -> str:
    """Taille lisible. decimal=True -> To (base 1000, comme les fabricants) ;
    decimal=False -> Tio (base 1024)."""
    if n is None:
        return "—"
    step = 1000.0 if decimal else 1024.0
    units = ["o", "Ko", "Mo", "Go", "To", "Po"] if decimal else ["o", "Kio", "Mio", "Gio", "Tio", "Pio"]
    val = float(n)
    for unit in units:
        if val < step:
            return f"{val:.1f} {unit}"
        val /= step
    return f"{val:.1f} {units[-1]}"


def render_status_text(s: DroboStatus) -> str:
    health = _HEALTH_LABEL.get(s.overall_health, "—")
    lines = [
        f"Drobo 5N2 @ {s.host}",
        f"  Santé      : {health}"
        + (f" — {s.health_label}" if s.health_label else "")
        + (f" (code {s.status_code})" if s.status_code is not None else ""),
        f"  Firmware   : {s.firmware or '—'}",
        f"  Disk pack  : {s.disk_pack_id or '—'}",
        "",
        "  Capacité physique (réelle) :",
        f"    {human_bytes(s.physical_used_bytes)} / {human_bytes(s.physical_total_bytes)}"
        + (f"  ({s.physical_used_pct}%)" if s.physical_used_pct is not None else ""),
        f"    Libre : {human_bytes(s.physical_free_bytes)}",
        "",
        "  Volume présenté (thin-provisioning) :",
        f"    {human_bytes(s.volume_used_bytes)} / {human_bytes(s.volume_total_bytes)}",
        "",
        "  (température par disque : non incluse — voir PROGRESS.md, phase 2)",
    ]
    return "\n".join(lines)
