# Contribuer

Règles de travail (tickets, commits, interdits) : [`AGENTS.md`](https://github.com/SimBienvenueHoulBoumi/repowarden/blob/develop/AGENTS.md), à lire avant tout changement.

## Mise en place

```bash
brew install bats-core shellcheck actionlint gitleaks   # ou équivalents apt / winget
./install.sh   # hooks repowarden sur ce dépôt (il se teste lui-même)
```

## Avant chaque PR

```bash
shellcheck bin/* ci/*.sh ci/tickets/*.sh hooks/pre-commit hooks/prepare-commit-msg hooks/commit-msg hooks/pre-push hooks/post-checkout hooks/post-merge hooks/lib/*.sh hooks/lib/i18n/*.sh hooks/lang/*.sh install.sh
actionlint .github/workflows/*.yml
bats test/                      # tests unitaires et d'intégration
test/e2e/run.sh python go       # tests réels (les langages dont l'outillage est installé)
```

La CI relance tout sur Linux, macOS et Windows, plus un job e2e par langage avec son vrai outillage.

## Conventions

- **Branches** : `<type>/<sujet>` (`feat/helm-unittest`, `fix/windows-paths`).
- **Commits** : [Conventional Commits](https://www.conventionalcommits.org). Le type détermine la version publiée : `fix` → correctif, `feat` → mineure, `!` → majeure.
- **Bash 3.2** (macOS) : pas de tableaux associatifs ni de `mapfile`. Dans les fonctions appelées par fichier, pas de sous-processus (`$(…)`) : résultat dans `REPLY`.
- **Noms de tests bats en ASCII** (bats Windows ignore les autres). Dans `languages.bats`, le nom commence par un préfixe couvert par les filtres Windows de `ci.yml` (`detection`, `format`, `pre-push`…) : un test vérifie qu'aucun n'est oublié.
- **Performance** : chaque création de processus coûte 20 à 50 ms sous Windows. Lire la config avec `cfg_r` (sans sous-shell), réutiliser `GIT_TOPLEVEL`, éviter `$(…)` dans les boucles.
- Un outil absent n'est **jamais bloquant** côté poste (`warn` / `tool_missing`) ; le mode strict de la CI le rend bloquant.

## Ajouter un langage ou un outil

1. `hooks/lang/<nom>.sh` : `register`, `<nom>_format`, `<nom>_test` (voir `docs/technologies.md`).
2. `test/e2e/<nom>/` : `project/` (sain), `bad/` (mal formaté), `break/` (tests cassés), `keep/` (à ne pas modifier), `e2e.env`.
3. Ajouter `<nom>` à la matrice de `.github/workflows/e2e.yml` avec l'installation de son outillage.
4. Mettre à jour le tableau de `docs/technologies.md`.

## Branches et releases

- Les PR visent **`develop`** (branche par défaut) ; une PR ouverte vers `main` est reciblée automatiquement. **Seul `develop` entre dans `main`**, par la PR de livraison, toujours avec une approbation humaine.
- À chaque merge sur `develop` : une **préversion** `vX.Y.Z-next.N` (npm `next`) et la **PR de livraison** `develop` → `main` tenue à jour (version à venir, notes). La merger, en merge commit, publie : tag `vX.Y.Z`, release GitHub (notes de version), `v4`, npm `latest`, site. Aucun fichier n'est écrit : la version est portée par le tag.
- Détail : [Versions et releases, mode tag](https://simbienvenuehoulboumi.github.io/repowarden/releases/#flux-develop-main-mode-tag-recommande).
