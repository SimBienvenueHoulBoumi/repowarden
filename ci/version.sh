#!/usr/bin/env bash
# Versions d'après les Conventional Commits, sans fichier de version (mode tag) :
#   ci/version.sh next  [ref]   prochaine version X.Y.Z, ou rien s'il n'y a rien à publier
#   ci/version.sh notes [ref]   notes de version (Markdown) : introduction (En bref,
#                               À faire, Mettre à jour, Tickets livrés), puis commits par type
#   ci/version.sh notes-livraison [ref]
#                               notes de la PR de livraison mergée en ref (celles que
#                               l'approbateur a relues, corrections comprises), sinon notes
# Depuis le tag vX.Y.Z le plus élevé (pas le plus proche : une branche
# d'intégration ne contient pas les merges tagués sur main).
#   type! ou BREAKING CHANGE → majeure ; feat → mineure ; fix, perf → correctif.
# Un commit « chore(release): vX.Y.Z » (PR de livraison mergée en squash) fixe la version.
# Première version : $INITIAL_VERSION (défaut 0.1.0).
set -euo pipefail

# Langue des notes : celle du projet (lang de .repowarden.conf), anglais par défaut en CI
# shellcheck source=../hooks/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/common.sh"

cmd="${1:-next}"
ref="${2:-HEAD}"
scope='(\([a-z0-9._-]+\))?'
# Dernière version stable : les préversions (v3.5.0-next.2) ne comptent pas
last="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | awk '!/-/ && !f { print; f = 1 }')"
# Base : le tag ; après une livraison squashée (dépôt sans rulesets), les
# commits livrés ne sont pas des ancêtres du tag : la base devient le merge
# commit qui a réuni le tag dans ref, s'il a le même contenu que le tag
base="$last"
if [ -n "$last" ]; then
    arbre="$(git rev-parse "$last^{tree}")"
    # Merge commit qui a réuni le tag dans ref, au contenu identique au tag
    # awk lit tout (sans exit) : un tube coupé tôt tuerait git log (SIGPIPE + pipefail)
    identique="$(git log --merges --format='%H %T' "$ref" | awk -v a="$arbre" '!vu && $2 == a { print $1; vu = 1 }')"
    if [ -n "$identique" ] && git merge-base --is-ancestor "$last" "$identique"; then
        base="$identique"
    fi
fi
range="${base:+$base..}$ref"

next() {
    local subjects bump major minor patch announced
    subjects="$(git log --no-merges --format=%s "$range")"
    announced="$(grep -oE '^chore\(release\): v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$subjects" |
        sed 's/.*: v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1 || true)"
    if [ -n "$announced" ]; then
        echo_t ci.version.1 >&2
        echo "$announced"
        return
    fi
    if grep -qE "^[a-z]+$scope!: " <<<"$subjects" ||
        grep -qE '^BREAKING[ -]CHANGE: ' <<<"$(git log --no-merges --format=%b "$range")"; then
        bump="major"
    elif grep -qE "^feat$scope: " <<<"$subjects"; then
        bump="minor"
    elif grep -qE "^(fix|perf)$scope: " <<<"$subjects"; then
        bump="patch"
    else
        echo_t ci.version.2 "${last:-le début}" >&2
        return 0
    fi
    if [ -z "$last" ]; then
        echo_t ci.version.3 >&2
        echo "${INITIAL_VERSION:-0.1.0}"
        return
    fi
    IFS=. read -r major minor patch <<<"${last#v}"
    major="${major:-0}" minor="${minor:-0}" patch="${patch:-0}"
    case "$bump" in
        major) major=$((major + 1)) minor=0 patch=0 ;;
        minor) minor=$((minor + 1)) patch=0 ;;
        patch) patch=$((patch + 1)) ;;
    esac
    echo_t ci.version.4 "$bump" "${last:-aucun tag}" >&2
    echo "$major.$minor.$patch"
}

notes() {
    local tab=$'\t' commits breaking_body breaking s h
    commits="$(git log --no-merges --reverse --format="%s$tab%h" "$range")"
    breaking_body="$(git log --no-merges --format=%h -E --grep='^BREAKING[ -]CHANGE: ' "$range")"
    breaking=""
    while IFS="$tab" read -r s h; do
        [ -n "$s" ] || continue
        if grep -qE "^[a-z]+$scope!: " <<<"$s" || grep -qx "$h" <<<"$breaking_body"; then
            breaking="$breaking- $s ($h)"$'\n'
        fi
    done <<<"$commits"
    intro
    t ci.version.breaking
    [ -z "$breaking" ] || printf '### ⚠ %s\n\n%s\n' "$REPLY" "$breaking"
    t ci.version.features
    section "$REPLY" "^feat$scope!?: "
    t ci.version.fixes
    section "$REPLY" "^(fix|perf)$scope!?: "
    t ci.version.maintenance
    section "$REPLY" "^(build|ci|chore|docs|refactor|style|test|revert)$scope!?: "
    echo_t ci.version.5 "${last:-le début du projet}"
}

# Introduction des notes, assemblée sans rien inventer : tickets livrés
# (« Ticket : #N » des commits ; titres lus par gh s'il répond), actions
# demandées (BREAKING CHANGE, « À faire : »), commande de mise à jour
# (releaseUpdate). Chaque partie vide est omise.
intro() {
    local corps numeros n infos titre type feats="" fixes="" autres="" faire liste="" maj illisibles=""
    corps="$(git log --no-merges --reverse --format=%B "$range")"
    numeros="$(grep -oE '^Tickets? *: *#[0-9]+' <<<"$corps" | grep -oE '[0-9]+' | awk '!vu[$0]++' || true)"
    if [ -n "$numeros" ] && command -v gh >/dev/null; then
        for n in $numeros; do
            infos="$(gh issue view "$n" --json title,labels \
                --jq '[.title, ([.labels[].name | select(startswith("type: "))][0] // "")] | @tsv' 2>/dev/null)" ||
                { illisibles="$illisibles #$n"; continue; }
            IFS="$tab" read -r titre type <<<"$infos"
            case "$type" in
                "type: feat") feats="$feats- $titre (#$n)"$'\n' ;;
                "type: fix") fixes="$fixes- $titre (#$n)"$'\n' ;;
                *) autres="$autres- $titre (#$n)"$'\n' ;;
            esac
            liste="$liste $n"
        done
    fi
    # Tickets cités mais illisibles (dépôt privé sans issues: read) : signalés,
    # les notes restent sur la sortie standard
    [ -z "$illisibles" ] || { t ci.version.unreadable "$illisibles"; echo "::warning::$REPLY" >&2; }
    if [ -n "$feats$fixes$autres" ]; then
        t ci.version.summary
        printf '### %s\n\n%s\n' "$REPLY" "$feats$fixes$autres"
    fi
    faire="$(sed -nE 's/^(BREAKING[ -]CHANGE|À faire|A faire|To do) *: *(.+)$/- \2/p' <<<"$corps" | awk '!vu[$0]++' || true)"
    if [ -n "$faire" ]; then
        t ci.version.todo
        printf '### %s\n\n%s\n\n' "$REPLY" "$faire"
    fi
    cfg_r releaseUpdate ""
    maj="$REPLY"
    if [ -n "$maj" ]; then
        t ci.version.update
        # shellcheck disable=SC2016 # accents graves Markdown, pas une substitution
        printf '### %s\n\n`%s`\n\n' "$REPLY" "$maj"
    fi
    if [ -n "$liste" ]; then
        liste="$(tr ' ' '\n' <<<"$liste" | sed '/^$/d' | sort -n | sed 's/^/#/' | paste -sd, - | sed 's/,/, /g')"
        t ci.version.tickets
        printf '### %s\n\n%s\n\n' "$REPLY" "$liste"
    fi
}

# Notes de la PR de livraison (branche d'intégration ou instantané livraison/*)
# mergée en $1 : sa description sans la phrase d'en-tête (premier paragraphe)
# ni le pied (à partir de « --- ») ; sinon, notes recalculées
notes_livraison() {
    local sha corps
    sha="$(git rev-parse "$1")"
    corps="$(gh api "repos/{owner}/{repo}/commits/$sha/pulls" --jq "[.[] | select(.merged_at != null
        and (.head.ref == \"${INTEGRATION:-develop}\" or (.head.ref | startswith(\"livraison/\"))))][0].body // empty" \
        2>/dev/null || true)"
    corps="$(tr -d '\r' <<<"$corps" | awk 'fin { next } f == 0 { if ($0 == "") f = 1; next } /^---$/ { fin = 1; next } { print }')"
    if [ -n "$(tr -d '[:space:]' <<<"$corps")" ]; then
        printf '%s\n' "$corps"
    else
        notes
    fi
}

section() { # titre, motif sur le sujet
    local lines
    lines="$(grep -E "$2" <<<"$commits" | grep -vE '^chore\(release\): ' |
        sed -E "s/^(.*)$tab(.*)$/- \1 (\2)/" || true)"
    [ -z "$lines" ] || printf '### %s\n\n%s\n\n' "$1" "$lines"
}

case "$cmd" in
    next) next ;;
    notes) notes ;;
    notes-livraison) notes_livraison "$ref" ;;
    *) echo_t ci.version.usage >&2; exit 2 ;;
esac
