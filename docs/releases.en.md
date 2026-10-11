# Versions and releases

Commits in a repowarden project follow the conventional format: the next version and the changelog are derived from them. A reusable workflow turns them into **automatic releases**, with no token to create and no manual step.

## Setup

```yaml title=".github/workflows/release.yml"
name: release

on:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: release
  cancel-in-progress: false

permissions: {}

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions:
      contents: write
      pull-requests: write
      actions: write
      checks: read
      statuses: write
```

Full template: [`templates/project/.github/workflows/release.yml`](https://github.com/SimBienvenueHoulBoumi/repowarden/blob/main/templates/project/.github/workflows/release.yml).

Two prerequisites:

1. *Settings → Actions → General → Workflow permissions*: check **Allow GitHub Actions to create and approve pull requests**;
2. the project's CI workflows accept `workflow_dispatch` (already the case for the `repowarden.yml` template): this is how CI is run on the release PR.

## How it works

| Commits since the last release | New version |
|---|---|
| `fix:`, `perf:` | patch: 1.4.**2** → 1.4.**3** |
| `feat:` | feature: 1.**4**.2 → 1.**5**.0 |
| `feat!:` or `BREAKING CHANGE:` in the footer | major: **1**.4.2 → **2**.0.0 |
| `ci:`, `chore:`, `test:`, `refactor:`, `style:` | no release |

`docs:` triggers a patch only if its section is visible in the changelog (configuration).

On every push to `main`:

1. [release-please](https://github.com/googleapis/release-please) opens or updates the "release x.y.z" PR: changelog and version in the project file;
2. the project's CI is run on this PR; once green, the PR is merged (squash). If `main` moves in the meantime, the PR is recomputed (version and changelog including the new commits) by the next run, then validated again;
3. the `vX.Y.Z` tag and the GitHub release are created.

The checks required by the protection of `main` remain mandatory: without green CI, nothing is merged.

## Merging the release PR: let the bot do it

The release PR is merged **by the workflow itself** as soon as the CI is green, and the release is published in the same run. Merging it by hand works too (the run waiting for its CI then stops cleanly, and the run triggered by your merge publishes), except in one case: if a file in `.github/workflows/` changes on `main` before the release is published, GitHub refuses to let the Actions token create the tag (it would need the `workflow` permission, which this token never has): "Resource not accessible by integration".

The workflow detects it and shows the cause and the exact commands; in short, with an account that has the `workflow` permission:

```bash
gh auth refresh -h github.com -s workflow
gh release create vX.Y.Z --target <merge commit of the PR> --title vX.Y.Z --notes-file notes.md
gh pr edit <PR number> --remove-label "autorelease: pending" --add-label "autorelease: tagged"
```

then run the `release` workflow again.

## Version file

The project type is detected from the files at the root:

| File | Version updated in |
|---|---|
| `pom.xml` | `pom.xml` (Maven) |
| `package.json` | `package.json`, `package-lock.json` |
| `pyproject.toml`, `setup.py` | `pyproject.toml` / `setup.py` |
| `Cargo.toml` | `Cargo.toml`, `Cargo.lock` |
| `Chart.yaml` | `Chart.yaml` (Helm) |
| `go.mod` | none: the tag defines the version |
| `composer.json`, `pubspec.yaml`, `mix.exs` | corresponding file |
| other | `version.txt` |

!!! tip "Changelog in French, monorepo, options"
    A `release-please-config.json` file at the root (with `.release-please-manifest.json`) takes precedence over detection: changelog sections, multiple packages, additional files to version… See the [repowarden configuration](https://github.com/SimBienvenueHoulBoumi/repowarden/blob/main/release-please-config.json) for an example in French.

!!! note "Maven"
    After each release, release-please proposes switching back to `-SNAPSHOT` (PR merged automatically in the same way). To skip it: `"skip-snapshot": true` in `release-please-config.json`.

## develop → main flow (tag mode, recommended)

For a project with two long-lived branches ([`integrationBranch` flow](configuration.md#integration-branch-flow-develop)): `develop` is for testing (pre-releases), `main` for production. **No version is written to files**: it is computed from all the delivered commits and carried by the tag, the notes go into the GitHub release, as [semantic-release recommends](https://semantic-release.gitbook.io/semantic-release/support/faq). repowarden itself works this way.

```yaml title=".github/workflows/release.yml"
on:
  push:
    branches: [main, develop]

concurrency:
  group: release-${{ github.ref_name }}   # one queue per branch
  cancel-in-progress: false

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write }
    with:
      mode: tag

  publish:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    permissions: { contents: write }
    steps:
      - uses: actions/checkout@v7
        with: { ref: "${{ needs.release.outputs.tag_name }}" }
      - run: ./mvnw -B verify -Drevision="${{ needs.release.outputs.version }}"
      - run: gh release upload "${{ needs.release.outputs.tag_name }}" target/*.jar
        env: { GH_TOKEN: "${{ github.token }}" }
```

1. On every merge into `develop`: the **delivery PR** `develop` → `main` (upcoming version, notes) is kept up to date, **without a release**. A test **pre-release** (`vX.Y.Z-next.N`, GitHub "pre-release") is published **at most once a day**, in the evening, if `develop` changed (`preversion-on-push` input for the former behaviour);
2. **a delivery window**, by default on Friday morning (`delivery-schedule` input, cron of the scheduled trigger): a **single** approval request, containing everything accumulated: a **snapshot** of `develop` (`livraison/vX.Y.Z` branch, frozen at the request's commit) and its PR into `main`. Validating it: **one "Approve and deploy" click** on the `production` environment (`delivery-environment` input), from the notification or the run page; the GitHub App then merges the delivery PR (**merge commit**: every commit stays visible), which publishes the `vX.Y.Z` tag and the release on `main`; the version is computed from **all** the delivered commits (merges excluded). Only one validation pending at a time: the latest;
3. **no stable version without a tested pre-release** (`preversion-obligatoire` input, enabled by default): the version published on `main` must have existed as `vX.Y.Z-next.N` on `develop`. A major (v3 → v4) therefore always goes through its `4.0.0-next.N`;
4. **only `develop` goes into `main`**: an urgent fix is a `fix/…` PR into `develop`, labelled **`urgent`**: its merge starts the delivery request right away (without waiting for the window). By hand: *Actions → release → Run workflow* on `develop`. If something still lands directly on `main`, it flows back into `develop` on its own (PR validated by the CI, merged, no key).

Stable versions follow a regular pace: `develop` accumulates, one delivery per window publishes it all as **one** version, minor or major depending on the commits. When it is out, that version's pre-releases are removed from GitHub (on npm they stay: a published version cannot be removed).

!!! note "Approve whenever you want"
    The approval covers the snapshot frozen when the request was made: work merged afterwards into `develop` does not void it, it will go out with the next delivery. A new request (urgency, manual run) replaces the previous one. Only `develop` and its `livraison/*` snapshots can enter `main`, never without approval.

| | `develop`: testing | `main`: production |
|---|---|---|
| Version | pre-release `3.6.0-next.4` (`prerelease_*` outputs) | stable `3.6.0` (`release_created`, `tag_name`… outputs) |
| GitHub release | "pre-release" | release, grouped notes |
| Package (e.g. npm) | `next` tag | `latest` tag |

The project CI must run on pushes to `develop`: its checks apply to the head commit, and therefore to the delivery PR.

## develop → main cycle with version files (cycle mode)

!!! warning "Not recommended: prefer tag mode"
    On `main`, release-please only reads first-level commits: a delivery merged as a merge commit appears as a single "Merge pull request", it does not see the `feat` and `fix` brought from `develop`, and may publish **no** version at all. Tag mode computes the version from all the delivered commits.

To deliver at a chosen pace while keeping the changelog and version files up to date (pr mode): work is integrated into `develop`, `main` only receives deliveries. repowarden itself works this way.

```yaml title=".github/workflows/release.yml"
on:
  push:
    branches: [main, develop]

jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write }
    with:
      mode: cycle
```

1. On every merge into `develop`, a test **pre-release** is published (`vX.Y.Z-next.N`, GitHub "pre-release", `preversion` input), and the **delivery PR** `develop` → `main` is created or updated (upcoming version, notes);
2. merging it (human decision, **merge commit**: release-please must see every commit) starts the pr-mode release on `main`: release PR (changelog, version files) validated by the CI and merged, tag, release;
3. `main` is then merged into `develop` by a PR merged automatically once its checks pass: the next cycle starts from up-to-date version files.

| | `develop`: testing, community | `main`: production |
|---|---|---|
| When | on every merge into `develop` | when the delivery is merged (human decision) |
| Version | pre-release `3.5.0-next.4` | stable `3.5.0`, changelog |
| GitHub release | "pre-release" | release |
| Package (e.g. npm) | `next` tag (job wired to the `prerelease_tag` output) | `latest` tag |

The pre-release is published like a stable version, from the `prerelease_created` and `prerelease_tag` outputs; for npm:

```yaml
  npm-next:
    needs: release
    if: needs.release.outputs.prerelease_created == 'true'
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/npm-publish.yml@v4
    permissions: { contents: read, id-token: write }
    with:
      tag: ${{ needs.release.outputs.prerelease_tag }}
      dist-tag: next
```

Requirements:

- `.repowarden.conf`: `integrationBranch = develop` (mistargeted PRs retargeted to `develop`);
- the CI also runs on pushes to `develop` (its checks apply to the delivery PR);
- `repowarden proteger`: `develop` as the default branch, merge commits allowed into `main`, auto-merge enabled;
- no key or token: the merge back into `develop`, like the release PR, is validated by the CI (started by the workflow) then merged automatically.

## Publishing to npm

A Node project can publish its package on every release, **without a token**: npm checks that the publication comes from the repository and its `release.yml` (trusted publishing) and shows the package provenance. yarn, pnpm and bun install from the same registry. repowarden itself is published this way (`repowarden`).

One-command setup, from the project repository. Everything is published by the pipeline, the first version included:

1. **npm login**, if needed.
2. **Package not on npm yet** (npm only accepts trusted publishing on an existing package):
   - a temporary npm token is created, valid for 7 days and limited to the package scope;
   - it goes straight into the `NPM_TOKEN` secret and is never displayed; the password and 2FA code are asked as hidden input;
   - the `REPOWARDEN_NPM` variable enables the job, then the command waits for the next release to publish the package.
3. **Trusted publishing**: configured with `npm trust github`, no form to fill in. The secret is then deleted and the token revoked. The following releases publish without a token.

If interrupted (Ctrl+C), the command resumes where it left off when run again.

```bash
repowarden npm-publication
```

Then, in `.github/workflows/release.yml`:

```yaml
  npm:
    needs: release
    if: vars.REPOWARDEN_NPM == 'true' && (needs.release.outputs.release_created == 'true' || github.event_name == 'workflow_dispatch')
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/npm-publish.yml@v4
    permissions: { contents: read, id-token: write }
    with:
      tag: ${{ needs.release.outputs.tag_name }}
      # environment: production     # approval before publishing (human validation)
      # directory: packages/ui      # package outside the root
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}   # first publication only
```

Running the `release` workflow manually (Run workflow) publishes the latest release if it is missing from npm. The package is published at the tag version (tag mode included, without a version file). An already published version is skipped: re-running the workflow breaks nothing.

## Inputs and outputs

| Input | Default | Purpose |
|---|---|---|
| `release-type` | detection | release-please type (`maven`, `node`, `python`, `simple`…) |
| `workflows` | detection | workflows run on the release PR; by default those that respond to `pull_request` and `workflow_dispatch` |
| `initial-version` | `0.1.0` | version of the first release (no existing tag) |
| `merge-auto` | `true` | `false`: the release PR is prepared and validated by CI, a human merges it; a review required by the protection is always honored |
| `notify` | `release attente echec` | events posted to the team channel (`webhook` secret): see [Human approval](validation.md#team-channel) |
| `mode` | `pr` | `tag`: develop → main flow, with no release PR and no version file |
| `integration-branch`, `main-branch` | `develop`, `main` | branches for tag mode |
| `config-file`, `manifest-file` | `release-please-config.json`, `.release-please-manifest.json` | release-please configuration |

!!! warning "Workflows that deploy"
    A workflow that deploys when it is not triggered by a PR (site, environment) would be run on the release branch: list the CI workflows explicitly with `workflows:`.

Outputs: `release_created`, `tag_name`, `version`, `major`, `sha`, to chain the project's own publishing:

```yaml
  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with: { ref: "${{ needs.release.outputs.tag_name }}" }
      # mvn deploy, npm publish, docker push…
```

Suspend releases: *Actions → release → Disable workflow*.
