#!/usr/bin/env bats
# Bots du dépôt configurés avec l'accord de l'utilisateur (bin/bots) : gh
# simulé, commandes enchaînées simulées, réponses sur l'entrée standard

load helpers

BOTS="$BATS_TEST_DIRNAME/../bin/bots"
INSTALL="$BATS_TEST_DIRNAME/../install.sh"

setup() {
    setup_repo
    initial_commit
    git remote set-url origin https://github.com/moi/projet.git
    F="$BATS_TEST_TMPDIR/f"
    mkdir -p "$F/bin" "$F/fakebin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE/log"
case "$*" in
    "auth status"*) exit "${GH_AUTH:-0}" ;;
    "repo view"*) echo moi/projet ;;
    "api repos/moi/projet --jq .permissions.admin") echo "${GH_ADMIN:-true}" ;;
    "api repos/moi/projet --jq .default_branch") echo main ;;
    "api repos/moi/projet/branches/develop"*) [ -n "${GH_DEVELOP:-}" ] && echo develop || exit 1 ;;
    "variable get REPOWARDEN_APP_CLIENT_ID"*) [ -n "${GH_APP:-}" ] && echo Iv1.abc || exit 1 ;;
    "api repos/moi/projet/git/ref/heads/main"*) echo abc123 ;;
esac
exit 0
GH
    for c in tickets app proteger npm-publication; do
        printf '#!/usr/bin/env bash\necho "%s $*" >>"$FAKE/log"\n[ "${ECHEC:-}" != %s ]\n' "$c" "$c" >"$F/fakebin/$c"
    done
    chmod +x "$F/bin/gh" "$F/fakebin/"*
    export PATH="$F/bin:$PATH" FAKE="$F" REPOWARDEN_BIN="$F/fakebin" REPOWARDEN_INTERACTIF=1
}

# Réponses, une par ligne
repondre() { printf '%s\n' "$@" >"$F/reponses"; }
lancer() { run bash -c "\"$BOTS\" <\"$F/reponses\""; }

@test "bots : rien sans accord (non par defaut), ni sans terminal, gh ou droits d'admin" {
    repondre ""
    lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun bot configuré"* ]]
    [ ! -e .github ] && ! grep -q -- "-X POST" "$F/log"
    ! grep -qE "^(tickets|app|proteger|npm-publication) " "$F/log"
    REPOWARDEN_INTERACTIF="" run bash -c "\"$BOTS\" </dev/null"
    [[ "$output" == *"pas de terminal"*"repowarden bots"* ]]
    GH_ADMIN=false lancer
    [[ "$output" == *"droits d'administration"* ]]
    GH_AUTH=1 lancer
    [[ "$output" == *"gh auth login"* ]]
    # réglage forge : prioritaire sur la CI (GITHUB_ACTIONS) et sur le remote
    git config repowarden.forge gitlab
    lancer
    [[ "$output" == *"hors de GitHub"* ]]
}

@test "bots : flux main, un accord par bot, apercu puis application" {
    # global, flux 1, ci, release, tickets, app (non), protection, confirmation
    repondre o 1 o o o n o o
    lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aperçu"* && "$output" == *".github/workflows/repowarden.yml : créé"* ]]
    grep -q 'branches: \[main\]' .github/workflows/repowarden.yml
    ! grep -q 'fix-pr' .github/workflows/repowarden.yml
    grep -q 'release-auto.yml@v4' .github/workflows/release.yml
    ! grep -q 'app-client-id' .github/workflows/release.yml
    [ ! -e .github/workflows/nettoyage.yml ]
    grep -q "^tickets init --repo moi/projet$" "$F/log"
    grep -q "^proteger --repo moi/projet$" "$F/log"
    ! grep -q "^app " "$F/log"
    ! git config -f .repowarden.conf --get repowarden.integrationBranch
    [[ "$output" == *"commiter par une PR"* ]]
    if command -v actionlint >/dev/null; then actionlint .github/workflows/*.yml; fi
}

@test "bots : flux develop, develop creee avec accord, App deja la -> livraison par l'environnement" {
    # global, flux 2, créer develop, ci, release, nettoyage, tickets (non), protection, confirmation
    repondre o 2 o o o o n o o
    GH_APP=1 lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"déjà configurée"* ]]
    grep -q "^gh api -X POST repos/moi/projet/git/refs -f ref=refs/heads/develop -f sha=abc123" "$F/log"
    [ "$(git config -f .repowarden.conf repowarden.integrationBranch)" = develop ]
    [ "$(git config -f .repowarden.conf repowarden.protectedBranches)" = "main develop" ]
    ! git config -f .repowarden.conf --get repowarden.deliveryApproval
    grep -q 'fix-pr: "true"' .github/workflows/repowarden.yml
    grep -q 'branches: \[main, develop\]' .github/workflows/repowarden.yml
    grep -q 'mode: tag' .github/workflows/release.yml
    grep -q 'delivery-environment: production' .github/workflows/release.yml
    grep -q 'nettoyage-branches.yml@v4' .github/workflows/nettoyage.yml
    ! grep -qE "^(tickets|app) " "$F/log"
    if command -v actionlint >/dev/null; then actionlint .github/workflows/*.yml; fi
}

@test "bots : flux develop sans App -> livraison validee par revue ; develop refusee -> flux main" {
    # global, flux 2 (develop existe), ci, release, nettoyage, tickets, app (non), protection, confirmation
    repondre o 2 o o o n n n o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(git config -f .repowarden.conf repowarden.deliveryApproval)" = review ]
    ! grep -q 'delivery-environment' .github/workflows/release.yml
    ! grep -q -- "-X POST" "$F/log"
    rm -rf .github .repowarden.conf
    : >"$F/log"
    # develop absente, création refusée : flux main
    repondre o 2 n o n n n n o
    lancer
    grep -q 'branches: \[main\]' .github/workflows/repowarden.yml
    [ ! -e .repowarden.conf ]
}

@test "bots : flux develop propose par defaut" {
    # global, flux (Entrée), ci, release, nettoyage, tickets, app, protection, confirmation
    repondre o "" o o n n n n o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(git config -f .repowarden.conf repowarden.integrationBranch)" = develop ]
}

@test "bots : fichier existant jamais ecrase, ecart signale ; confirmation refusee -> rien" {
    mkdir -p .github/workflows
    echo "# perso" >.github/workflows/repowarden.yml
    # global, flux 1, ci, release (non), tickets (non), app (non), protection (non), confirmation (non)
    repondre o 1 o n n n n n
    lancer
    [[ "$output" == *"repowarden.yml existe : gardé tel quel (écart avec le modèle"* ]]
    [[ "$output" == *"Aucun bot configuré"* ]]
    repondre o 1 o n n n n o
    lancer
    [ "$(cat .github/workflows/repowarden.yml)" = "# perso" ]
    [[ "$output" == *"repowarden.yml existe : gardé tel quel."* ]]
}

@test "bots : un bot en echec n'arrete pas les autres ; npm propose seulement pour un paquet public" {
    printf '{ "name": "x", "private": true }\n' >package.json
    # global, flux 1, ci (non), release (non), tickets, app (non), protection, confirmation
    repondre o 1 n n o n o o
    ECHEC=tickets lancer
    [ "$status" -ne 0 ]
    [[ "$output" == *"tickets : échec"* ]]
    grep -q "^proteger " "$F/log"
    [[ "$output" != *"Publication npm"* ]]
    printf '{ "name": "x" }\n' >package.json
    : >"$F/log"
    # ... protection (non), npm, confirmation
    repondre o 1 n n n n n o o
    lancer
    grep -q "^npm-publication --repo moi/projet$" "$F/log"
}

@test "install : bots proposes dans un depot GitHub, --sans-bots les fait taire" {
    REPOWARDEN_INTERACTIF="" run bash -c "\"$INSTALL\" </dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bots du dépôt non proposés (pas de terminal"* ]]
    run "$INSTALL" --sans-bots
    [[ "$output" == *"ne seront plus proposés"* ]]
    [ "$(git config --local repowarden.bots)" = off ]
    REPOWARDEN_INTERACTIF="" run bash -c "\"$INSTALL\" </dev/null"
    [[ "$output" != *"Bots du dépôt"* ]]
}
