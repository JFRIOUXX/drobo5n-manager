"""Chargement de la configuration de connexion.

La config vit dans un fichier TOML (voir config.example.toml). Le mot de passe
peut aussi être fourni via la variable d'environnement DROBO5N_PASSWORD pour
éviter de l'écrire en clair sur disque.
"""
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path


DEFAULT_CONFIG_PATHS = [
    Path("config.toml"),
    Path.home() / ".config" / "drobo5n" / "config.toml",
]


@dataclass
class DroboConfig:
    host: str                      # IP ou nom mDNS du Drobo 5N
    port: int = 22
    username: str = "root"
    password: str | None = None    # sinon clé SSH
    key_filename: str | None = None
    connect_timeout: int = 10

    def resolved_password(self) -> str | None:
        return os.environ.get("DROBO5N_PASSWORD") or self.password


def _find_config(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.exists():
            raise FileNotFoundError(f"Fichier de config introuvable : {p}")
        return p
    for p in DEFAULT_CONFIG_PATHS:
        if p.exists():
            return p
    raise FileNotFoundError(
        "Aucune config trouvée. Copie config.example.toml vers config.toml "
        "et remplis l'adresse du Drobo."
    )


def load_config(path: str | None = None) -> DroboConfig:
    cfg_path = _find_config(path)
    with cfg_path.open("rb") as fh:
        data = tomllib.load(fh)
    drobo = data.get("drobo", data)  # accepte [drobo] ... ou racine plate
    return DroboConfig(
        host=drobo["host"],
        port=int(drobo.get("port", 22)),
        username=drobo.get("username", "root"),
        password=drobo.get("password"),
        key_filename=drobo.get("key_filename"),
        connect_timeout=int(drobo.get("connect_timeout", 10)),
    )
