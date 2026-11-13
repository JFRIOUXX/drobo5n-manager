"""Point d'entrée ligne de commande.

Usage :
    python -m drobo5n ping            # teste juste la connexion SSH
    python -m drobo5n recon           # sweep de découverte -> rapport Markdown
    python -m drobo5n status          # affiche l'état (JSON avec --json)
    python -m drobo5n serve           # mini dashboard web local
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import sys

from .collect import collect_status
from .config import load_config
from .format import render_status_text
from .recon import run_recon, write_report
from .ssh import connected


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("-c", "--config", help="Chemin du fichier config.toml")


def cmd_ping(args) -> int:
    cfg = load_config(args.config)
    with connected(cfg) as s:
        res = s.run_safe("echo drobo5n-ok")
        if res.text == "drobo5n-ok":
            print(f"Connexion OK à {cfg.host} (user={cfg.username}).")
            return 0
        print(f"Connecté mais réponse inattendue : {res.text!r} / {res.stderr!r}",
              file=sys.stderr)
        return 1


def cmd_recon(args) -> int:
    cfg = load_config(args.config)
    with connected(cfg) as s:
        results = run_recon(s)
    path = write_report(results, out_dir=args.out or ".")
    print(f"Rapport écrit : {path}")
    print("Analyse-le (ou passe-le à ton Claude Code) pour repérer les sources "
          "de statut, puis complète les parseurs dans drobo5n/collect.py.")
    return 0


def cmd_status(args) -> int:
    cfg = load_config(args.config)
    with connected(cfg) as s:
        status = collect_status(s)
    if args.json:
        payload = dataclasses.asdict(status)
        payload["overall_health"] = status.overall_health.value
        payload["physical_free_bytes"] = status.physical_free_bytes
        payload["physical_used_pct"] = status.physical_used_pct
        payload["volume_free_bytes"] = status.volume_free_bytes
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print(render_status_text(status))
    return 0


def cmd_serve(args) -> int:
    from .web import serve
    serve(config_path=args.config, host=args.bind, port=args.port)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="drobo5n", description="Gestion/monitoring Drobo 5N via SSH")
    sub = parser.add_subparsers(dest="command", required=True)

    p_ping = sub.add_parser("ping", help="Teste la connexion SSH")
    _add_common(p_ping)
    p_ping.set_defaults(func=cmd_ping)

    p_recon = sub.add_parser("recon", help="Reconnaissance de l'appareil -> rapport")
    _add_common(p_recon)
    p_recon.add_argument("-o", "--out", help="Dossier de sortie du rapport", default=".")
    p_recon.set_defaults(func=cmd_recon)

    p_status = sub.add_parser("status", help="Affiche l'état du Drobo")
    _add_common(p_status)
    p_status.add_argument("--json", action="store_true", help="Sortie JSON")
    p_status.set_defaults(func=cmd_status)

    p_serve = sub.add_parser("serve", help="Mini dashboard web local")
    _add_common(p_serve)
    p_serve.add_argument("--bind", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8765)
    p_serve.set_defaults(func=cmd_serve)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except FileNotFoundError as exc:
        print(f"Erreur : {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"Échec : {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
