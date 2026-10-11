# Versions et releases

Les commits d'un projet repowarden sont conventionnels : la version suivante et le changelog s'en déduisent. Un workflow réutilisable en fait des **releases automatiques**, sans jeton à créer ni étape manuelle.

## Mise en place

```yaml title=".github/workflows/release.yml"
name: release

on:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: release
  cancel-in-progress: false

permissions: {}

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions:
      contents: write
      pull-requests: write
      actions: write
      checks: read
      statuses: write
```

Modèle complet : [`templates/project/.github/workflows/release.yml`](https://github.com/SimBienvenueHoulBoumi/repowarden/blob/main/templates/project/.github/workflows/release.yml).

Deux prérequis :

1. *Settings → Actions → General → Workflow permissions* : cocher **Allow GitHub Actions to create and approve pull requests** ;
2. les workflows de CI du projet acceptent `workflow_dispatch` (déjà le cas du modèle `repowarden.yml`) : c'est ainsi que la CI est lancée sur la PR de release.

## Fonctionnement

| Commits depuis la dernière release | Nouvelle version |
|---|---|
| `fix:`, `perf:` | correctif : 1.4.**2** → 1.4.**3** |
| `feat:` | fonctionnalité : 1.**4**.2 → 1.**5**.0 |
| `feat!:` ou `BREAKING CHANGE:` en pied | majeure : **1**.4.2 → **2**.0.0 |
| `ci:`, `chore:`, `test:`, `refactor:`, `style:` | aucune release |

`docs:` déclenche un correctif seulement si sa section est visible dans le changelog (configuration).

À chaque push sur `main` :

1. [release-please](https://github.com/googleapis/release-please) ouvre ou met à jour la PR « release x.y.z » : changelog et version dans le fichier du projet ;
2. la CI du projet est lancée sur cette PR ; une fois verte, la PR est mergée (squash). Si `main` avance entre-temps, la PR est recalculée (version et changelog incluant les nouveaux commits) par le run suivant, puis revalidée ;
3. le tag `vX.Y.Z` et la release GitHub sont créés.

Les vérifications exigées par la protection de `main` restent obligatoires : sans CI verte, rien n'est mergé.

## Merger la PR de release : laisser faire le bot

La PR de release est mergée **par le workflow lui-même**, dès que la CI est verte, et la release est publiée dans le même run. La merger à la main fonctionne aussi (le run qui attendait sa CI s'arrête alors proprement, et c'est le run déclenché par ton merge qui publie), sauf dans un cas : si un fichier de `.github/workflows/` change sur `main` avant que la release soit publiée, GitHub refuse au jeton des Actions de créer le tag (il faudrait la permission `workflow`, que ce jeton n'a jamais) : « Resource not accessible by integration ».

Le workflow le détecte et affiche la cause et les commandes exactes ; en résumé, avec un compte qui a la permission `workflow` :

```bash
gh auth refresh -h github.com -s workflow
gh release create vX.Y.Z --target <commit de merge de la PR> --title vX.Y.Z --notes-file notes.md
gh pr edit <n° de la PR> --remove-label "autorelease: pending" --add-label "autorelease: tagged"
```

puis relancer le workflow `release`.

## Fichier de version

Le type de projet est détecté d'après les fichiers à la racine :

| Fichier | Version mise à jour dans |
|---|---|
| `pom.xml` | `pom.xml` (Maven) |
| `package.json` | `package.json`, `package-lock.json` |
| `pyproject.toml`, `setup.py` | `pyproject.toml` / `setup.py` |
| `Cargo.toml` | `Cargo.toml`, `Cargo.lock` |
| `Chart.yaml` | `Chart.yaml` (Helm) |
| `go.mod` | aucun : le tag fait la version |
| `composer.json`, `pubspec.yaml`, `mix.exs` | fichier correspondant |
| autre | `version.txt` |

!!! tip "Changelog en français, monorepo, options"
    Un fichier `release-please-config.json` à la racine (avec `.release-please-manifest.json`) prend le pas sur la détection : sections du changelog, plusieurs paquets, fichiers supplémentaires à versionner… Voir la [configuration de repowarden](https://github.com/SimBienvenueHoulBoumi/repowarden/blob/main/release-please-config.json) pour un exemple en français.

!!! note "Maven"
    Après chaque release, release-please propose de repasser en `-SNAPSHOT` (PR mergée automatiquement de la même façon). Pour s'en passer : `"skip-snapshot": true` dans `release-please-config.json`.

## Flux develop → main (mode tag, recommandé)

Pour un projet à deux branches longues ([flux `integrationBranch`](configuration.md#flux-avec-branche-dintegration-develop)) : `develop` sert aux tests (préversions), `main` à la production. **Aucune version n'est écrite dans les fichiers** : elle est calculée depuis tous les commits livrés et portée par le tag, les notes vont dans la release GitHub, comme le [recommande semantic-release](https://semantic-release.gitbook.io/semantic-release/support/faq). repowarden lui-même fonctionne ainsi.

```yaml title=".github/workflows/release.yml"
on:
  push:
    branches: [main, develop]

concurrency:
  group: release-${{ github.ref_name }}   # une file par branche
  cancel-in-progress: false

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write }
    with:
      mode: tag

  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v7
        with: { ref: "${{ needs.release.outputs.tag_name }}" }
      - run: ./mvnw -B verify -Drevision="${{ needs.release.outputs.version }}"
      - run: gh release upload "${{ needs.release.outputs.tag_name }}" target/*.jar
        env: { GH_TOKEN: "${{ github.token }}" }
```

1. À chaque merge sur `develop` : la **PR de livraison** `develop` → `main` (version à venir, notes) est tenue à jour, **sans release**. Une **préversion** de test (`vX.Y.Z-next.N`, release GitHub « pre-release ») est publiée **au plus une fois par jour**, le soir, si `develop` a changé (entrée `preversion-on-push` pour l'ancien comportement) ;
2. **une fenêtre de livraison**, par défaut le vendredi matin (entrée `delivery-schedule`, cron du déclenchement planifié) : une **seule** demande d'approbation, qui contient tout ce qui s'est accumulé : un **instantané** de `develop` (branche `livraison/vX.Y.Z`, figée au commit de la demande) et sa PR vers `main`. La valider : **un clic « Approve and deploy »** sur l'environnement `production` (entrée `delivery-environment`), depuis la notification ou la page du run ; la GitHub App merge alors la PR de livraison (**merge commit** : chaque commit reste visible), ce qui publie sur `main` le tag `vX.Y.Z` et la release ; la version est calculée à partir de **tous** les commits livrés (merges exclus). Une seule validation en attente à la fois : la plus récente ;
3. **aucune version stable sans préversion testée** (entrée `preversion-obligatoire`, activée par défaut) : la version publiée sur `main` doit avoir existé en `vX.Y.Z-next.N` sur `develop`. Une majeure (v3 → v4) passe donc toujours par ses `4.0.0-next.N` ;
4. **seul `develop` entre dans `main`** : un correctif urgent est une PR `fix/…` vers `develop`, étiquetée **`urgent`** : son merge lance tout de suite la demande de livraison (sans attendre la fenêtre). À la main : *Actions → release → Run workflow* sur `develop`. Si quelque chose arrive malgré tout directement sur `main`, il revient seul dans `develop` (PR validée par la CI, mergée, sans clé).

Le rythme des versions stables est régulier : `develop` accumule, une livraison par fenêtre publie le tout en **une** version, mineure ou majeure selon les commits. À sa sortie, les préversions de cette version sont retirées de GitHub (sur npm, elles restent : une version publiée ne se retire pas).

!!! note "Approuver quand on veut"
    L'approbation porte sur l'instantané figé au moment de la demande : le travail mergé ensuite dans `develop` ne la rend pas caduque, il partira à la livraison suivante. Une nouvelle demande (urgence, relance) remplace la précédente. Seuls `develop` et ses instantanés `livraison/*` peuvent entrer dans `main`, jamais sans approbation.

| | `develop` : test | `main` : production |
|---|---|---|
| Version | préversion `3.6.0-next.4` (sorties `prerelease_*`) | stable `3.6.0` (sorties `release_created`, `tag_name`…) |
| Release GitHub | « pre-release » | release, notes groupées |
| Paquet (ex. npm) | étiquette `next` | étiquette `latest` |

La CI du projet doit tourner sur les pushs vers `develop` : ses vérifications portent sur le commit de tête, et valent donc pour la PR de livraison.

## Cycle develop → main avec fichiers de version (mode cycle)

!!! warning "Déconseillé : préférer le mode tag"
    release-please ne lit sur `main` que les commits de premier niveau : une livraison mergée en merge commit lui apparaît comme un seul « Merge pull request », il n'y voit pas les `feat` et `fix` apportés de `develop`, et peut ne publier **aucune** version. Le mode tag calcule la version à partir de tous les commits livrés.

Pour livrer à un rythme choisi, tout en gardant changelog et fichiers de version à jour (mode pr) : le travail s'intègre dans `develop`, `main` ne reçoit que les livraisons. repowarden lui-même fonctionne ainsi.

```yaml title=".github/workflows/release.yml"
on:
  push:
    branches: [main, develop]

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write }
    with:
      mode: cycle
```

1. À chaque merge sur `develop`, une **préversion** de test est publiée (`vX.Y.Z-next.N`, release GitHub « pre-release », entrée `preversion`), et la **PR de livraison** `develop` → `main` est créée ou mise à jour (version à venir, notes) ;
2. la merger (décision humaine, **merge commit** : release-please doit voir chaque commit) déclenche sur `main` la release du mode pr : PR de release (changelog, fichiers de version) validée par la CI et mergée, tag, release ;
3. `main` est ensuite fusionnée dans `develop` par une PR mergée automatiquement dès que ses vérifications passent : le cycle suivant repart des fichiers de version à jour.

| | `develop` : test, communauté | `main` : production |
|---|---|---|
| Quand | à chaque merge sur `develop` | au merge de la livraison (décision humaine) |
| Version | préversion `3.5.0-next.4` | stable `3.5.0`, changelog |
| Release GitHub | « pre-release » | release |
| Paquet (ex. npm) | étiquette `next` (job à brancher sur la sortie `prerelease_tag`) | étiquette `latest` |

La préversion se publie comme une version stable, depuis les sorties `prerelease_created` et `prerelease_tag` ; pour npm :

```yaml
  npm-next:
    needs: release
    if: needs.release.outputs.prerelease_created == 'true'
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/npm-publish.yml@v4
    permissions: { contents: read, id-token: write }
    with:
      tag: ${{ needs.release.outputs.prerelease_tag }}
      dist-tag: next
```

Prérequis :

- `.repowarden.conf` : `integrationBranch = develop` (PR mal ciblées reciblées vers `develop`) ;
- la CI tourne aussi sur les pushs vers `develop` (ses vérifications valent pour la PR de livraison) ;
- `repowarden proteger` : `develop` en branche par défaut, merge commit autorisé vers `main`, merge automatique activé ;
- aucune clé ni jeton : le retour vers `develop`, comme la PR de release, est validé par la CI (lancée par le workflow) puis mergé automatiquement.

## Publier sur npm

Un projet Node peut publier son paquet à chaque release, **sans jeton** : npm vérifie que la publication vient bien du dépôt et de son `release.yml` (publication de confiance) et affiche la provenance du paquet. yarn, pnpm et bun installent depuis le même registre. repowarden lui-même est publié ainsi (`repowarden`).

Mise en place en une commande, depuis le dépôt du projet. Tout est publié par la pipeline, la première version comprise :

1. **Connexion à npm** : `npm login` si besoin.
2. **Paquet pas encore sur npm** (npm n'accepte la publication de confiance que sur un paquet existant) :
   - un jeton npm temporaire est créé, valable 7 jours et limité au scope du paquet ;
   - il va directement dans le secret `NPM_TOKEN`, sans jamais s'afficher ; le mot de passe et le code 2FA sont demandés en saisie masquée ;
   - la variable `REPOWARDEN_NPM` active le job, puis la commande attend que la prochaine release publie le paquet.
3. **Publication de confiance** : configurée avec `npm trust github`, sans formulaire. Le secret est ensuite supprimé et le jeton révoqué. Les releases suivantes publient sans jeton.

Interrompue (Ctrl+C), la commande reprend où elle en était quand on la relance.

```bash
repowarden npm-publication
```

Puis, dans `.github/workflows/release.yml` :

```yaml
  npm:
    needs: release
    if: vars.REPOWARDEN_NPM == 'true' && (needs.release.outputs.release_created == 'true' || github.event_name == 'workflow_dispatch')
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/npm-publish.yml@v4
    permissions: { contents: read, id-token: write }
    with:
      tag: ${{ needs.release.outputs.tag_name }}
      # environment: production     # approbation avant publication (validation humaine)
      # directory: packages/ui      # paquet hors de la racine
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}   # première publication seulement
```

Lancer le workflow `release` à la main (Run workflow) publie la dernière release si elle manque sur npm. Le paquet est publié à la version du tag (y compris en mode tag, sans fichier de version). Une version déjà publiée est ignorée : relancer le run ne casse rien.

## Entrées et sorties

| Entrée | Défaut | Rôle |
|---|---|---|
| `release-type` | détection | type release-please (`maven`, `node`, `python`, `simple`…) |
| `workflows` | détection | workflows lancés sur la PR de release ; par défaut ceux qui réagissent à `pull_request` et à `workflow_dispatch` |
| `initial-version` | `0.1.0` | version de la première release (aucun tag existant) |
| `merge-auto` | `true` | `false` : la PR de release est préparée et validée par la CI, un humain la merge ; une relecture exigée par la protection est toujours respectée |
| `notify` | `release attente echec` | événements envoyés au canal de l'équipe (secret `webhook`) : voir [Validation humaine](validation.md#canal-de-lequipe) |
| `mode` | `pr` | `tag` : flux develop → main, sans PR de release ni fichier de version |
| `integration-branch`, `main-branch` | `develop`, `main` | branches du mode tag |
| `config-file`, `manifest-file` | `release-please-config.json`, `.release-please-manifest.json` | configuration release-please |

!!! warning "Workflows qui déploient"
    Un workflow qui déploie quand il n'est pas lancé par une PR (site, environnement) serait lancé sur la branche de release : lister explicitement les workflows de CI avec `workflows:`.

Sorties : `release_created`, `tag_name`, `version`, `major`, `sha`, pour enchaîner la publication propre au projet :

```yaml
  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with: { ref: "${{ needs.release.outputs.tag_name }}" }
      # mvn deploy, npm publish, docker push…
```

Suspendre les releases : *Actions → release → Disable workflow*.
