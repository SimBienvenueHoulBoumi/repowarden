# shellcheck shell=bash
# Suivi des tickets, préversion et release (ci/tickets.sh release) : tickets
# prévenus, ou passés en done et fermés.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

cmd_release() {
    local n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        if [[ "$TAG" == *-* ]]; then
            _tr tk.prerelease "$TAG"
            gh issue comment "$n" --body "$_T" >/dev/null
        else
            _tr tk.released "$TAG"
            statut "$n" "$S_DONE"
            gh issue close "$n" --comment "$_T" >/dev/null
        fi
    done < <(gh issue list --state open --label "$S_PREPROD" --limit 500 --json number -q '.[].number')
}
