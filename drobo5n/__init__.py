"""drobo5n-manager — outil de gestion/monitoring d'un Drobo 5N via SSH.

Le Drobo 5N tourne sous Linux embarqué. Une fois l'accès SSH activé sur
l'appareil (voir README), ce paquet s'y connecte, exécute des commandes de
lecture pour récupérer l'état, et (à terme) expose des actions de gestion.

Modules :
    ssh      -> enveloppe de connexion SSH (paramiko)
    recon    -> reconnaissance : découvre OÙ vit le statut sur l'appareil
    model    -> structures de données (statut, baies, disques)
    collect  -> collecte + parsing de l'état (à compléter après recon)
    cli      -> point d'entrée ligne de commande
    web      -> mini dashboard web (Flask)
"""

__version__ = "0.1.0"
