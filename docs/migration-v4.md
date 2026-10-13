# Passer de repogarde 3 à repowarden 4

**lefthook n'est plus pris en charge** depuis la v4.0.0, et **repogarde s'appelle repowarden** depuis la v4.1.0. Les anciens noms restent lus pendant toute la v4, avec un avertissement : rien ne casse le jour de la mise à jour. Ils seront ignorés en v5.

## Ce qui change

| Avant (v3) | Après (v4) | En v4 |
|---|---|---|
| `npm install -g @simbie/repogarde`, commande `repogarde` | `npm install -g repowarden`, commande `repowarden` | `repogarde` relaie vers `repowarden`, avec un avertissement |
| `.repogarde.conf`, section `[repogarde]` | `.repowarden.conf`, section `[repowarden]` | ancien fichier lu ; le nouveau l'emporte |
| `git config repogarde.*` | `git config repowarden.*` | anciennes clés lues ; `repowarden install` les renomme |
| variables `REPOGARDE_*` | variables `REPOWARDEN_*` | anciennes lues ; les nouvelles l'emportent |
| hooks du projet dans `.repogarde/<hook>` | `.repowarden/<hook>` | ancien dossier lancé s'il n'y a pas le nouveau |
| `uses: SimBienvenueHoulBoumi/repogarde@v3` | `uses: simdevWarden/repowarden@v4` | `@v3` continue de fonctionner (GitHub redirige le dépôt renommé) |
| vérification exigée `repogarde` | vérification exigée `repowarden` | relancer `repowarden proteger` |
| lefthook (`lefthook.yml`, `lefthook-remote.yml`) | retiré | hook lefthook ignoré, avec la marche à suivre |
| site `…github.io/repogarde/` | `…github.io/repowarden/` |  |

## Sur chaque poste

```bash
repogarde uninstall --global          # avec l'ancien paquet
npm uninstall -g @simbie/repogarde
npm install -g repowarden
repowarden install --global           # renomme aussi les anciennes clés repogarde.*
repowarden                            # vérifie : état du poste et étape suivante
```

## Dans chaque projet

1. Renommer `.repogarde.conf` en `.repowarden.conf`, et sa section `[repogarde]` en `[repowarden]` ; y mettre `version = 4`.
2. Renommer le dossier `.repogarde/` en `.repowarden/`, s'il existe.
3. Dans les workflows : `simdevWarden/repowarden@v4`, et les variables `REPOGARDE_*` en `REPOWARDEN_*`.
4. Projet sous lefthook : déplacer ses commandes dans `.repowarden/<hook>`, puis `lefthook uninstall` et supprimer `lefthook.yml`.
5. Mettre à jour la protection des branches, la vérification exigée s'appelant désormais `repowarden` : `repowarden proteger`.
