#!/usr/bin/env bats
# ci/check.sh : mêmes règles que les hooks, en CI

load helpers

CHECK="$BATS_TEST_DIRNAME/../ci/check.sh"

setup() {
    setup_repo
    # contexte CI : pas de hooks (prepare-commit-msg corrigerait les messages testés)
    mkdir -p "$BATS_TEST_TMPDIR/nohooks"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip # contexte CI : aucune config locale
    initial_commit
    BASE_SHA="$(git rev-parse HEAD)"
    git switch -q -c feat/x
    export REPOWARDEN_BASE="$BASE_SHA" REPOWARDEN_BRANCH=feat/x
    # isole des variables CI de l'environnement d'exécution
    unset GITHUB_ACTIONS GITHUB_BASE_REF GITHUB_HEAD_REF GITHUB_REF_NAME CI_COMMIT_BRANCH \
        CI_MERGE_REQUEST_SOURCE_BRANCH_NAME CI_MERGE_REQUEST_DIFF_BASE_SHA \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME REPOWARDEN_TARGET
}

@test "ci : commits conformes" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    git commit -q --no-verify --allow-empty -m "fix(api): b"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 commit(s) conforme(s)"* ]]
}

@test "ci : commit non conforme refuse" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    git commit -q --no-verify --allow-empty -m "wip"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"« wip »"* ]]
}

@test "ci : fixup! refuse (a squasher avant merge)" {
    git commit -q --no-verify --allow-empty -m "fixup! feat: a"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"squasher"* ]]
}

@test "ci : nom de branche" {
    run "$CHECK" branch
    [ "$status" -eq 0 ]
    REPOWARDEN_BRANCH=Mauvais run "$CHECK" branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"feat/mauvais"* ]]
}

@test "ci : branche detectee depuis les variables GitLab" {
    unset REPOWARDEN_BRANCH
    CI_COMMIT_BRANCH=Mauvais run "$CHECK" branch
    [ "$status" -ne 0 ]
    CI_MERGE_REQUEST_SOURCE_BRANCH_NAME=fix/ok run "$CHECK" branch
    [ "$status" -eq 0 ]
}

@test "ci : tag, pas de verification de branche" {
    unset REPOWARDEN_BRANCH
    CI_COMMIT_TAG=v1.0.0 CI_COMMIT_BRANCH="" run "$CHECK" branch
    [ "$status" -eq 0 ]
}

@test "ci : format non conforme refuse, dossier de travail restaure" {
    require ruff
    printf 'x  =  1\n' >a.py
    git add a.py
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" format
    [ "$status" -ne 0 ]
    [[ "$output" == *"a.py : non formaté"* ]]
    [ -z "$(git status --porcelain)" ]
}

@test "ci : format conforme" {
    require ruff
    printf 'x = 1\n' >a.py
    git add a.py
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" format
    [ "$status" -eq 0 ]
}

@test "ci : tests des projets touches" {
    require make
    printf 'test:\n\t@echo ci-make && exit 1\n' >Makefile
    git add Makefile
    git commit -q --no-verify -m "build: make"
    run "$CHECK" tests
    [ "$status" -ne 0 ]
    [[ "$output" == *"ci-make"* ]]
}

@test "ci : secrets detectes" {
    require gitleaks
    printf 'token = ghp_%s\n' "4Rk9vQ2xLm7TzP0aWc3Ny8BdHs5Ju1Ef6GiX" >config.ini # factice
    git add config.ini
    git commit -q --no-verify -m "feat: config"
    run "$CHECK" secrets
    [ "$status" -ne 0 ]
}

@test "ci : skip via .repowarden.conf versionne" {
    git commit -q --no-verify --allow-empty -m "wip"
    printf '[repowarden]\n\tskip = commit-msg\n' >.repowarden.conf
    git add .repowarden.conf
    git commit -q --no-verify -m "chore: conf"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"Désactivé par .repowarden.conf"* ]]
}

@test "ci : mode strict, outil manquant = echec" {
    printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >package.json
    printf 'const a=1\n' >a.js
    git add -A
    git commit -q --no-verify -m "feat: js"
    run env PATH="$(dirname "$(command -v git)"):/usr/bin:/bin" REPOWARDEN_STRICT=true "$CHECK" format
    [ "$status" -ne 0 ]
    [[ "$output" == *"prettier introuvable"* ]]
}

@test "ci : annotations GitHub" {
    git commit -q --no-verify --allow-empty -m "wip"
    GITHUB_ACTIONS=true run "$CHECK" commits
    [[ "$output" == *"::error title=repowarden::"* ]]
}

@test "ci : verification inconnue" {
    run "$CHECK" nimporte
    [ "$status" -ne 0 ]
}

@test "ci : formateur en erreur (syntaxe) -> echec" {
    require ruff
    printf 'def f(:\n' >casse.py
    git add casse.py
    git commit -q --no-verify -m "feat: casse"
    run "$CHECK" format
    [ "$status" -ne 0 ]
}

@test "ci : titre de PR conforme / non conforme (message du commit en squash)" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    REPOWARDEN_PR_TITLE="feat(api): ajoute la route" run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"Titre de la PR conforme"* ]]
    REPOWARDEN_PR_TITLE="Ajout de la route" run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"Titre de la PR « Ajout de la route »"* ]]
}

@test "ci : requirements.txt sans tests (ex. outils de doc) -> pas d'exigence pytest en strict" {
    mkdir -p docs
    printf 'mkdocs==1.6.1\n' >docs/requirements.txt
    printf '# Doc\n' >docs/index.md
    git add -A
    git commit -q --no-verify -m "docs: site"
    run env REPOWARDEN_STRICT=true PATH="$(dirname "$(command -v git)"):/usr/bin:/bin" "$CHECK" tests
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python : aucun test"* ]]
    [[ "$output" != *"pytest absent"* ]]
}

@test "ci : suffixe (#NN) d'un merge squash non compte dans les 72 caracteres" {
    # 67 caractères écrits + « (#31) » ajouté par GitHub = 73
    git commit -q --no-verify --allow-empty -m "docs(securite): vérification SLSA corrigée, piège du dossier déplacé (#31)"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    git commit -q --no-verify --allow-empty -m "docs: $(printf 'a%.0s' {1..70})"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
}

@test "longueur : caracteres et non octets, meme en locale C (Git Bash Windows)" {
    source "$HOOKS/lib/common.sh"
    LC_ALL=C authored_length "docs(securite): vérification SLSA corrigée, piège du dossier déplacé"
    [ "$REPLY" -eq 68 ]
    authored_length "fix: àéèùçôîï (#12)"
    [ "$REPLY" -eq 13 ]
}

@test "ci : flux develop, cibles de PR autorisees" {
    git config repowarden.integrationBranch develop
    git config repowarden.allowedBranches "main develop release/* release-please--* dependabot/*"
    for paire in feat/x:develop develop:main release/1.2.0:develop hotfix/crash:develop \
        dependabot/maven/x:develop release-please--branches--main:main; do
        REPOWARDEN_BRANCH="${paire%%:*}" REPOWARDEN_TARGET="${paire#*:}" run "$CHECK" branch
        [ "$status" -eq 0 ] || { echo "devrait passer : $paire"; echo "$output"; return 1; }
    done
}

@test "ci : flux develop, instantane de livraison (livraison/vX.Y.Z) admis vers main, meme avec allowedBranches" {
    git config repowarden.integrationBranch develop
    git config repowarden.allowedBranches "main develop"
    REPOWARDEN_BRANCH=livraison/v4.4.0 REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # vers develop : refusee (un instantane ne va que vers main)
    REPOWARDEN_BRANCH=livraison/v4.4.0 REPOWARDEN_TARGET=develop run "$CHECK" branch
    [ "$status" -ne 0 ]
    # toute autre source vers main reste refusee
    REPOWARDEN_BRANCH=release/4.4.0 REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -ne 0 ]
}

@test "ci : flux develop, seul develop entre dans main (hotfix et release compris)" {
    git config repowarden.integrationBranch develop
    for b in hotfix/crash release/1.2.0 fix/x; do
        REPOWARDEN_BRANCH="$b" REPOWARDEN_TARGET=main run "$CHECK" branch
        [ "$status" -ne 0 ] || { echo "devrait être refusée vers main : $b"; return 1; }
    done
}

@test "ci : flux develop, mauvaise cible refusee avec la correction" {
    git config repowarden.integrationBranch develop
    REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"cible attendue develop"* ]]
    [[ "$output" == *"gh pr edit --base develop"* ]]
}

@test "ci : PR depuis une branche persistante -> jamais rouge (inversee sans objet, retour sans titre)" {
    git config repowarden.integrationBranch develop
    # develop vers une branche de travail, main vers autre que develop : sans objet
    for paire in develop:feat/184-x develop:release/1.0.0 main:feat/x; do
        REPOWARDEN_BRANCH="${paire%%:*}" REPOWARDEN_TARGET="${paire#*:}" run "$CHECK"
        [ "$status" -eq 0 ] || { echo "devrait passer : $paire"; echo "$output"; return 1; }
        [[ "$output" == *"sans objet"* && "$output" == *"git merge origin/develop"* ]]
    done
    # retour main -> develop : titre libre (merge commit), le reste verifie
    git commit -q --no-verify --allow-empty -m "fix: a"
    REPOWARDEN_BRANCH=main REPOWARDEN_TARGET=develop REPOWARDEN_PR_TITLE="Main" run "$CHECK" commits branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"titre de la PR n'est pas vérifié"* ]]
    # une PR de travail garde la verification du titre
    REPOWARDEN_TARGET=develop REPOWARDEN_PR_TITLE="Main" run "$CHECK" commits
    [ "$status" -ne 0 ]
}

@test "ci : sans integrationBranch, toute cible acceptee" {
    REPOWARDEN_TARGET=develop run "$CHECK" branch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Cible"* ]]
}

# --- ci/fix-pr.sh (entrée fix-pr de l'action) : gh simulé ----------------------

FIX="$BATS_TEST_DIRNAME/../ci/fix-pr.sh"

# Faux gh : journalise ses arguments ; « pr list » renvoie $GH_DUP (doublon)
fake_gh() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
[ "$1 $2" = "pr list" ] && echo "${GH_DUP:-}"
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GITHUB_ENV="$BATS_TEST_TMPDIR/github_env" PR=7
    : >"$GH_LOG"
    : >"$GITHUB_ENV"
}

# main et develop sur le remote, branche feat/x avec un commit
flux_develop() {
    git config repowarden.integrationBranch develop
    git push -q origin HEAD:main HEAD:develop
    git fetch -q origin
    git commit -q --allow-empty -m "feat(panier): ajoute le panier"
    export HEAD=feat/x HEAD_SHA="$(git rev-parse HEAD)"
}

@test "fix-pr : PR vers main recible vers develop, titre conforme garde" {
    fake_gh
    flux_develop
    BASE=main TITLE="feat: panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr edit 7 --base develop" "$GH_LOG"
    ! grep -q -- "--title" "$GH_LOG"
    grep -q "^REPOWARDEN_FIXED_TARGET=develop$" "$GITHUB_ENV"
    grep -q "^REPOWARDEN_FIXED_BASE=$BASE_SHA$" "$GITHUB_ENV"
}

@test "fix-pr : doublon ferme au lieu d'etre recible" {
    fake_gh
    flux_develop
    GH_DUP=3 BASE=main TITLE="feat: panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr close 7 --comment Doublon de #3" "$GH_LOG"
    ! grep -q -- "--base" "$GH_LOG"
    grep -q "^REPOWARDEN_PR_CLOSED=true$" "$GITHUB_ENV"
}

@test "fix-pr : titre non conforme remplace par le commit unique" {
    fake_gh
    flux_develop
    BASE=develop TITLE="Feat/x" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr edit 7 --title feat(panier): ajoute le panier" "$GH_LOG"
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier): ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : plusieurs commits -> celui au plus fort impact de version" {
    fake_gh
    flux_develop
    git commit -q --allow-empty -m "test: panier"
    git commit -q --allow-empty -m "fix: arrondi"
    export HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="Ajout du panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier): ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : pied BREAKING CHANGE -> ! ajoute au titre" {
    fake_gh
    flux_develop
    git commit -q --allow-empty -m "fix: format" -m "BREAKING CHANGE: nouveau format"
    export HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="wip" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier)!: ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : aucun commit conforme -> titre deduit de la branche" {
    fake_gh
    git config repowarden.integrationBranch develop
    git push -q origin HEAD:main HEAD:develop
    git fetch -q origin
    git commit -q --no-verify --allow-empty -m "wip"
    export HEAD=feat/ajout-du-panier HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="Ajout du panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat: ajout du panier$" "$GITHUB_ENV"
}

@test "titres deduits des branches" {
    source "$BATS_TEST_DIRNAME/../hooks/lib/common.sh"
    git config repowarden.integrationBranch develop
    cfg_load
    for paire in "hotfix/crash-login:fix: crash login" "release/1.2.0:chore(release): 1.2.0" \
        "develop:chore(release): livrer develop sur main" "wip:chore: wip" \
        "feature/a_b:feat: a b"; do
        suggest_pr_title_r "${paire%%:*}"
        [ "$REPLY" = "${paire#*:}" ] || { echo "${paire%%:*} -> « $REPLY »"; return 1; }
    done
    suggest_pr_title_r "feat/$(printf 'mot-%.0s' {1..30})fin"
    header_valid "$REPLY" || { echo "trop long : $REPLY"; return 1; }
}

# --- bin/proteger (protection GitHub d'après .repowarden.conf) : gh simulé --------

PROTEGER="$BATS_TEST_DIRNAME/../bin/proteger"

# Faux gh : branches existantes = $GH_BRANCHES ; journalise les appels
fake_gh_repo() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "repo view"*) echo moi/projet ;;
    "api user --jq .login") echo moi ;;
    "api repos/moi/projet --jq .owner.type") echo "${GH_OWNER_TYPE:-User}" ;;
    "api users/"*) case "$2" in users/moi) echo 101 ;; users/alice) echo 102 ;; *) exit 1 ;; esac ;;
    "api orgs/acme/teams/release --jq .id") echo 900 ;;
    "api orgs/"*) exit 1 ;;
    # branche renommée : GitHub redirige master vers main
    "api repos/moi/projet/branches/master"*) echo main ;;
    "api repos/moi/projet/branches/"*) [[ " $GH_BRANCHES " == *" ${2##*/} "* ]] && echo "${2##*/}" ;;
    # rulesets existants = $GH_RULESETS (JSON), filtrés comme le ferait gh
    "api repos/moi/projet/rulesets --jq "*) jq -r "$4" <<<"${GH_RULESETS:-[]}" ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
}

# Rulesets affichés par --dry-run → JSON (liste) dans $RULESETS
rulesets_json() {
    python3 -c 'import json,sys
d=json.JSONDecoder(); t=sys.stdin.read(); i=t.index("{"); out=[]
while i < len(t):
    if t[i] in " \n": i+=1; continue
    o,i=d.raw_decode(t,i); out.append(o)
print(json.dumps(out))' <<<"$(sed -n '/^{/,$p' <<<"$1")"
}

@test "proteger : flux main seul -> squash, branches supprimees au merge, tags reserves" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==2; b,t=r; \
        assert b["name"]=="repowarden" and b["conditions"]["ref_name"]["include"]==["refs/heads/main"]; \
        assert b["rules"][2]["parameters"]["allowed_merge_methods"]==["squash"]; \
        assert b["rules"][3]["parameters"]["required_status_checks"][0]["context"]=="repowarden"; \
        assert b["rules"][3]["parameters"]["strict_required_status_checks_policy"] is True; \
        assert t["target"]=="tag" and t["conditions"]["ref_name"]["include"]==["refs/tags/v*"]' "$(rulesets_json "$output")"
    [[ "$output" == *"suppression auto des branches : true"* ]]
    [[ "$output" != *"branche par défaut"* ]]
}

@test "proteger : flux develop -> main en merge commit, develop squash ou merge, defaut develop" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden, tests (ubuntu-latest)"
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==4; m,d,t,e=r; \
        assert m["conditions"]["ref_name"]["include"]==["refs/heads/main"]; \
        assert m["rules"][2]["parameters"]["allowed_merge_methods"]==["merge"]; \
        assert d["name"]=="repowarden (develop)" and d["conditions"]["ref_name"]["include"]==["refs/heads/develop"]; \
        assert d["rules"][2]["parameters"]["allowed_merge_methods"]==["squash","merge"]; \
        assert [c["context"] for c in d["rules"][3]["parameters"]["required_status_checks"]]==["repowarden","tests (ubuntu-latest)"]; \
        assert m["rules"][3]["parameters"]["strict_required_status_checks_policy"] is False; \
        assert d["rules"][3]["parameters"]["strict_required_status_checks_policy"] is False; \
        assert m["bypass_actors"]==[] and d["bypass_actors"]==[]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==0; \
        assert m["rules"][4]=={"type":"required_deployments","parameters":{"required_deployment_environments":["production"]}}; \
        assert m["rules"][2]["parameters"]["require_last_push_approval"] is False; \
        assert d["rules"][2]["parameters"]["required_approving_review_count"]==0; \
        assert len(d["rules"])==4; \
        assert e["reviewers"]==[{"type":"User","id":101}] and e["prevent_self_review"] is False; \
        assert t["name"]=="repowarden (tags)"' "$(rulesets_json "$output")"
    [[ "$output" == *"suppression auto des branches : false"* ]]
    [[ "$output" == *"branche par défaut : develop"* ]]
    [[ "$output" == *"livraison vers main : approbation du déploiement « production »"* ]]
    # sans workflow de nettoyage : avertissement ; avec : rien
    [[ "$output" == *"ajouter un workflow qui appelle nettoyage-branches.yml"* ]]
    mkdir -p .github/workflows
    printf 'jobs:\n  n:\n    uses: o/r/.github/workflows/nettoyage-branches.yml@v4\n' >.github/workflows/nettoyage.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden"
    [[ "$output" != *"nettoyage-branches.yml"* ]]
    [[ "$output" == *"merge automatique des PR de travail vers develop : true"* ]]
    git config repowarden.autoMergeWork false
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"merge automatique des PR de travail vers develop : false"* ]]
    git config repowarden.autoMergeWork peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    # deliveryApproval = review : revue de PR, ni règle de déploiement ni environnement
    git config --unset repowarden.autoMergeWork
    git config repowarden.deliveryApproval review
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden"
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==3; m=r[0]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==1 and len(m["rules"])==4' \
        "$(rulesets_json "$output")"
    [[ "$output" == *"livraison vers main : 1 approbation(s) exigée(s)"* ]]
    git config repowarden.deliveryApproval peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    git config --unset repowarden.deliveryApproval
}

@test "proteger : approbation des changements non attribues posee explicitement (false par defaut, reglable)" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); \
        assert all(x["rules"][2]["parameters"]["require_extra_approval_for_unattributed_changes"] is False for x in r if x.get("target")=="branch")' \
        "$(rulesets_json "$output")"
    [[ "$output" == *"changements non attribués : false"* ]]
    git config repowarden.unattributedApproval true
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); \
        assert all(x["rules"][2]["parameters"]["require_extra_approval_for_unattributed_changes"] is True for x in r if x.get("target")=="branch")' \
        "$(rulesets_json "$output")"
    git config repowarden.unattributedApproval peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
}

@test "proteger : relecture exigee (approbations, CODEOWNERS, pas d'auto-approbation du dernier push)" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --relecteurs 2 --codeowners
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; b=json.loads(sys.argv[1])[0]; p=b["rules"][2]["parameters"]; \
        assert p["required_approving_review_count"]==2 and p["require_code_owner_review"] is True; \
        assert p["require_last_push_approval"] is True and p["dismiss_stale_reviews_on_push"] is True' "$(rulesets_json "$output")"
    [[ "$output" == *"contournement explicite"* ]]
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --relecteurs beaucoup
    [ "$status" -ne 0 ]
}

@test "proteger : reglages lus dans .repowarden.conf" {
    require python3
    fake_gh_repo
    git config repowarden.requiredReviews 1
    git config repowarden.codeOwnerReview true
    GH_BRANCHES="main" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"approbations exigées : 1 ; revue des CODEOWNERS : true"* ]]
}

@test "proteger : environnement de deploiement approuve par des personnes" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert e["reviewers"]==[{"type":"User","id":101}] and e["prevent_self_review"] is False; \
        assert e["deployment_branch_policy"]["custom_branch_policies"] is True' "$(rulesets_json "$output")"
    [[ "$output" == *"environnement « production » : approbation de moi"* ]]
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "moi alice"
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert [r["id"] for r in e["reviewers"]]==[101,102] and e["prevent_self_review"] is True' "$(rulesets_json "$output")"
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs inconnu
    [ "$status" -ne 0 ]
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "@acme/release moi"
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert e["reviewers"]==[{"type":"Team","id":900},{"type":"User","id":101}]' "$(rulesets_json "$output")"
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "@acme/inconnue"
    [ "$status" -ne 0 ]
}

@test "proteger : tags -> workflows seuls (organisation), ni deplaces ni supprimes (compte perso)" {
    require python3
    fake_gh_repo
    GH_OWNER_TYPE=Organization GH_BRANCHES="main" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; t=json.loads(sys.argv[1])[-1]; \
        assert [r["type"] for r in t["rules"]]==["creation","update","deletion"]; \
        assert t["bypass_actors"][0]["actor_type"]=="Integration"' "$(rulesets_json "$output")"
    GH_OWNER_TYPE=User GH_BRANCHES="main" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; t=json.loads(sys.argv[1])[-1]; \
        assert [r["type"] for r in t["rules"]]==["update","deletion"]; \
        assert t["bypass_actors"][0]["actor_type"]=="RepositoryRole"' "$(rulesets_json "$output")"
    [[ "$output" == *"compte personnel"* ]]
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --sans-tags
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert all(x["target"]=="branch" for x in r)' "$(rulesets_json "$output")"
}

@test "proteger : rulesets de l'ancien nom (repogarde) repris et renommes, pas doubles" {
    require jq
    fake_gh_repo
    GH_BRANCHES="main" GH_RULESETS='[{"id":7,"name":"repogarde"},{"id":8,"name":"repogarde (tags)"}]' \
        run "$PROTEGER"
    [ "$status" -eq 0 ]
    grep -q "^api -X PUT repos/moi/projet/rulesets/7 " "$GH_LOG"
    grep -q "^api -X PUT repos/moi/projet/rulesets/8 " "$GH_LOG"
    ! grep -q "^api -X POST repos/moi/projet/rulesets" "$GH_LOG"
    # nouveau nom deja present : c'est lui qui est mis a jour
    : >"$GH_LOG"
    GH_BRANCHES="main" GH_RULESETS='[{"id":7,"name":"repogarde"},{"id":9,"name":"repowarden"}]' \
        run "$PROTEGER"
    grep -q "^api -X PUT repos/moi/projet/rulesets/9 " "$GH_LOG"
}

@test "proteger : aucune branche protegee existante -> erreur" {
    fake_gh_repo
    GH_BRANCHES="" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aucune des branches"* ]]
}

@test "ci : agents IA -> auteur, committer ou signature refuses (commits et description de PR), bots acceptes" {
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        git commit -q --no-verify --allow-empty -m "fix: par un agent"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"agent IA (Claude <noreply@anthropic.com>)"* ]]
    [[ "$output" != *"nouvelle fonctionnalité"* ]]
    # signature dans le message
    git reset -q --hard "$REPOWARDEN_BASE"
    git commit -q --no-verify --allow-empty -m "fix: a" -m "Co-Authored-By: Claude Opus <noreply@anthropic.com>"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"signature d'agent IA dans le message"* ]]
    # description de PR (corps du commit en squash)
    git reset -q --hard "$REPOWARDEN_BASE"
    git commit -q --no-verify --allow-empty -m "fix: b"
    REPOWARDEN_PR_BODY=$'Corrige b.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)' run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"Description de la PR"* ]]
    # bots d'automatisation : acceptes
    git reset -q --hard "$REPOWARDEN_BASE"
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
        git commit -q --no-verify --allow-empty -m "chore: par le bot"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    # reglage : agents autorises
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        git commit -q --no-verify --allow-empty -m "fix: agent autorise"
    git config repowarden.allowAgentSignatures true
    run "$CHECK" commits
    [ "$status" -eq 0 ]
}

@test "ci : bots (Dependabot, Renovate) -> format exige, longueur libre" {
    long="fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod group"
    GIT_AUTHOR_EMAIL="49699333+dependabot[bot]@users.noreply.github.com" \
        git commit -q --no-verify --allow-empty -m "$long"
    REPOWARDEN_BRANCH=dependabot/maven/prod REPOWARDEN_PR_TITLE="$long" run "$CHECK" commits
    [ "$status" -eq 0 ]
    GIT_AUTHOR_EMAIL="29139614+renovate[bot]@users.noreply.github.com" \
        git commit -q --no-verify --allow-empty -m "Update dependency x"
    REPOWARDEN_BRANCH=renovate/x run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"« Update dependency x »"* ]]
}

@test "ci : humain -> longueur toujours limitee, aide sans force push en premier" {
    git commit -q --no-verify --allow-empty -m "fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod group"
    REPOWARDEN_PR_TITLE="fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod" run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"72 caractères"* ]]
    [[ "$output" == *"le corriger suffit"* ]]
}

# --- ci/version.sh (releases en mode tag) ----------------------------------------

VERSION="$BATS_TEST_DIRNAME/../ci/version.sh"

c() { git commit -q --no-verify --allow-empty -m "$1"; }

@test "version : aucun tag -> version initiale des le premier fix ou feat, rien sur chore" {
    c "chore: outillage"
    [ -z "$("$VERSION" next 2>/dev/null)" ]
    c "fix: a"
    [ "$("$VERSION" next 2>/dev/null)" = 0.1.0 ]
    [ "$(INITIAL_VERSION=1.0.0 "$VERSION" next 2>/dev/null)" = 1.0.0 ]
}

@test "version : depuis le tag le plus eleve, increment selon les commits" {
    git tag v1.4.2
    c "fix: a"
    [ "$("$VERSION" next 2>/dev/null)" = 1.4.3 ]
    c "feat: b"
    [ "$("$VERSION" next 2>/dev/null)" = 1.5.0 ]
    c "refactor!: c"
    [ "$("$VERSION" next 2>/dev/null)" = 2.0.0 ]
}

@test "version : les preversions (v1.5.0-next.2) ne servent pas de base" {
    git tag v1.4.2
    c "feat: b"
    git tag v1.5.0-next.2
    c "fix: c"
    [ "$("$VERSION" next 2>/dev/null)" = 1.5.0 ]
}

@test "version : BREAKING CHANGE en pied -> majeure" {
    git tag v1.0.0
    git commit -q --no-verify --allow-empty -m "fix: a" -m "BREAKING CHANGE: format change"
    [ "$("$VERSION" next 2>/dev/null)" = 2.0.0 ]
}

@test "version : livraison mergee en squash -> version annoncee par le titre" {
    git tag v1.0.0
    c "chore(release): v1.3.0"
    [ "$("$VERSION" next 2>/dev/null)" = 1.3.0 ]
}

@test "version : notes groupees, incompatibles en tete" {
    git tag v1.0.0
    c "feat: panier"
    c "fix(api): timeout"
    c "feat!: nouvelle API"
    c "docs: guide"
    run "$VERSION" notes
    [ "$status" -eq 0 ]
    [[ "$output" == *"### ⚠ Changements incompatibles"*"- feat!: nouvelle API"* ]]
    [[ "$output" == *"### Fonctionnalités"*"- feat: panier"* ]]
    [[ "$output" == *"### Corrections"*"- fix(api): timeout"* ]]
    [[ "$output" == *"### Maintenance"*"- docs: guide"* ]]
    [[ "$output" == *"_Depuis v1.0.0._"* ]]
}

@test "langue en CI : anglais par defaut, langue du projet si reglee" {
    git commit -q --no-verify --allow-empty -m "wip"
    REPOWARDEN_LANG= CI=true GIT_CONFIG_GLOBAL=/dev/null run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected format <type>(<scope>)"* ]]
    printf '[repowarden]\n\tlang = fr\n' >.repowarden.conf
    REPOWARDEN_LANG= CI=true GIT_CONFIG_GLOBAL=/dev/null run "$CHECK" commits
    [[ "$output" == *"format attendu <type>(<scope>)"* ]]
}

@test "version : titres des notes dans la langue du projet" {
    git tag v1.0.0
    c "feat: panier"
    c "fix: arrondi"
    REPOWARDEN_LANG=en run "$VERSION" notes
    [[ "$output" == *"### Features"*"### Bug fixes"* ]]
    [[ "$output" == *"_Since v1.0.0._"* ]]
}

# --- Code mort (ci/check.sh deadcode) : outils simulés ---------------------------

# Faux ruff et vulture : signalent une ligne de chaque fichier Python listé
fake_python_tools() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/ruff" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "ruff 0.0"; exit 0; }
for f in $(git ls-files '*.py'; git ls-files --others --exclude-standard '*.py'); do
    echo "$f:1:8: F401 [*] \`os\` imported but unused"
done
T
    cat >"$BATS_TEST_TMPDIR/bin/vulture" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "vulture 0.0"; exit 0; }
for f in $(git ls-files '*.py'; git ls-files --others --exclude-standard '*.py'); do
    echo "$f:2: unused function 'aide' (60% confidence)"
done
T
    chmod +x "$BATS_TEST_TMPDIR/bin/ruff" "$BATS_TEST_TMPDIR/bin/vulture"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Base : ancien.py (code mort existant) ; branche : nouveau.py
python_dead_code() {
    echo "requests" >requirements.txt
    printf 'import os\ndef ancienne():\n    pass\n' >ancien.py
    git add -A
    git commit -q --no-verify -m "chore: base"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'import os\ndef aide():\n    pass\n' >nouveau.py
    git add -A
    git commit -q --no-verify -m "feat: nouveau"
}

@test "code mort : seul le nouveau code compte, le prouve bloque" {
    fake_python_tools
    python_dead_code
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"nouveau.py:1 : \`os\` imported but unused (code mort prouvé)"* ]]
    [[ "$output" == *"nouveau.py:2 : unused function 'aide' (60 %) (candidat"* ]]
    [[ "$output" != *"ancien.py"* ]]
    [[ "$output" == *"1 élément(s) de code mort prouvé"* ]]
}

@test "code mort : modes warn (rien ne bloque) et strict (candidats compris)" {
    fake_python_tools
    python_dead_code
    git config repowarden.deadcode warn
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    git config repowarden.deadcode strict
    git config repowarden.deadcodeIgnore "nouveau.py"
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun nouveau code mort"* ]]
}

@test "code mort : outil absent -> signale, sans echec meme en mode strict" {
    # ruff et vulture « absents » : ils échouent à --version (portable, Windows compris)
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    for t in ruff vulture; do printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/$t"; chmod +x "$BATS_TEST_TMPDIR/bin/$t"; done
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    python_dead_code
    REPOWARDEN_STRICT=true run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"ruff / vulture absent"* ]]
}

@test "code mort : sortie PMD (Java) interpretee" {
    mkdir -p "$BATS_TEST_TMPDIR/bin" src/a
    printf '#!/bin/sh\nprintf "src/a/A.java:3:\\tUnnecessaryImport:\\tUnused import x\\n"; exit 4\n' >"$BATS_TEST_TMPDIR/bin/pmd"
    chmod +x "$BATS_TEST_TMPDIR/bin/pmd"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    echo "<project/>" >pom.xml
    git add -A
    git commit -q --no-verify -m "chore: base"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'package a;\n\nimport x;\nclass A {}\n' >src/a/A.java
    git add -A
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"src/a/A.java:3 : Unused import x (code mort prouvé)"* ]]
}

# --- ci/notifier.sh (canal de l'équipe) : curl simulé ---------------------------

NOTIFIER="$BATS_TEST_DIRNAME/../ci/notifier.sh"

fake_curl() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/curl" <<'T'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -d ] && { shift; printf '%s' "$1" >"$CURL_BODY"; }; shift; done
exit "${CURL_EXIT:-0}"
T
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" CURL_BODY="$BATS_TEST_TMPDIR/body.json"
}

@test "notification : format adapte a Slack, Discord, Teams ; texte echappe" {
    require python3
    fake_curl
    REPOWARDEN_WEBHOOK=https://hooks.slack.com/services/x run "$NOTIFIER" ci.notify.released 'acme/app' 'v1.2.0' 'https://x/"y"'
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["text"]=="🚀 acme/app v1.2.0 publiée : https://x/\"y\""' "$CURL_BODY"
    REPOWARDEN_WEBHOOK=https://discord.com/api/webhooks/x run "$NOTIFIER" ci.notify.failure acme/app https://run
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["content"].startswith("❌ acme/app")' "$CURL_BODY"
    REPOWARDEN_WEBHOOK=https://prod-01.westeurope.logic.azure.com/workflows/x run "$NOTIFIER" ci.notify.waiting acme/app 12 https://pr
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert "#12" in d["attachments"][0]["content"]["body"][0]["text"]' "$CURL_BODY"
}

@test "notification : sans adresse rien n'est envoye ; un echec d'envoi ne casse rien" {
    fake_curl
    rm -f "$CURL_BODY"
    REPOWARDEN_WEBHOOK= run "$NOTIFIER" ci.notify.released a v1 u
    [ "$status" -eq 0 ]
    [ ! -e "$CURL_BODY" ]
    CURL_EXIT=22 REPOWARDEN_WEBHOOK=https://hooks.slack.com/x run "$NOTIFIER" ci.notify.released a v1 u
    [ "$status" -eq 0 ]
    [[ "$output" == *"release non affectée"* ]]
}

@test "code mort : script isole sans fichier de projet -> analyse quand meme" {
    fake_python_tools
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'import os\ndef aide():\n    pass\n' >script.py
    git add -A
    git commit -q --no-verify -m "feat: script"
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"script.py:1"*"(code mort prouvé)"* ]]
}

@test "code mort : aucun fichier analysable -> le dire, sans pretendre que tout va bien" {
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    echo note >NOTES.txt
    git add -A
    git commit -q --no-verify -m "docs: note"
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"rien à vérifier"* ]]
    [[ "$output" != *"Aucun nouveau code mort"* ]]
}

@test "code-mort : aucune modification -> message clair, pas aucun langage" {
    git update-ref refs/remotes/origin/main HEAD
    run "$BATS_TEST_DIRNAME/../bin/code-mort"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucune modification par rapport à origin/main"* ]]
    [[ "$output" != *"langage analysable"* ]]
}

# --- ci/merger-pr.sh : validation par la CI puis merge (gh simulé) --------------

fake_gh_merge() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "pr view "*"headRefName"*) echo main ;;
    "pr view "*"headRefOid"*) echo abc123 ;;
    "pr view "*"--json state"*) echo OPEN ;;
    "pr view "*"mergeStateStatus"*) echo CLEAN ;;
    "api repos/"*"/commits/"*) echo abc123 ;;
    "api repos/"*"/rules/branches/"*) echo repowarden ;;
    "run list "*) echo 101 ;;
    "run view 101 --json jobs"*) echo success ;;
    "run view 101 --json url"*) echo https://exemple/run/101 ;;
esac
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GH_REPO=o/r WORKFLOWS=ci.yml BASE=develop GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
    : >"$GH_LOG"
    : >"$GITHUB_OUTPUT"
}

@test "merger-pr : CI lancee, verifications reportees en statut, merge commit" {
    fake_gh_merge
    run bash "$BATS_TEST_DIRNAME/../ci/merger-pr.sh" 9 merge
    [ "$status" -eq 0 ]
    grep -qx "workflow run ci.yml --ref main" "$GH_LOG"
    grep -q "api repos/o/r/statuses/abc123 -f state=success -f context=repowarden" "$GH_LOG"
    grep -qx "pr merge 9 --merge --match-head-commit abc123" "$GH_LOG"
    grep -qx "merged=true" "$GITHUB_OUTPUT"
    # retour vers develop : la branche source (main) n'est jamais supprimée
    ! grep -q "api -X DELETE" "$GH_LOG"
}

@test "merger-pr : merge-auto false -> PR validee, laissee a un humain" {
    fake_gh_merge
    MERGE_AUTO=false run bash "$BATS_TEST_DIRNAME/../ci/merger-pr.sh" 9 squash
    [ "$status" -eq 0 ]
    ! grep -q "^pr merge" "$GH_LOG"
    grep -qx "waiting_pr=9" "$GITHUB_OUTPUT"
}

@test "code-mort : seuls des .md et .yml modifies -> pas d'analyse JavaScript" {
    git update-ref refs/remotes/origin/main HEAD
    printf '# Doc\n' >NOTES.md
    printf 'a: 1\n' >conf.yml
    run "$BATS_TEST_DIRNAME/../bin/code-mort"
    [ "$status" -eq 0 ]
    [[ "$output" != *"JavaScript"* ]]
}

@test "langue : scripts sans configuration complete -> lang du .repowarden.conf (meme en CI)" {
    printf '[repowarden]\n    lang = fr\n' >.repowarden.conf
    run env -u REPOWARDEN_LANG CI=true GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        bash -c "source '$HOOKS/lib/ui.sh'; source '$HOOKS/lib/i18n.sh'; echo \$REPOWARDEN_LANG"
    [ "$output" = fr ]
}
