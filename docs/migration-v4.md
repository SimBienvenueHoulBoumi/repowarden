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
| `uses: SimBienvenueHoulBoumi/repogarde@v3` (action) | `uses: simdevWarden/repowarden@v4` | l'action continue de fonctionner (GitHub redirige le dépôt renommé) |
| `uses: SimBienvenueHoulBoumi/repogarde/.github/workflows/<fichier>.yml@v3` (workflow réutilisable) | `uses: simdevWarden/repowarden/.github/workflows/<fichier>.yml@v4` | **cassé** : GitHub ne redirige pas les workflows réutilisables ; le run échoue sans démarrer aucun job, et releases, tickets et nettoyage s'arrêtent en silence. À corriger en premier |
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
3. Dans les workflows, **en premier les workflows réutilisables** (`release-auto.yml`, `tickets.yml`, `nettoyage-branches.yml`, `npm-publish.yml`) : remplacer **tout le chemin**, pas seulement la version. Changer `@v3` en `@v4` sans changer le dépôt ne répare rien :
   - `SimBienvenueHoulBoumi/repogarde/.github/workflows/release-auto.yml@v3` → `simdevWarden/repowarden/.github/workflows/release-auto.yml@v4`
   - de même pour chaque `uses:` qui ne commence pas par `simdevWarden/repowarden/`.

   Symptôme d'une ligne oubliée : un run en échec **sans aucun job**. Ensuite, l'action : `simdevWarden/repowarden@v4`, et les variables `REPOGARDE_*` en `REPOWARDEN_*`.
4. Projet sous lefthook : déplacer ses commandes dans `.repowarden/<hook>`, puis `lefthook uninstall` et supprimer `lefthook.yml`.
5. Mettre à jour la protection des branches, la vérification exigée s'appelant désormais `repowarden` : `repowarden proteger`.
