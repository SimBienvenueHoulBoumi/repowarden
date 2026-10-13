# Deploying repowarden across an organization

repowarden enforces the same rules on every project (commit messages, branch naming, secrets, formatting, tests) at **three levels**:

| Level | Role | Can be bypassed? |
|---|---|---|
| Developer machine — repowarden hooks (global installation) | Immediate feedback, automatic fixes (formatting, commit prefix) | Yes (`--no-verify`) |
| CI — GitHub action / GitLab template | **Authoritative**: the same checks on every merge request | No |
| Server — branch protection | Blocks merging when CI fails, blocks direct pushes to `main` | No |

Local hooks save time; **CI and branch protection guarantee the rules**.

## 1. Hosting repowarden

The repository must be **readable by all developers and by CI**:

- GitLab: import/mirror the repository into an internal group (e.g. `outils/repowarden`);
- GitHub: public repository, or internal to the organization.

Replace `simdevWarden/repowarden` with that path in the templates (`templates/`).

## 2. Versions and releases (automatic)

Projects can get the same automatic releases: see [Versions and releases](releases.md). Below are the releases of repowarden itself.

Version numbers are **computed automatically** from Conventional Commits by [release-please](https://github.com/googleapis/release-please):

| Commits since the last release | New version |
|---|---|
| `fix: …` | patch: 1.4.**2** → 1.4.**3** |
| `feat: …` | feature: 1.**4**.2 → 1.**5**.0 |
| `feat!: …` or `BREAKING CHANGE:` in the body | major: **1**.4.2 → **2**.0.0 |

On every push to `main`, the `release` workflow:

1. updates the "release x.y.z" PR (changelog + version in the templates);
2. runs CI on that PR and waits for the required checks;
3. merges it, creates the `vX.Y.Z` tag and the release, moves the major tag `vX` and attaches a signed archive.

**No token to create**: the workflow only uses `GITHUB_TOKEN` (it triggers CI through `workflow_dispatch`, the only event type this token is allowed to trigger). Prerequisite: *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*.

To suspend automatic releases: disable the `release` workflow (*Actions → release → Disable workflow*).

Recommended policy for projects: **pin an exact version** (`ref: v1.4.2`) and upgrade it deliberately (Renovate/Dependabot can propose the update). A stricter rule = major version.

## 3. Developer machine

Install repowarden once per machine, for every repository:

```bash
npm install -g repowarden   # internal registry: see "Internal sources" below
repowarden install --global
```

The minimum version a project expects goes in its `.repowarden.conf` (`version`): an outdated machine is warned on every commit, with the update command. The project's own commands go in `.repowarden/<hook>` ([Configuration](configuration.md#project-specific-hooks)).

Recommended tools: `gitleaks` (secrets) and the formatters for the languages in use (see [Technologies](technologies.md)).

A machine without hooks blocks no one: CI runs every check again and is authoritative. `repowarden` (no argument) shows the machine's status and the next step.

## 4. Adopting repowarden in a project

Copy from `templates/project/`:

| File | Role |
|---|---|
| `.github/workflows/repowarden.yml` | GitHub CI (add the `setup-*` steps for the project's tools) |
| `gitlab-ci.yml` | To merge into `.gitlab-ci.yml` (choose an image with the project's tools) |
| `.repowarden.conf` | Shared settings: branch exceptions, disabled steps, custom commands |

`.repowarden.conf` is read **by both the hooks and CI**: an exception agreed on in code review applies everywhere.

With `strict: true` (GitHub) / `REPOWARDEN_STRICT: "true"` (GitLab), a formatting or test tool missing from the CI image fails the check instead of being skipped.

## 5. Protecting branches (server)

### Squash merges

One PR = one commit on `main`, whose message is the **PR title**: a clean changelog, one line per PR. Settings (*Settings → General → Pull Requests*): allow only *squash merging*, default message *Pull request title*. repowarden CI checks that this title follows Conventional Commits; use `!` in the title for a breaking change (`feat!: …`).

### Merged branches: deleted automatically

- Server — GitHub: *Settings → General → Automatically delete head branches*; GitLab: *Settings → Merge requests → Enable "Delete source branch" option by default*.
- `develop` flow: a `release/…` or `hotfix/…` branch is merged twice (into `main` and `develop`); GitHub's automatic deletion would delete it after the first merge. The reusable workflow `nettoyage-branches.yml` keeps it as long as another open PR uses it (`repowarden proteger` then disables automatic deletion):

  ```yaml
  on:
    pull_request:
      types: [closed]
  jobs:
    nettoyage:
      uses: simdevWarden/repowarden/.github/workflows/nettoyage-branches.yml@v4
      permissions: { contents: write, pull-requests: read }
  ```

- Developer machines: after a `git pull`, repowarden's `post-merge` hook deletes local branches whose remote branch is gone and whose changes are all in the current branch (regular merge or squash); a branch with unintegrated work is kept.

### GitHub

**In one command**, based on `.repowarden.conf` (protected branches, `develop` flow) — safe to re-run, `--dry-run` to preview before applying:

```bash
repowarden proteger --checks "repowarden,build"   # comma-separated checks; gh logged in (admin)
```

The script sets up the "repowarden" ruleset (PR required, required checks up to date, no deletion and no force push), the merge methods (squash; with a `develop` flow: merge commit on `main`, **squash only** on `develop` (one commit per work PR: intermediate commits never get in), which becomes the default branch; in this flow, PRs need not be up to date with their target: a delivery's merge commit only exists on `main` and would otherwise block the next delivery), reserves `v*` tags for workflows ("repowarden (tags)" ruleset), uses the PR title as the commit message and allows GitHub Actions to create PRs (automatic releases).

With a `develop` flow, it also creates the `urgent` label if missing: merging a PR with it triggers the delivery request right away.

**Rules up to date?** After updating repowarden or `.repowarden.conf`, `repowarden proteger --verifier` compares the online rules with those `proteger` would set, without changing anything: each difference is listed ("online" / "expected") and the command fails. Pass the same `--checks` as when applying: the list of required checks is not in `.repowarden.conf`, and without `--checks` it is not compared. Note that `repowarden proteger` without `--checks` reduces the required checks to `repowarden` alone.

Manually: *Settings → Rules → Rulesets* (or *Branches → Branch protection rules*) on `main`:

- Require a pull request before merging
- Require status checks to pass → add **`repowarden`**
- Block force pushes
- (optional) Restrict branch names / commit metadata with the [regular expressions](ci.md#server-side-rules)

### GitHub App for workflows

What the Actions token does triggers **no other workflow**: a draft PR opened by ticket tracking has no CI, and an automatic merge would start neither a pre-release nor a delivery. A GitHub App dedicated to the repository removes this limit:

```bash
repowarden app init                  # once: "Create", then "Install"
repowarden app init --administration # + administration right (configuration applied by the CI)
```

The command opens GitHub's creation page, prefilled: minimal permissions (contents, PRs, issues, statuses), no webhook. It stores the identifier (variable `REPOWARDEN_APP_CLIENT_ID`) and the private key (secret `REPOWARDEN_APP_KEY`) without displaying them, then opens the installation page. Workflows then get a one-hour token on each run; without the App, they fall back to the Actions token. The App follows the same rules as everyone: no exception in the rulesets.

### GitLab

- *Settings → Repository → Protected branches*: `main` → *Allowed to push: No one*, *Allowed to merge: Developers*
- *Settings → Merge requests*: **Pipelines must succeed**
- (Premium) *Settings → Repository → Push rules*: branch name and commit message regex ([regular expressions](ci.md#server-side-rules))

## 6. What CI checks

`ci/check.sh` compares the branch with its base (merge request, previous push or default branch):

| Check | Fails if |
|---|---|
| `commits` | a message or the PR title is not Conventional Commits, exceeds 72 characters (format only for dependency bots), or is an unsquashed `fixup!`/`squash!` |
| `branch` | the branch name does not follow `<type>/<subject>` (exceptions aside); in a [`develop` flow](configuration.md#integration-branch-flow-develop), the PR targets the wrong branch (retargeted automatically with `fix-pr`) |
| `secrets` | gitleaks finds a secret in the branch's commits |
| `format` | a modified file is not formatted (the formatter runs, nothing is committed) |
| `tests` | the tests of an affected project fail (monorepo: only modified projects) |
| `deadcode` | **proven** dead code is introduced (unreachable, unused in its scope); candidates only warn ([Dead code](code-mort.md)) |

Errors appear as annotations on GitHub and in the job log on GitLab, with the command to fix them.

## 7. Machine with the global repowarden installation

With `install.sh --global` or `repowarden install --global`, the hooks apply to every repository on the machine, without adding anything to the projects.

A project still configured with lefthook (repowarden 3): since repowarden 4, lefthook is no longer supported. A hook installed by lefthook in `.git/hooks` is ignored, with a warning. Move the project's commands to `.repowarden/<hook>`, the expected version to `.repowarden.conf` (`version`), then run `lefthook uninstall` ([Uninstallation](desinstallation.md)).

## 8. Internal sources (closed network, Nexus, Artifactory…)

repowarden does not download project dependencies: it runs the projects' tools (`mvn`, `gradle`, `npm`, `pip`, `go`…), which use their usual configuration, on developer machines and in CI alike.

| Tool | Point to the internal source |
|---|---|
| Maven | `~/.m2/settings.xml`: `<mirrors>` |
| Gradle | `repositories { maven { url = uri("…") } }`, or an init script in `~/.gradle/init.d/` (plugins: `pluginManagement` in `settings.gradle.kts`) |
| npm, yarn, pnpm | `.npmrc`: `registry=…` (including to install `repowarden`) |
| pip | `pip.conf`: `index-url` |
| Go | `GOPROXY` |
| MegaLinter (Docker) | registry mirror configured on the runner |

What repowarden fetches itself:

| Item | Internal source |
|---|---|
| repowarden (clone installation) | internal Git mirror of the repository: `git clone` URL, `REPOWARDEN_URL` variable of the GitLab template |
| GitHub Action `repowarden@v4` (GitHub Enterprise Server) | repository synced into the organisation ([actions-sync](https://docs.github.com/en/enterprise-server/admin/managing-github-actions-for-your-enterprise/managing-access-to-actions-from-githubcom/manually-syncing-actions-from-githubcom)), then `uses: <organisation>/repowarden@v4` |
| Tools installed in CI (gitleaks, PMD, actionlint) | **recommended**: already present in the runner image, nothing is downloaded then; otherwise `REPOWARDEN_DOWNLOAD_MIRROR` |

`REPOWARDEN_DOWNLOAD_MIRROR` replaces `https://github.com` in downloads, for example an Artifactory or Nexus "generic" repository proxying GitHub releases (`https://artifactory.example.com/artifactory/github`). The SHA-256 checksum **never** comes from the mirror: the default versions' checksums are pinned in repowarden; for another version, provide it in `GITLEAKS_SHA256` or `ACTIONLINT_SHA256`, otherwise the download is refused. A compromised mirror therefore cannot get a modified binary installed.
