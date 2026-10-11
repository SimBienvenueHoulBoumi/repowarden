# shellcheck shell=bash
# Suivi des tickets, vérification « ticket » d'une PR (statut de commit
# exigé par la protection) et merge automatique des PR de travail.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Vrai si le ticket $1 porte une conception écrite par un mainteneur (commentaire
# « Conception retenue ») : le code suit une conception relue, pas l'inverse
conception_ecrite() {
    local corps
    corps="$(gh issue view "$1" --json comments -q '.comments[]
        | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
        | .body' 2>/dev/null || true)"
    grep -qi "conception retenue" <<<"$corps"
}

# REPLY = premier autre ticket que $2 cité par un commit de la PR $1 (« Ticket : #M »)
autre_ticket_r() {
    local cites n
    cites="$(gh pr view "$1" --json commits -q '.commits[].messageBody' 2>/dev/null || true)"
    REPLY=""
    for n in $(grep -oiE '^[[:space:]]*tickets?[[:space:]]*:[[:space:]]*#[0-9]+' <<<"$cites" | grep -oE '[0-9]+' || true); do
        if [ "$n" != "$2" ]; then REPLY="$n"; return 0; fi
    done
    return 1
}

# Vérification « ticket » (statut de commit) de la PR $1, commit $2, tickets
# $3, branche $4. Contrôles (pas des consignes) : un seul ticket, validé,
# porté par la branche (type/N-sujet), avec sa conception écrite ; aucun
# commit d'un autre ticket.
verifier() {
    local pr="$1" sha="$2" tickets="$3" head="${4:-}" n attente="" liste
    for n in $tickets; do est_valide "$n" || attente="$attente #$n"; done
    [ -z "$head" ] || branch_ticket_r "$head"
    if [ -z "$tickets" ]; then
        _tr tk.none; etat=failure
    elif [ "$(wc -w <<<"$tickets")" -gt 1 ]; then
        _tr tk.multi "#${tickets// /, #}"; etat=failure
    elif [ -n "$attente" ]; then
        _tr tk.waiting "${attente# }" "$VALIDE"; etat=failure
    elif [ -n "$head" ] && [ -z "$REPLY" ]; then
        _tr tk.bad_branch "$head" "$tickets"; etat=failure
    elif [ "${REQUIRE_DESIGN:-true}" = true ] && ! conception_ecrite "$tickets"; then
        _tr tk.no_design "$tickets"; etat=failure
    elif autre_ticket_r "$pr" "$tickets"; then
        _tr tk.other_ticket "$REPLY" "$tickets"; etat=failure
    else
        liste=""
        for n in $tickets; do liste="$liste #$n"; done
        _tr tk.ok "${liste# }"; etat=success
    fi
    echo "$_T"
    gh api "repos/$GH_REPO/statuses/$sha" -f state="$etat" -f context=ticket \
        -f description="${_T:0:140}" >/dev/null
    [ "$etat" = success ]
}

# Merge automatique (squash) de la PR de travail $1, cible $2, brouillon $3 :
# armé quand elle est prête, vise la branche d'intégration et que son ticket
# est validé (appelé après une vérification réussie) ; désarmé en brouillon.
# Seulement avec le jeton de l'App : un merge fait avec le jeton des Actions ne
# déclencherait aucun workflow (préversion, livraison, tickets).
merge_auto() {
    local pr="$1" base="$2" brouillon="$3"
    [ "${AUTO_MERGE:-true}" = true ] && [ "$base" = "${INTEGRATION:-develop}" ] || return 0
    if [ "$brouillon" = true ]; then
        gh pr merge "$pr" --disable-auto >/dev/null 2>&1 || true
        return 0
    fi
    if [ "${APP_TOKEN:-false}" != true ]; then
        notice_t tk.automerge_no_app "$pr"
        return 0
    fi
    if gh pr merge "$pr" --auto --squash >/dev/null 2>&1; then
        notice_t tk.automerge_armed "$pr"
    else
        notice_t tk.automerge_failed "$pr"
    fi
}
