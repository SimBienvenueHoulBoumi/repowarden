#!/usr/bin/env bash
# Plateforme de gestion de version : github, gitlab, bitbucket, gitea (Gitea,
# Forgejo, Codeberg) ou other. Réglage forge (git config ou .repowarden.conf),
# sinon variables de la CI, sinon adresse du remote origin (domaine interne
# reconnu s'il contient gitlab, gitea…). Résultat mémorisé : FORGE.
# Vocabulaire : FORGE_PR (PR / MR), FORGE_REFS (exemple de références).
# shellcheck disable=SC2034 # variables utilisées par les scripts qui sourcent ce fichier

forge_init() {
    local forge="" url
    if declare -F cfg_r >/dev/null; then
        cfg_r forge ""
        forge="$REPLY"
    fi
    if [ -z "$forge" ]; then
        if [ -n "${GITHUB_ACTIONS:-}" ]; then forge=github
        elif [ -n "${GITLAB_CI:-}" ]; then forge=gitlab
        elif [ -n "${BITBUCKET_BUILD_NUMBER:-}" ]; then forge=bitbucket
        elif [ -n "${GITEA_ACTIONS:-}${FORGEJO_ACTIONS:-}" ]; then forge=gitea
        else
            url="$(git remote get-url origin 2>/dev/null || true)"
            case "$url" in
                *github*) forge=github ;;
                *gitlab*) forge=gitlab ;;
                *bitbucket*) forge=bitbucket ;;
                *gitea* | *forgejo* | *codeberg*) forge=gitea ;;
                *) forge=other ;;
            esac
        fi
    fi
    FORGE="$forge"
    case "$FORGE" in
        gitlab) FORGE_PR=MR FORGE_REFS="Closes #12, !34" ;;
        bitbucket) FORGE_PR=PR FORGE_REFS="PROJ-42" ;;
        *) FORGE_PR=PR FORGE_REFS="Closes #12" ;;
    esac
}

forge_init

# Dépôt GitHub $1 sans rulesets ni protection de branches (dépôt privé d'une
# offre gratuite : GitHub les refuse en 403, « Upgrade to GitHub Pro or make
# this repository public ») ; le merge automatique y est aussi ignoré
github_sans_rulesets() {
    local reponse
    ! reponse="$(gh api "repos/$1/rulesets" 2>&1)" && [[ "$reponse" == *"403"* ]]
}
