"""Mini dashboard web local (Flask) pour le Drobo 5N2.

Sert une page qui affiche santé + capacité réelle + firmware, rafraîchie
automatiquement. Tourne en local (127.0.0.1). 100 % compatible macOS 27.
"""
from __future__ import annotations

import dataclasses

from flask import Flask, jsonify, render_template_string

from .collect import collect_status
from .config import load_config
from .format import human_bytes
from .ssh import connected

_PAGE = """<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Drobo 5N2</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, system-ui, sans-serif; margin: 0;
         background: #f5f5f7; color: #1d1d1f; }
  @media (prefers-color-scheme: dark) {
    body { background: #1d1d1f; color: #f5f5f7; }
    .card { background: #2a2a2c !important; }
  }
  .wrap { max-width: 620px; margin: 2rem auto; padding: 0 1rem; }
  h1 { font-size: 1.4rem; }
  .card { background: #fff; border-radius: 14px; padding: 1.25rem 1.5rem;
          box-shadow: 0 1px 4px rgba(0,0,0,.08); margin-bottom: 1rem; }
  .row { display: flex; justify-content: space-between; padding: .35rem 0;
         border-bottom: 1px solid rgba(128,128,128,.15); gap: 1rem; }
  .row:last-child { border-bottom: none; }
  .bar { height: 10px; border-radius: 6px; background: rgba(128,128,128,.25);
         overflow: hidden; margin: .5rem 0; }
  .bar > span { display: block; height: 100%; background: #0a84ff; }
  .muted { opacity: .6; font-size: .85rem; }
  .pill { padding: .15rem .6rem; border-radius: 999px; font-weight: 600; font-size: .85rem; }
  .good { background: rgba(48,209,88,.18); color: #248a3d; }
  .warning { background: rgba(255,159,10,.18); color: #b25e00; }
  .critical { background: rgba(255,69,58,.18); color: #c1271b; }
  .unknown { background: rgba(128,128,128,.18); }
  h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .04em;
       opacity: .55; margin: 0 0 .4rem; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Drobo 5N2 <span class="muted" id="host"></span></h1>
  <div class="card" id="status">Chargement…</div>
  <p class="muted">Rafraîchissement auto toutes les 30 s. La température par disque
     n'est pas encore incluse — la santé globale sert de filet anti-surchauffe.</p>
</div>
<script>
async function refresh() {
  try {
    const r = await fetch('/api/status');
    const d = await r.json();
    document.getElementById('host').textContent = '· ' + d.host;
    const hcls = d.overall_health || 'unknown';
    const hlabel = {good:'OK', warning:'ATTENTION', critical:'CRITIQUE', unknown:'inconnu'}[hcls] || '—';
    const pct = d.physical_used_pct == null ? 0 : d.physical_used_pct;
    document.getElementById('status').innerHTML =
        `<div class="row"><span>Santé</span>`
      + `<span class="pill ${hcls}">${hlabel}${d.health_label ? ' — '+d.health_label : ''}</span></div>`
      + `<div class="row"><span>Firmware</span><b>${d.firmware||'—'}</b></div>`
      + `<div class="row"><span>Disk pack</span><b>${d.disk_pack_id||'—'}</b></div>`
      + `<h2 style="margin-top:1rem">Capacité physique réelle</h2>`
      + `<div class="row"><span>Utilisé</span><b>${d.phys_used_h} / ${d.phys_total_h} (${pct}%)</b></div>`
      + `<div class="bar"><span style="width:${pct}%"></span></div>`
      + `<div class="row"><span>Libre</span><b>${d.phys_free_h}</b></div>`
      + `<h2 style="margin-top:1rem">Volume présenté (thin-provisioning)</h2>`
      + `<div class="row"><span>Utilisé</span><b>${d.vol_used_h} / ${d.vol_total_h}</b></div>`;
  } catch (e) {
    document.getElementById('status').textContent = 'Erreur : ' + e;
  }
}
refresh(); setInterval(refresh, 30000);
</script>
</body>
</html>"""


def create_app(config_path: str | None = None) -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index():
        return render_template_string(_PAGE)

    @app.get("/api/status")
    def api_status():
        cfg = load_config(config_path)
        with connected(cfg) as s:
            status = collect_status(s)
        payload = dataclasses.asdict(status)
        payload["overall_health"] = status.overall_health.value
        payload["physical_used_pct"] = status.physical_used_pct
        payload["phys_total_h"] = human_bytes(status.physical_total_bytes)
        payload["phys_used_h"] = human_bytes(status.physical_used_bytes)
        payload["phys_free_h"] = human_bytes(status.physical_free_bytes)
        payload["vol_total_h"] = human_bytes(status.volume_total_bytes)
        payload["vol_used_h"] = human_bytes(status.volume_used_bytes)
        return jsonify(payload)

    return app


def serve(config_path: str | None = None, host: str = "127.0.0.1", port: int = 8765) -> None:
    app = create_app(config_path)
    print(f"Dashboard : http://{host}:{port}  (Ctrl+C pour quitter)")
    app.run(host=host, port=port, debug=False)
