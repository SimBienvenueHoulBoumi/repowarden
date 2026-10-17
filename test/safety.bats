#!/usr/bin/env bats
# Isolation du travail en cours : fichiers partiellement stagés (pre-commit)
# et tests sur le commit poussé (pre-push). Utilise Go (gofmt, go test).

load helpers

setup() {
    require go
    setup_repo
    initial_commit
    git switch -q -c feat/x
}

@test "spotless : regex limitee aux fichiers stages" {
    source "$HOOKS/lib/common.sh"
    source "$HOOKS/lib/lang.sh"
    run spotless_files_regex <<<"$(printf 'src/A.java\nsrc/B$1.java')"
    [ "$output" = '.*[\\/]src[\\/]A\.java,.*[\\/]src[\\/]B\$1\.java' ]
}

@test "pre-commit : partiellement stage, sans chevauchement -> worktree formate + travail conserve" {
    printf 'module x\n\ngo 1.21\n' >go.mod
    printf 'package main\n\nfunc main() {}\n\n// a\n// b\n// c\n// d\n// fin\n' >main.go
    git add -A && git commit -q -m "chore: base"

    # partie stagée mal formatée (en haut), partie non stagée loin (en bas)
    sed -i.bak 's/^func main() {}$/func main(){  }/' main.go && rm main.go.bak
    git add main.go
    sed -i.bak 's#^// fin$#// fin, travail en cours#' main.go && rm main.go.bak

    run git commit -q -m "reformate main"
    [ "$status" -eq 0 ]
    git show HEAD:main.go | grep -q '^func main() {}$'
    ! git show HEAD:main.go | grep -q 'travail en cours'
    # dossier de travail : formaté ET travail en cours conservé
    grep -q '^func main() {}$' main.go
    grep -q 'travail en cours' main.go
    [ ! -e .git/repowarden-unstaged.patch ] && [ ! -e .git/repowarden-backup ]
}

@test "pre-commit : partiellement stage, avec chevauchement -> worktree intact" {
    printf 'module x\n\ngo 1.21\n' >go.mod
    printf 'package main\n\nfunc main() {}\n' >main.go
    git add -A && git commit -q -m "chore: base"

    printf 'package main\n\nfunc main() {}\n\nfunc A(){  }\n' >main.go
    git add main.go
    printf '\n// travail en cours\n' >>main.go
    before="$(cat main.go)"

    run git commit -q -m "ajoute A"
    [ "$status" -eq 0 ]
    [[ "$output" == *"se chevauchent"* ]] || false
    # commit : formaté, sans le travail en cours
    git show HEAD:main.go | grep -q '^func A() {}$'
    ! git show HEAD:main.go | grep -q 'travail en cours'
    # dossier de travail : exactement comme avant le commit
    [ "$(cat main.go)" = "$before" ]
    [ ! -e .git/repowarden-unstaged.patch ] && [ ! -e .git/repowarden-backup ]
}

@test "pre-commit : suppression non stagee preservee" {
    printf 'module x\n\ngo 1.21\n' >go.mod
    printf 'package main\n\nfunc main() {}\n' >main.go
    echo a >autre.txt
    git add -A && git commit -q -m "chore: base"

    printf 'package main\n\nfunc main(){  }\n' >main.go
    git add main.go
    rm autre.txt

    run git commit -q -m "reformate"
    [ "$status" -eq 0 ]
    [ ! -e autre.txt ]
    git show HEAD:autre.txt >/dev/null
}

@test "pre-push : teste le commit pousse, pas une modification locale qui casse" {
    go_project ok
    git add -A && git commit -q -m "test: ok"
    write_go_test fail # cassé localement, non committé

    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    # modification locale restaurée
    grep -q '!= 2' x_test.go
    [ -z "$(git stash list)" ]
}

@test "pre-push : refuse un commit casse meme si le dossier de travail est corrige" {
    go_project fail
    git add -A && git commit -q --no-verify -m "test: ko"
    write_go_test ok # corrigé localement, non committé
    echo nouveau >untracked.txt

    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"push refusé"* ]] || false
    grep -q '!= 1' x_test.go
    [ -f untracked.txt ]
    [ -z "$(git stash list)" ]
}

@test "pre-push : branche autre que HEAD testee dans un worktree temporaire" {
    go_project ok
    git add -A && git commit -q -m "test: ok"
    git switch -q -c fix/casse
    write_go_test fail
    git commit -q -am "test: ko"
    git switch -q feat/x

    run git push -q origin fix/casse
    [ "$status" -ne 0 ]
    [[ "$output" == *"worktree temporaire"* ]] || false
    [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]

    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : suppression de branche, rien a tester" {
    go_project ok
    git add -A && git commit -q -m "test: ok"
    git push -q origin feat/x
    run git push -q origin --delete feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rien à tester"* ]] || false
}
