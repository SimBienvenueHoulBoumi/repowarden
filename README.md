# repowarden

[![CI](https://github.com/simdevWarden/repowarden/actions/workflows/ci.yml/badge.svg)](https://github.com/simdevWarden/repowarden/actions/workflows/ci.yml)
[![e2e](https://github.com/simdevWarden/repowarden/actions/workflows/e2e.yml/badge.svg)](https://github.com/simdevWarden/repowarden/actions/workflows/e2e.yml)
[![Release](https://img.shields.io/github/v/release/simdevWarden/repowarden)](https://github.com/simdevWarden/repowarden/releases)
[![npm](https://img.shields.io/npm/v/repowarden)](https://www.npmjs.com/package/repowarden)
[![Documentation](https://img.shields.io/badge/docs-site-indigo)](https://simdevwarden.github.io/repowarden/)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/simdevWarden/repowarden/badge)](https://scorecard.dev/viewer/?uri=github.com/simdevWarden/repowarden)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

**repowarden** garde l'entrée de vos dépôts Git : messages de commit, nommage des branches, secrets, formatage et tests, **quel que soit le langage** — sur les postes (hooks), en CI (GitHub, GitLab) et côté serveur.

📖 **Documentation : https://simdevwarden.github.io/repowarden/** · 🇬🇧 **English: https://simdevwarden.github.io/repowarden/en/**

> **v4 : repogarde devient repowarden** (paquet npm `repowarden`) et lefthook n'est plus pris en charge. Les anciens noms restent lus en v4. Marche à suivre : [Passer à la v4](https://simdevwarden.github.io/repowarden/migration-v4/).

## Ce qu'il fait

- **Commits** : Conventional Commits imposés, préfixe déduit de la branche ; assistant interactif `git cc` (en-tête, corps, pied).
- **Branches** : format `<type>/<sujet>`, commande de renommage proposée, branches mergées supprimées automatiquement.
- **Secrets** : gitleaks avant le commit et en CI.
- **Formatage** : seul le contenu stagé, avec l'outil du projet ; le travail en cours est préservé.
- **Tests** : au push et en CI, seulement les projets touchés, sur le commit poussé.
- **Code mort** : seul le nouveau code mort est signalé, prouvé (bloquant) ou candidat (à vérifier) ; `repowarden code-mort` en local.
- **Tickets** : chaque PR est reliée à un ticket validé (créé automatiquement s'il manque), suivi de « à valider » à « done » à la release ; `repowarden tickets init`.
- **Versions et releases** : les commits étant conventionnels, la version suivante (semver) et le changelog se déduisent de l'historique ; un workflow réutilisable en fait des releases automatiques (PR de release validée par la CI puis mergée, tag, release), sans jeton ; dans le flux `develop` → `main`, un clic d'approbation par livraison.

**Plus de 25 technologies** : Java (Maven, Gradle), JavaScript / TypeScript, Python, Go, Rust, PHP, Ruby, .NET, Dart / Flutter, Swift, Elixir, C / C++, Shell, Terraform, Packer, Ansible, Helm, Kubernetes, Docker, GitHub Actions — [détail](https://simdevwarden.github.io/repowarden/technologies/). Linux, macOS, Windows.

## Ce que tu fais à la main

Le reste est automatique. Pas à pas et pièges : [où cliquer](https://simdevwarden.github.io/repowarden/validation/#ou-cliquer).

| Geste | Où |
|---|---|
| Valider un ticket | étiquette `validé` (d'office si un mainteneur l'ouvre) |
| Écrire la conception, avant le code | commentaire contenant « Conception retenue » sur le ticket |
| Terminer une PR | **Ready for review** : elle se merge seule quand la CI est verte |
| Livrer en production (flux `develop`) | *Actions → release → Run workflow* (ou la demande du vendredi), puis **Review deployments → Approve and deploy** sur le run |
| Livrer un correctif urgent | étiquette `urgent` (à créer si absente) sur la PR `fix/…` |
| Relire une PR, si exigé | *Files changed → Review changes → Approve* |

Une PR `develop` → `main` ouverte à la main ne reçoit jamais d'approbation : lancer le workflow `release`, qui ouvre la sienne.

## Démarrage

### 1. Sur ton poste, en une minute (tous tes dépôts)

```bash
npm install -g repowarden     # 1. le paquet (yarn global add, pnpm add -g : idem)
repowarden install --global           # 2. active les hooks : demande la langue, installe git cc
repowarden                            # 3. vérifie : état du poste et étape suivante
```

L'étape 2 est indispensable : par sécurité, le paquet n'exécute rien à l'installation (aucun script `postinstall`, que npm 12 bloque d'ailleurs). Ensuite, dans **n'importe quel dépôt**, les hooks s'appliquent dès le prochain commit. Rien n'est ajouté aux projets ni à leur `package.json`.

```bash
cd mon-projet
git switch -c feat/panier            # nom de branche vérifié
git add . && git cc                  # assistant : type, scope, description… puis commit
git push -u origin feat/panier       # tests des projets touchés avant l'envoi
repowarden code-mort                  # nouveau code mort de ta branche
```

| Action | Commande |
|---|---|
| État du poste, étape suivante | `repowarden` (ou `repowarden statut`) |
| Toutes les commandes | `repowarden --help` (`cc`, `code-mort`, `proteger`, `npm-publication`…) |
| Mettre à jour | `npm update -g repowarden` (les hooks suivent) |
| Désinstaller | `repowarden uninstall --global`, **puis** `npm uninstall -g repowarden` (dans cet ordre : npm n'exécute rien à la désinstallation, les hooks resteraient branchés sur un dossier supprimé) |

Sans Node : `git clone https://github.com/simdevWarden/repowarden.git ~/repowarden && ~/repowarden/install.sh --global` (mise à jour : `git -C ~/repowarden pull`).

### 4. GitHub App pour l'automatisation (merge auto, tickets, releases)

Pour que les workflows déclenchent les autres workflows (merge auto, tickets, releases), il faut une GitHub App au lieu du `GITHUB_TOKEN` :

```bash
repowarden app init
```

1. Ouvre la page locale → clique "Create GitHub App" sur GitHub
2. Clique "Install" sur ton repo/org
3. Les secrets `REPOWARDEN_APP_CLIENT_ID` / `REPOWARDEN_APP_KEY` sont configurés automatiquement

Sans cette étape, le `GITHUB_TOKEN` des Actions est utilisé : **ce qu'il fait ne déclenche pas les autres workflows** (merge auto, tickets, préversions).

**Tester la prochaine version** (avant sa sortie en production) : `npm install -g repowarden@next`, ou `uses: simdevWarden/repowarden@develop` en CI. Retour à la version stable : `npm install -g repowarden@latest`. Les problèmes se signalent en [issue](https://github.com/simdevWarden/repowarden/issues).

### 2. Dans un projet d'équipe : les mêmes règles pour tous

Chaque personne de l'équipe installe repowarden une fois sur son poste (partie 1). Le projet, lui, ajoute deux fichiers, à copier depuis [`templates/project/`](templates/project) :

| Fichier | Rôle |
|---|---|
| [`.github/workflows/repowarden.yml`](templates/project/.github/workflows/repowarden.yml) | la CI refait toutes les vérifications sur chaque PR : c'est elle qui fait foi, même si quelqu'un contourne les hooks (`git commit --no-verify`) |
| [`.repowarden.conf`](templates/project/.repowarden.conf) | réglages communs à toute l'équipe, dont la version minimale de repowarden attendue sur les postes |

L'essentiel des deux fichiers :

```yaml
# .github/workflows/repowarden.yml : vérifications de la PR (dernière version 4.x)
- uses: simdevWarden/repowarden@v4
  with: { strict: true }      # un outil manquant fait échouer la CI
```

```ini
# .repowarden.conf : un poste en retard est prévenu, avec la commande de mise à jour
[repowarden]
    version = 3
```

Puis rendre la CI obligatoire pour merger : `repowarden proteger` (protection de `main`, check `repowarden` exigé).

Exemple complet : [repowarden-demo](https://github.com/simdevWarden/repowarden-demo) · Releases automatiques : [documentation](https://simdevwarden.github.io/repowarden/releases/).

### 3. Contribuer à repowarden

```bash
git clone https://github.com/simdevWarden/repowarden.git && cd repowarden
./install.sh                         # repowarden se vérifie lui-même (hooks de ce dépôt)
bats test/                           # tests (bats-core), aussi lancés au push
```

Les PR visent `develop` ; `main` ne reçoit que les livraisons, qui déclenchent les releases. Voir [CONTRIBUTING.md](CONTRIBUTING.md).

**Dans VS Code** : l'extension [repowarden-vscode](https://github.com/simdevWarden/repowarden-vscode) guide la rédaction des commits, signale une branche mal nommée et des hooks inactifs. En attendant sa publication sur le Marketplace : `.vsix` dans ses [releases](https://github.com/simdevWarden/repowarden-vscode/releases), puis `code --install-extension repowarden-X.Y.Z.vsix`.

## Liens

[Démarrage rapide](https://simdevwarden.github.io/repowarden/demarrage/) · [Hooks et règles](https://simdevwarden.github.io/repowarden/hooks/) · [Technologies](https://simdevwarden.github.io/repowarden/technologies/) · [Configuration](https://simdevwarden.github.io/repowarden/configuration/) · [CI](https://simdevwarden.github.io/repowarden/ci/) · [Versions et releases](https://simdevwarden.github.io/repowarden/releases/) · [Validation humaine](https://simdevwarden.github.io/repowarden/validation/) · [Code mort](https://simdevwarden.github.io/repowarden/code-mort/) · [En organisation](https://simdevwarden.github.io/repowarden/industrialisation/) · [Sources internes (Nexus, Artifactory)](https://simdevwarden.github.io/repowarden/industrialisation/#8-sources-internes-reseau-ferme-nexus-artifactory) · [Désinstallation](https://simdevwarden.github.io/repowarden/desinstallation/) · [Sécurité](SECURITY.md) · [Contribuer](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

Licence [MIT](LICENSE).
