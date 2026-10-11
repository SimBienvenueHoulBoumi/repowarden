#!/usr/bin/env bats
# Paquet npm : commande repowarden (installation sur la machine), contenu publié

load helpers

PKG="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

setup() {
    setup_repo
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
}

@test "npm : version lue dans le tag (clone), package.json ecrit seulement a la publication" {
    run "$PKG/bin/repowarden" --version
    [ "$status" -eq 0 ]
    tag="$(git -C "$PKG" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    if [ -n "$tag" ]; then [ "$output" = "${tag#v}" ]; else [ "$output" = 0.0.0-dev ]; fi
    grep -q '"version": "0.0.0-dev"' "$PKG/package.json"
}

@test "npm : appelee par un lien symbolique (npm install -g), installe les vrais hooks" {
    mkdir -p "$BATS_TEST_TMPDIR/prefix/bin"
    ln -s "$PKG/bin/repowarden" "$BATS_TEST_TMPDIR/prefix/bin/repowarden" 2>/dev/null || true
    # Git Bash (Windows) copie au lieu de lier ; npm y crée des scripts .cmd
    [ -L "$BATS_TEST_TMPDIR/prefix/bin/repowarden" ] || skip "liens symboliques indisponibles"
    git config --unset core.hooksPath
    run "$BATS_TEST_TMPDIR/prefix/bin/repowarden" install --global --lang fr
    [ "$status" -eq 0 ]
    [ "$(git config --global --get core.hooksPath)" = "$PKG/hooks" ]
    [[ "$(git config --global --get alias.cc)" == *"$PKG/bin/commit"* ]]
    run "$BATS_TEST_TMPDIR/prefix/bin/repowarden" uninstall --global
    [ "$status" -eq 0 ]
    [ -z "$(git config --global --get core.hooksPath || true)" ]
}

@test "npm : npx refuse une installation globale (dossier temporaire)" {
    npx="$BATS_TEST_TMPDIR/_npx/abc/node_modules/repowarden"
    mkdir -p "$npx"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$npx/"
    run "$npx/bin/repowarden" install --global
    [ "$status" -ne 0 ]
    [[ "$output" == *"npm install -g"* ]]
    [ -z "$(git config --global --get core.hooksPath || true)" ]
}

@test "npm : commande inconnue refusee, aide affichee" {
    run "$PKG/bin/repowarden" inconnue
    [ "$status" -ne 0 ]
    [[ "$output" == *"repowarden install"* ]]
}

@test "npm : le paquet contient les hooks, ni tests, ni CI, ni modeles" {
    require npm
    run bash -c "cd '$PKG' && npm pack --dry-run --json 2>/dev/null"
    [ "$status" -eq 0 ]
    for f in bin/repowarden bin/commit install.sh hooks/lib/common.sh hooks/pre-commit; do
        [[ "$output" == *"\"$f\""* ]]
    done
    # Rien d'inutile sur une machine : tests, scripts de CI (accès réseau), modèles ;
    # sauf le suivi des tickets, appelé par « repowarden tickets init »
    for f in ci/tickets.sh ci/tickets/commun.sh ci/tickets/adopter.sh; do
        [[ "$output" == *"\"$f\""* ]]
    done
    for d in test/ ci/check.sh ci/version.sh templates/; do
        [[ "$output" != *"\"$d"* ]]
    done
}

@test "npm : desinstallation complete -> npm uninstall -g propose, pas rm -rf" {
    pkg="$BATS_TEST_TMPDIR/prefix/lib/node_modules/repowarden"
    mkdir -p "$pkg"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$pkg/"
    "$pkg/bin/repowarden" install --global --lang fr >/dev/null
    run "$pkg/bin/repowarden" uninstall --global --purge
    [ "$status" -eq 0 ]
    [[ "$output" == *"npm uninstall -g repowarden"* ]]
    [[ "$output" != *"rm -rf"* ]]
}

@test "statut : sans argument -> etat et etape suivante, puis tout est pret apres installation" {
    git config --unset core.hooksPath
    run "$PKG/bin/repowarden"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks git non activés"* ]]
    [[ "$output" == *"Étape suivante : repowarden install --global"* ]]
    "$PKG/bin/repowarden" install --global --lang fr >/dev/null
    run "$PKG/bin/repowarden" statut
    [[ "$output" == *"Hooks git actifs pour tous les dépôts"* ]]
    [[ "$output" == *"Assistant de commit : git cc"* ]]
    [[ "$output" == *"Tout est prêt"* ]]
}

@test "statut : lefthook.yml present -> signale comme non pris en charge" {
    printf 'pre-commit: {}\n' >lefthook.yml
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *"lefthook.yml présent : lefthook n'est plus pris en charge"* ]]
    [[ "$output" != *"absents : "*"lefthook"* ]]
}

@test "statut : installation locale (sans --global) -> hooks et git cc reconnus" {
    git config --unset core.hooksPath
    "$PKG/install.sh" --lang fr >/dev/null
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks git actifs dans ce dépôt seulement"* ]]
    [[ "$output" == *"Assistant de commit : git cc"* ]]
    [[ "$output" != *"non activés"* ]]
    [[ "$output" == *"Tout est prêt"* ]]
}

@test "statut : autre installation de repowarden -> signalee, reinstallation proposee" {
    autre="$BATS_TEST_TMPDIR/autre"
    mkdir -p "$autre"
    cp -R "$PKG/hooks" "$autre/"
    git config --global core.hooksPath "$autre/hooks"
    run "$PKG/bin/repowarden" statut
    [[ "$output" == *"Hooks git d'une autre installation de repowarden"* ]]
    [[ "$output" == *"Étape suivante : repowarden install --global"* ]]
}

@test "npm : uninstall --global rappelle npm uninstall -g (le paquet reste installe)" {
    pkg="$BATS_TEST_TMPDIR/prefix/lib/node_modules/repowarden"
    mkdir -p "$pkg"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$pkg/"
    "$pkg/bin/repowarden" install --global --lang fr >/dev/null
    run "$pkg/bin/repowarden" uninstall --global
    [ "$status" -eq 0 ]
    [[ "$output" == *"Le paquet reste installé ; pour le retirer aussi : npm uninstall -g repowarden"* ]]
}
