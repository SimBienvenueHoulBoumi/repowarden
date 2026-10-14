#!/usr/bin/env bats
# commit-msg + prepare-commit-msg

load helpers

setup() { setup_repo; initial_commit; }

@test "commit-msg : message conforme accepte" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "fix: corrige un truc"
    [ "$status" -eq 0 ]
    [ "$(subject)" = "fix: corrige un truc" ]
}

@test "commit-msg : message invalide refuse avec l'aide" {
    git switch -q -c wip-x 2>/dev/null
    git config repowarden.skip "secrets branch-name"
    run git commit -q --allow-empty -m "n'importe quoi"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Message de commit invalide"* ]]
    [[ "$output" == *"nouvelle fonctionnalité"* ]]
}

@test "commit-msg : premiere ligne > 72 caracteres refusee" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "fix: $(printf 'a%.0s' {1..80})"
    [ "$status" -ne 0 ]
    [[ "$output" == *"trop longue"* ]]
}

@test "prepare-commit-msg : prefixe deduit de la branche" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "ajoute le bean"
    [ "$(subject)" = "feat(bean): ajoute le bean" ]
}

@test "prepare-commit-msg : alias de branche (bugfix -> fix)" {
    git switch -q -c bugfix/timeout
    git commit -q --allow-empty -m "corrige"
    [ "$(subject)" = "fix(timeout): corrige" ]
}

@test "prepare-commit-msg : scope trop long omis" {
    git switch -q -c fix/un-sujet-vraiment-tres-long
    git commit -q --allow-empty -m "corrige"
    [ "$(subject)" = "fix: corrige" ]
}

@test "prepare-commit-msg : message deja conforme inchange" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "docs: readme"
    [ "$(subject)" = "docs: readme" ]
}

@test "prepare-commit-msg : amend sans double prefixe" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "ajoute"
    GIT_EDITOR=true git commit -q --amend --allow-empty
    [ "$(subject)" = "feat(bean): ajoute" ]
}

@test "repowarden.skip true desactive tout" {
    git config repowarden.skip true
    run git commit -q --allow-empty -m "n'importe quoi"
    [ "$status" -eq 0 ]
}

@test "commit-msg : signatures d'agent IA retirees du message, identite d'agent refusee" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "feat: ajoute un truc" -m "Pourquoi." \
        -m "Co-Authored-By: Claude Opus <noreply@anthropic.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-authored-by: Alice <alice@example.com>"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Signature d'agent IA retirée"* ]]
    msg="$(git log -1 --format=%B)"
    echo "message : $msg"
    [[ "$msg" != *anthropic* && "$msg" != *"Generated with"* ]]
    [[ "$msg" == *"Co-authored-by: Alice <alice@example.com>"* ]]
    # auteur agent : refuse
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        run git commit -q --allow-empty -m "fix: autre"
    [ "$status" -ne 0 ]
    [[ "$output" == *"agent IA"* ]]
    # reglage : agents autorises
    git config repowarden.allowAgentSignatures true
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        run git commit -q --allow-empty -m "fix: autorise" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
    [ "$status" -eq 0 ]
    [[ "$(git log -1 --format=%B)" == *anthropic* ]]
}

@test "commit-msg : type inconnu sur une branche typee -> refuse avec le type le plus proche, pas enveloppe" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "doc: essai"
    [ "$status" -ne 0 ]
    [[ "$output" == *"docs: essai"* ]]
    [ "$(subject)" = "chore: init" ]
    run git commit -q --allow-empty -m "Feat(panier): ajoute"
    [ "$status" -ne 0 ]
    [[ "$output" == *"feat(panier): ajoute"* ]]
}

@test "commit-msg : description vide refusee, pas enveloppee" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "fix:"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Description manquante"* ]]
    [ "$(subject)" = "chore: init" ]
}

@test "prepare-commit-msg : message libre prefixe, corps et references intacts" {
    git switch -q -c feat/panier
    printf 'ajoute le panier\n\nPourquoi : les clients le demandent.\n\nTicket : #12\n' >"$BATS_TEST_TMPDIR/msg"
    git commit -q --allow-empty -F "$BATS_TEST_TMPDIR/msg"
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
    [ "$(git log -1 --format=%b)" = "$(printf 'Pourquoi : les clients le demandent.\n\nTicket : #12')" ]
}

@test "commit-msg : point final retire (meme regle que git cc), majuscule initiale permise" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "docs: README à jour."
    [ "$status" -eq 0 ]
    [ "$(subject)" = "docs: README à jour" ]
}

@test "commit-msg : refus en anglais sans texte francais" {
    git switch -q -c feat/panier
    REPOWARDEN_LANG=en run git commit -q --allow-empty -m "doc: essai"
    [ "$status" -ne 0 ]
    [[ "$output" == *"docs: essai"* ]]
    [[ "$output" != *"inconnu"* && "$output" != *"Astuce"* ]]
}
