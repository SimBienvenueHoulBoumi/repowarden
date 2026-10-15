#!/usr/bin/env bats
# Bot d'organisation (bin/bot) : gh simulé (dépôts de l'installation,
# configuration, rulesets, issues), proteger et migrer simulés, clones locaux

load helpers

BOT="$BATS_TEST_DIRNAME/../bin/bot"

# Projet o/$1 (dépôt nu local) ; $2 : contenu de .repowarden.conf (vide : aucun)
projet() {
    local d="$F/git/o/$1"
    git init -q -b main "$d.src"
    printf 'x\n' >"$d.src/README.md"
    [ -z "${2:-}" ] || printf '%b' "$2" >"$d.src/.repowarden.conf"
    git -C "$d.src" add -A
    git -C "$d.src" -c user.name=t -c user.email=t@e.com -c core.hooksPath=/dev/null commit -q -m "chore: init"
    git clone -q --bare "$d.src" "$d.git"
    if [ -n "${2:-}" ]; then printf '%b' "$2" >"$F/conf/$1"; fi
    GH_REPOS="${GH_REPOS:-} o/$1"
}

setup() {
    require jq
    F="$BATS_TEST_TMPDIR/f"
    mkdir -p "$F/bin" "$F/fakebin" "$F/git/o" "$F/conf" "$F/rulesets"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE/log"
case "$*" in
    "api installation/repositories"*) for r in $GH_REPOS; do echo "$r"; done ;;
    "api -H Accept: application/vnd.github.raw repos/o/"*"/contents/.repowarden.conf")
        n="${4#repos/o/}"; n="${n%%/*}"; cat "$FAKE/conf/$n" 2>/dev/null || exit 1 ;;
    "api -H Accept: application/vnd.github.raw"*) exit 1 ;;
    "api repos/o/"*"/rulesets --jq "*) n="${2#repos/o/}"; n="${n%%/*}"; jq -r "$4" "$FAKE/rulesets/$n" 2>/dev/null ;;
    "api repos/o/"*"/rulesets/"*) n="${2#repos/o/}"; n="${n%%/*}"; jq -c '.[0]' "$FAKE/rulesets/$n" | jq -r "$4" ;;
    "issue list"*) cat "$FAKE/issues" 2>/dev/null ;;
    "issue edit"* | "issue create"*) while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$FAKE/issue-body"; shift; done ;;
esac
exit 0
GH
    # proteger et migrer simulés : journal, puis comportement selon le dépôt
    cat >"$F/fakebin/proteger" <<'SH'
#!/usr/bin/env bash
r=""; v=""; c=""
while [ $# -gt 0 ]; do case "$1" in --repo) r="$2"; shift ;; --checks) c="$2"; shift ;; --verifier) v=1 ;; esac; shift; done
echo "proteger $r checks=$c${v:+ verifier}" >>"$FAKE/log"
if [ -n "$v" ]; then [[ " ${PROT_A_JOUR:-} " == *" $r "* ]] && exit 0; echo "✖ Règles périmées"; exit 1; fi
[[ " ${PROT_REFUS:-} " == *" $r "* ]] && { echo "✖ Ruleset « repowarden » refusé par GitHub : Validation Failed"; exit 1; }
exit 0
SH
    cat >"$F/fakebin/migrer" <<'SH'
#!/usr/bin/env bash
n="$(basename "$PWD")"
echo "migrer $n $* ident=$(git config user.name)" >>"$FAKE/log"
case " ${MIG_PR:-} " in
    *" $n "*) echo "✔ PR de migration ouverte (chore/migration-repowarden-v4)." ;;
    *) echo "✔ Rien à migrer : le projet utilise déjà les noms de repowarden." ;;
esac
SH
    chmod +x "$F/bin/gh" "$F/fakebin/"*
    export PATH="$F/bin:$PATH" FAKE="$F" REPOWARDEN_BIN="$F/fakebin" REPOWARDEN_BOT_GIT="file://$F/git"
    export REPOWARDEN_BOT_NAME="repowarden-bot-o[bot]" GH_REPOS=""
    projet a ""
    projet b '[repowarden]\n    bot = off\n'
    projet c '[repowarden]\n    requiredChecks = repowarden,tests\n'
    projet d '[repowarden]\n    bot = pr\n'
    projet e '[repowarden]\n'
    printf '[{"id": 5, "name": "repowarden", "rules": [{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "repowarden"}, {"context": "build"}]}}]}]' >"$F/rulesets/e"
    export GH_REPOS
}

@test "bot : projets adoptes seulement, mode du projet respecte, verifications jamais retirees" {
    MIG_PR="o_c" run "$BOT" --rapport "$F/rapport.md"
    [ "$status" -eq 0 ]
    # non adopté et off : ni clone, ni protection, ni migration
    ! grep -q "o/a\|o_a\|o/b \|o_b" <(grep -E "^(proteger|migrer)" "$F/log")
    # auto : vérifiée puis appliquée, avec requiredChecks ; migration par PR
    grep -q "^proteger o/c checks=repowarden,tests verifier$" "$F/log"
    grep -q "^proteger o/c checks=repowarden,tests$" "$F/log"
    grep -q "^migrer o_c --pr ident=repowarden-bot-o\[bot\]$" "$F/log"
    # pr : vérifiée, jamais appliquée
    grep -q "^proteger o/d checks=repowarden verifier$" "$F/log"
    ! grep -q "^proteger o/d checks=repowarden$" "$F/log"
    # sans requiredChecks : celles du ruleset en ligne, gardées
    grep -q "^proteger o/e checks=repowarden,build$" "$F/log"
    # rapport : une ligne par dépôt
    grep -q '^| `o/a` | — | non adopté' "$F/rapport.md"
    grep -q '^| `o/b` | off | ignoré' "$F/rapport.md"
    grep -q '^| `o/c` | auto | ✔ appliquée | ✔ PR ouverte |$' "$F/rapport.md"
    grep -q '^| `o/d` | pr | ⚠ périmée : repowarden proteger | rien à migrer |$' "$F/rapport.md"
    [[ "$output" == *"Rapport du bot repowarden"* ]]
}

@test "bot --dry-run : rien d'applique, migration dans le clone jetable" {
    run "$BOT" --dry-run --repo o/c
    [ "$status" -eq 0 ]
    grep -q "^proteger o/c checks=repowarden,tests verifier$" "$F/log"
    ! grep -q "^proteger o/c checks=repowarden,tests$" "$F/log"
    grep -q "^migrer o_c  ident=" "$F/log"
    [[ "$output" == *"Aperçu (dry-run)"* ]]
    ! grep -q "installation/repositories" "$F/log"
}

@test "bot : une erreur n'arrete pas les autres projets, detail dans le rapport, echec a la fin" {
    printf '[repowarden]\n    bot = peut-etre\n' >"$F/conf/b"
    PROT_REFUS="o/c" run "$BOT" --rapport "$F/rapport.md"
    [ "$status" -ne 0 ]
    grep -q '^| `o/b` | `peut-etre` | ✖ bot = peut-etre : auto, pr ou off attendu' "$F/rapport.md"
    grep -q '^| `o/c` | auto | ✖ Ruleset « repowarden » refusé par GitHub : Validation Failed |' "$F/rapport.md"
    grep -q '^| `o/e` | auto | ✔ appliquée' "$F/rapport.md"
    [[ "$output" == *"2 erreur(s)"* ]]
}

@test "bot : protection a jour -> rien d'applique" {
    PROT_A_JOUR="o/c" run "$BOT" --repo o/c --rapport "$F/rapport.md"
    [ "$status" -eq 0 ]
    ! grep -q "^proteger o/c checks=repowarden,tests$" "$F/log"
    grep -q '^| `o/c` | auto | à jour |' "$F/rapport.md"
}

@test "bot rapport : issue unique, creee puis mise a jour" {
    printf '## Rapport\n' >"$F/rapport.md"
    run "$BOT" rapport "$F/rapport.md"
    [ "$status" -eq 0 ]
    grep -q "^gh issue create --title Rapport du bot repowarden" "$F/log"
    echo 42 >"$F/issues"
    : >"$F/log"
    run "$BOT" rapport "$F/rapport.md"
    grep -q "^gh issue edit 42 " "$F/log"
    ! grep -q "issue create" "$F/log"
    grep -q '## Rapport' "$F/issue-body"
}

@test "bot init : workflow du depot de pilotage, jamais ecrase" {
    setup_repo
    run "$BOT" init
    [ "$status" -eq 0 ]
    grep -q 'uses: simdevWarden/repowarden/.github/workflows/bot.yml@v4' .github/workflows/bot.yml
    grep -q 'app-key: ${{ secrets.REPOWARDEN_BOT_KEY }}' .github/workflows/bot.yml
    if command -v actionlint >/dev/null; then actionlint .github/workflows/bot.yml; fi
    echo "# perso" >.github/workflows/bot.yml
    run "$BOT" init
    [[ "$output" == *"existe déjà"* ]]
    [ "$(cat .github/workflows/bot.yml)" = "# perso" ]
}
