"""Enveloppe de connexion SSH vers le Drobo 5N.

Toutes les commandes exécutées ici sont, par convention, en LECTURE SEULE tant
qu'on est en phase de reconnaissance. Les actions de gestion (écriture) seront
ajoutées explicitement plus tard, avec confirmation.
"""
from __future__ import annotations

import shlex
from contextlib import contextmanager
from dataclasses import dataclass

import paramiko

from .config import DroboConfig


@dataclass
class CommandResult:
    command: str
    stdout: str
    stderr: str
    exit_status: int

    @property
    def ok(self) -> bool:
        return self.exit_status == 0

    @property
    def text(self) -> str:
        return self.stdout.strip()


class DroboSSH:
    """Session SSH réutilisable vers l'appareil."""

    def __init__(self, config: DroboConfig):
        self.config = config
        self._client: paramiko.SSHClient | None = None

    def connect(self) -> None:
        client = paramiko.SSHClient()
        # Le 5N a une clé d'hôte auto-signée qui change au reflash du firmware.
        # AutoAdd est acceptable sur un réseau local de confiance ; à durcir si besoin.
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=self.config.host,
            port=self.config.port,
            username=self.config.username,
            password=self.config.resolved_password(),
            key_filename=self.config.key_filename,
            timeout=self.config.connect_timeout,
            allow_agent=True,
            look_for_keys=True,
        )
        self._client = client

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None

    def run(self, command: str, timeout: int = 20) -> CommandResult:
        if self._client is None:
            raise RuntimeError("Session non connectée — appelle connect() d'abord.")
        stdin, stdout, stderr = self._client.exec_command(command, timeout=timeout)
        exit_status = stdout.channel.recv_exit_status()
        return CommandResult(
            command=command,
            stdout=stdout.read().decode("utf-8", errors="replace"),
            stderr=stderr.read().decode("utf-8", errors="replace"),
            exit_status=exit_status,
        )

    def run_safe(self, command: str, timeout: int = 20) -> CommandResult:
        """Exécute une commande en encadrant les erreurs (jamais d'exception)."""
        try:
            return self.run(command, timeout=timeout)
        except Exception as exc:  # noqa: BLE001 — on veut vraiment tout capturer ici
            return CommandResult(command=command, stdout="", stderr=str(exc), exit_status=-1)

    def read_file(self, path: str) -> CommandResult:
        return self.run_safe(f"cat {shlex.quote(path)}")

    def run_sudo(self, command: str, timeout: int = 20) -> CommandResult:
        """Exécute `sudo -S <command>` en fournissant le mot de passe sur stdin.

        Chaque exec SSH est une session neuve, donc sudo redemande le mot de passe.
        `-S` fait lire le mot de passe depuis stdin ; le prompt part sur stderr.
        Utilise le mot de passe de la config (le même que celui du compte admin).
        """
        if self._client is None:
            raise RuntimeError("Session non connectée — appelle connect() d'abord.")
        password = self.config.resolved_password()
        stdin, stdout, stderr = self._client.exec_command(
            f"sudo -S -p '' {command}", timeout=timeout
        )
        if password:
            try:
                stdin.write(password + "\n")
                stdin.flush()
            except OSError:
                pass
        exit_status = stdout.channel.recv_exit_status()
        return CommandResult(
            command=f"sudo {command}",
            stdout=stdout.read().decode("utf-8", errors="replace"),
            stderr=stderr.read().decode("utf-8", errors="replace"),
            exit_status=exit_status,
        )

    def esa(self, subcommand: str, timeout: int = 20) -> str:
        """Lance `sudo esa <subcommand>` et renvoie la sortie nettoyée (str vide si échec)."""
        res = self.run_sudo(f"esa {subcommand}", timeout=timeout)
        return res.stdout.strip() if res.ok else ""


@contextmanager
def connected(config: DroboConfig):
    """Context manager : ouvre puis ferme proprement la session."""
    session = DroboSSH(config)
    session.connect()
    try:
        yield session
    finally:
        session.close()
