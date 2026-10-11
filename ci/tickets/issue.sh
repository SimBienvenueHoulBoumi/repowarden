# shellcheck shell=bash
# Suivi des tickets, événements de ticket (ci/tickets.sh issue) : validation
# (d'office pour un mainteneur), assignation, fermeture.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Ticket $1 validé : backlog s'il attendait la validation, sa branche, et
# vérification relancée sur les PR ouvertes qui l'attendaient
accepter() {
    local n="$1" pr head sha body base brouillon
    if grep -qxF "$S_AVALIDER" <<<"$(etiquettes "$n")"; then
        statut "$n" "$S_BACKLOG"
    fi
    # La branche naît quand le ticket est pris (assigné) : un ticket validé
    # pour plus tard n'a pas de branche qui vieillit en attendant
    if [ -n "$(assignes "$n")" ]; then
        creer_branche "$n"
    else
        _tr tk.validated_waiting "$n"
        gh issue comment "$n" --body "$_T" >/dev/null
    fi
    while IFS=$'\t' read -r pr head sha base brouillon; do
        [ -n "$pr" ] || continue
        body="$(gh pr view "$pr" --json body -q .body)"
        pr_tickets_r "$body" "$head"
        [[ " $REPLY " == *" $n "* ]] || continue
        if verifier "$pr" "$sha" "$REPLY" "$head"; then
            merge_auto "$pr" "$base" "$brouillon"
        fi
    done < <(gh pr list --state open --json number,headRefName,headRefOid,baseRefName,isDraft \
        -q '.[] | [.number, .headRefName, .headRefOid, .baseRefName, .isDraft] | @tsv')
}

cmd_issue() {
    local pr sha head body
    case "$ACTION" in
        opened)
            est_valide "$ISSUE" && return 0
            # Ouvert par un mainteneur (droits d'écriture) : c'est déjà sa
            # décision, validé d'office ; sinon, un mainteneur pose « validé »
            if [ "${AUTO_VALIDATE:-maintainers}" = maintainers ] &&
                est_mainteneur "${ISSUE_ASSOCIATION:-}"; then
                gh issue edit "$ISSUE" --add-label "$VALIDE" >/dev/null
                statut "$ISSUE" "$S_AVALIDER"
                accepter "$ISSUE"
            else
                statut "$ISSUE" "$S_AVALIDER"
            fi
            ;;
        labeled)
            [ "${LABEL:-}" = "$VALIDE" ] || return 0
            accepter "$ISSUE"
            ;;
        assigned)
            # Pris en charge : sa branche (s'il est validé), en cours s'il
            # attendait dans le backlog
            est_valide "$ISSUE" && creer_branche "$ISSUE"
            grep -qxF "$S_BACKLOG" <<<"$(etiquettes "$ISSUE")" && statut "$ISSUE" "$S_ENCOURS"
            return 0
            ;;
        closed)
            # Fermé par GitHub au merge d'une PR liée dans la branche par défaut
            # (develop) : pas encore en production, rouvert en préprod. Une
            # fermeture à la main (sans PR) est respectée.
            if [ "${STATE_REASON:-}" = completed ] && ! grep -qxF "$S_DONE" <<<"$(etiquettes "$ISSUE")"; then
                fermee_par_pr_r "$ISSUE"
                local fpr="${REPLY%% *}" fbase="${REPLY#* }"
                if [ -n "$fpr" ] && [ "$fbase" != "${MAIN:-main}" ]; then
                    gh issue reopen "$ISSUE" >/dev/null
                    statut "$ISSUE" "$S_PREPROD"
                    _tr tk.reopened "$fpr" "$fbase"
                    gh issue comment "$ISSUE" --body "$_T" >/dev/null
                    notice "$_T"
                fi
                return 0
            fi
            # Abandonné : PR fermées, branche supprimée (un ticket terminé est
            # fermé par la release, sa branche est déjà supprimée au merge)
            [ "${STATE_REASON:-}" = not_planned ] || return 0
            branche_du_ticket_r "$ISSUE"
            [ -n "$REPLY" ] || return 0
            local branche="$REPLY"
            while IFS= read -r pr; do
                [ -n "$pr" ] || continue
                _tr tk.abandoned "$ISSUE"
                gh pr close "$pr" --comment "$_T" >/dev/null
            done < <(gh pr list --state open --head "$branche" --json number -q '.[].number')
            gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$branche" >/dev/null
            notice_t tk.branch_deleted "$branche" "$ISSUE"
            ;;
    esac
}
