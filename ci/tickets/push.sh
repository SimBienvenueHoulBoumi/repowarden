# shellcheck shell=bash
# Suivi des tickets, premier push d'une branche de ticket (PR brouillon) et
# revues (ci/tickets.sh push, revue).
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Premier push sur la branche d'un ticket : PR brouillon vers la branche
# d'intégration, citant le ticket, assignée à l'auteur du push ; ticket en
# cours. Ouverte par le jeton des Actions, elle ne lance pas la CI : elle
# tourne au push suivant, ou au passage « prête pour revue ».
cmd_push() {
    local n pr titre type url
    : "${PUSH_BRANCH:?}" "${SHA:?}"
    [ "${DELETED:-false}" != true ] || return 0
    branch_ticket_r "$PUSH_BRANCH"
    n="$REPLY"
    [ -n "$n" ] || return 0
    # Branche faite hors du ticket (à la main) : inscrite sur le ticket
    inscrire_branche "$n" "$PUSH_BRANCH"
    pr="$(gh pr list --state open --head "$PUSH_BRANCH" --json number -q '.[0].number // empty')"
    [ -z "$pr" ] || return 0
    [ "$(gh api "repos/$GH_REPO/compare/$INTEGRATION...$PUSH_BRANCH" -q .ahead_by)" != 0 ] || return 0
    titre="$(gh issue view "$n" --json title -q .title)"
    type="${PUSH_BRANCH%%/*}"
    case "$type" in feature) type=feat ;; bugfix | hotfix) type=fix ;; esac
    # Titre conventionnel (message du commit en squash) : type: titre du ticket
    titre="$type: $(tr '[:upper:]' '[:lower:]' <<<"${titre:0:1}")${titre:1}"
    authored_length "$titre"
    [ "$REPLY" -le 72 ] || titre="${titre:0:72}"
    url="$(gh pr create --draft --base "$INTEGRATION" --head "$PUSH_BRANCH" --title "$titre" \
        --body "Ticket : #$n" ${PUSHER:+--assignee "$PUSHER"})"
    [ -z "${PUSHER:-}" ] || gh issue edit "$n" --add-assignee "$PUSHER" >/dev/null || true
    est_valide "$n" && statut "$n" "$S_ENCOURS"
    notice_t tk.draft_opened "${url##*/}" "$n"
    verifier "${url##*/}" "$SHA" "$n" "$PUSH_BRANCH" || true
}

# Revue : corrections demandées → le ticket repasse en cours
cmd_revue() {
    local body n
    : "${PR:?}" "${HEAD:?}"
    [ "${REVIEW_STATE:-}" = changes_requested ] || return 0
    body="$(gh pr view "$PR" --json body -q .body)"
    pr_tickets_r "$body" "$HEAD"
    for n in $REPLY; do
        est_valide "$n" && statut "$n" "$S_ENCOURS"
    done
    return 0
}
