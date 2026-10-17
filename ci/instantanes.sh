#!/usr/bin/env bash
# Instantanés de livraison abandonnés supprimés (workflow release-auto, mode
# tag avec delivery-environment) : chaque demande de livraison crée une branche
# livraison/vX.Y.Z et sa PR vers la branche principale ; le nettoyage des
# branches n'agit qu'au merge d'une PR, une demande remplacée ou refusée
# laisserait donc son instantané pour toujours.
#   ci/instantanes.sh
# Supprimé : un instantané dont la version est publiée (tag stable ≥ X.Y.Z) ou
# dont la PR de livraison est fermée sans fusion, seulement s'il ne contient
# aucun commit absent de la branche d'intégration. Jamais supprimés : la
# livraison en attente la plus récente (plus haute version non publiée), un
# instantané encore source d'une PR ouverte.
# Environnement : GH_TOKEN, GH_REPO, INTEGRATION (develop par défaut).
# Une erreur de l'API n'échoue jamais le run (la release est déjà faite) :
# avertissement, l'instantané est conservé.
set -euo pipefail

: "${GH_REPO:?}" "${INTEGRATION:=develop}"

STABLE='^[0-9]+\.[0-9]+\.[0-9]+$'

# REPLY = clé de tri de la version X.Y.Z (comparaison de chaînes = numérique)
cle_r() {
    local reste="${1#*.}"
    printf -v REPLY '%09d%09d%09d' "$((10#${1%%.*}))" "$((10#${reste%%.*}))" "$((10#${reste#*.}))"
}

# Plus haute version stable publiée (préversions vX.Y.Z-… exclues)
if ! tags="$(gh api --paginate "repos/$GH_REPO/git/matching-refs/tags/v" --jq '.[].ref')"; then
    echo "::warning::Instantanés de livraison : tags illisibles, aucun nettoyé."
    exit 0
fi
publiee="" derniere=""
for ref in $tags; do
    v="${ref#refs/tags/v}"
    [[ "$v" =~ $STABLE ]] || continue
    cle_r "$v"
    if [[ "$REPLY" > "$publiee" ]]; then
        publiee="$REPLY" derniere="$v"
    fi
done

if ! refs="$(gh api --paginate "repos/$GH_REPO/git/matching-refs/heads/livraison/v" --jq '.[].ref')"; then
    echo "::warning::Instantanés de livraison : branches illisibles, aucune nettoyée."
    exit 0
fi
# Livraison en attente la plus récente : plus haute version non publiée
versions="" attente=""
for ref in $refs; do
    v="${ref#refs/heads/livraison/v}"
    [[ "$v" =~ $STABLE ]] || continue
    versions="$versions $v"
    cle_r "$v"
    if [[ "$REPLY" > "$publiee" && "$REPLY" > "$attente" ]]; then
        attente="$REPLY"
    fi
done

for v in $versions; do
    branche="livraison/v$v"
    cle_r "$v"
    if [ "$REPLY" = "$attente" ]; then
        echo "$branche conservée : livraison en attente la plus récente."
        continue
    fi
    if ! etats="$(gh pr list --head "$branche" --state all --json state -q '[.[].state] | join(" ")')"; then
        echo "::warning::$branche conservée : PR illisibles."
        continue
    fi
    if [[ " $etats " == *" OPEN "* ]]; then
        echo "$branche conservée : PR de livraison ouverte."
        continue
    fi
    if [[ ! "$REPLY" > "$publiee" ]]; then
        raison="v$derniere publiée"
    elif [[ " $etats " == *" CLOSED "* ]]; then
        raison="PR de livraison fermée sans fusion"
    else
        continue
    fi
    # Jamais de travail perdu : rien d'absent de la branche d'intégration
    avance="$(gh api "repos/$GH_REPO/compare/$INTEGRATION...$branche" --jq .ahead_by 2>/dev/null)" || avance=""
    if [ "$avance" != 0 ]; then
        echo "::warning::$branche conservée ($raison) : ${avance:-?} commit(s) absent(s) de $INTEGRATION, à vérifier puis supprimer à la main."
        continue
    fi
    if gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$branche" >/dev/null; then
        echo "::notice::Instantané $branche supprimé ($raison)."
    else
        echo "::warning::$branche non supprimée ($raison)."
    fi
done
