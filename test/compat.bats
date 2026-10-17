#!/usr/bin/env bats
# Anciens noms (repogarde, jusqu'à la v3) : encore lus en v4, avec un avertissement

load helpers

setup() {
    # Configuration globale du poste isolée (elle peut contenir repogarde.*)
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
    setup_repo
    initial_commit
    git switch -q -c feat/compat
    echo a >a.txt
    git add a.txt
}

@test "compat : variable REPOGARDE_* lue comme REPOWARDEN_*, avec avertissement" {
    unset REPOWARDEN_LANG
    export REPOGARDE_LANG=en
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Old repogarde name still in use (REPOGARDE_LANG)"* ]] || false
    [ "$(grep -c "Old repogarde name" <<<"$output")" -eq 1 ] # une fois par commit
}

@test "compat : la variable REPOWARDEN_* l'emporte sur l'ancienne" {
    export REPOGARDE_LANG=en
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ancien nom repogarde encore utilisé (REPOGARDE_LANG)"* ]] || false
}

@test "compat : cle git repogarde.* lue, avec avertissement" {
    git config repogarde.skip pre-commit
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ancien nom repogarde encore utilisé (repogarde.*)"* ]] || false
    [[ "$output" != *"Pre-commit OK"* ]] || false
}

@test "compat : .repogarde.conf lu ; .repowarden.conf l'emporte" {
    git config --unset repowarden.skip # réglage du dépôt de test : le fichier décide
    printf '[repogarde]\n    skip = secrets pre-commit\n' >.repogarde.conf
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(.repogarde.conf)"* ]] || false
    [[ "$output" != *"Pre-commit OK"* ]] || false
    printf '[repowarden]\n    skip = secrets\n' >.repowarden.conf
    echo b >b.txt && git add b.txt
    run git commit -m "feat: b"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-commit OK"* ]] || false
}

@test "compat : .repogarde/<hook> lance, sauf si .repowarden/<hook> existe" {
    mkdir -p .repogarde
    printf '#!/bin/sh\necho ANCIEN-HOOK\n' >.repogarde/pre-commit
    chmod +x .repogarde/pre-commit
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ANCIEN-HOOK"* ]] || false
    [[ "$output" == *"(.repogarde/)"* ]] || false
    mkdir -p .repowarden
    printf '#!/bin/sh\necho NOUVEAU-HOOK\n' >.repowarden/pre-commit
    chmod +x .repowarden/pre-commit
    echo b >b.txt && git add b.txt
    run git commit -m "feat: b"
    [[ "$output" == *"NOUVEAU-HOOK"* ]] || false
    [[ "$output" != *"ANCIEN-HOOK"* ]] || false
}

@test "compat : install migre les cles repogarde.* vers repowarden.*" {
    git config --global repogarde.lang en
    git config --global repogarde.skip secrets
    git config --global repowarden.skip format
    git config --unset core.hooksPath
    run "$BATS_TEST_DIRNAME/../install.sh" --global
    [ "$status" -eq 0 ]
    [[ "$output" == *"Réglages repogarde.* (--global) renommés en repowarden.*"* ]] || false
    [ "$(git config --global --get repowarden.lang)" = en ]
    [ "$(git config --global --get repowarden.skip)" = format ] # nouvelle cle gardee
    [ -z "$(git config --global --get-regexp '^repogarde\.' || true)" ]
}

@test "compat : commande repogarde relayee vers repowarden, avec avertissement" {
    run "$BATS_TEST_DIRNAME/../bin/repogarde" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"s'appelle désormais repowarden"* ]] || false
    [[ "$output" == *[0-9]* ]] || false
}
