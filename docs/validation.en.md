# Human approval

repowarden automates what is **mechanical and verifiable**:
- formatting;
- checking a message, a branch name or a PR target;
- computing a version, writing a changelog, creating a tag;
- building and signing a package.

These actions always produce the same result for the same input, and each one is traceable (CI logs, provenance attestations).

What requires **judgment** stays human:
- does this code do what we want?
- is this the right time to deliver?
- can we publish?

The risk is not the machine. It is human approval that is too light. This page describes how to make it mandatory.

## Decision points

| Decision | GitHub mechanism | repowarden |
|---|---|---|
| Review code before it gets in | required approvals; approval dismissed by a new commit; the last pusher cannot approve their own push (except in a solo repository: a single person with write access, no rule requires another person) | `repowarden proteger --relecteurs N` |
| Have sensitive areas reviewed by their owners | `CODEOWNERS` file + required code owner review | `repowarden proteger --codeowners` |
| Decide to publish | deployment environment: the job waits for approval from a designated person | `repowarden proteger --environnement production` |
| Decide to deliver (`develop` flow) | one **"Approve and deploy"** click on the `production` environment (notification, mobile app, run page); the GitHub App then merges the `develop` → `main` delivery PR. `main` requires this successful deployment: nothing enters it without this approval | `tag` mode, `deliveryApproval = deployment` (default; `review`: PR review instead) |
| Keep control over the release PR (`pr` mode) | human merge | `release-auto` with `merge-auto: false` |

With a required review, the release PR is never merged by the bot. The bot prepares it and has CI validate it, then it waits for human approval. Merging it publishes the release.

## Setup

Settings versioned in `.repowarden.conf`, applied by `repowarden proteger` (can be re-run):

```ini
[repowarden]
    requiredReviews = 1              # approvals per PR
    codeOwnerReview = true           # CODEOWNERS review on their files
    unattributedApproval = false     # extra approval for unattributed changes (default false)
    deliveryApproval = deployment    # delivery validated by "Approve and deploy" (review: PR review)
    environment = production         # deployments subject to approval
    environmentReviewers = alice @acme/release  # accounts or teams; default: the current gh user
```

`unattributedApproval` defaults to `false` and `proteger` always sets it explicitly. Otherwise GitHub turns it on: a PR opened by an app (delivery PR, ticket draft PR, opened by the Actions token) would then wait for a human approval, even with no approval required. Human validation of a delivery already goes through `requiredReviews` on `main`.

```text title=".github/CODEOWNERS"
# One pattern per line; the last matching rule wins
*                  @equipe-dev
# Workflows and protection
/.github/          @equipe-plateforme
# Build and dependencies
/pom.xml           @equipe-plateforme
/package.json      @equipe-plateforme
/src/**/security/  @equipe-securite
```

Then, in the workflows, each publishing job declares the environment:

```yaml
  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    environment: production   # waits for approval before running
```

The environment only accepts deployments from protected branches and `v*` tags: a working branch cannot publish.

## Solo project

GitHub does not allow approving your own PR, and `repowarden proteger` grants **no exception**, not even to the administrator: with `requiredReviews = 1` and a single developer, no merge would be possible. For a solo project, the recommended settings:
- `requiredReviews = 0`: CI is the authority on form;
- `environment = production` with yourself as approver: each publication requires a deliberate click.

## Who gets notified

Recipients are designated by **GitHub account or team**, never by email address: a public repository would expose the addresses, and Git history would keep them forever. GitHub then notifies each person according to their preferences (email, mobile, web).

| Who | Where | Example |
|---|---|---|
| Reviewers, per code area | `.github/CODEOWNERS` | `/.github/  @acme/platform` |
| Release approvers | `environmentReviewers` | `alice @acme/release` |
| Team channel (optional) | `REPOWARDEN_WEBHOOK` secret | Slack, Teams, Discord, Mattermost… |

A team (`@organisation/team`) is managed in GitHub: people joining or leaving change no file.

### Team channel

The release workflow can post to a channel: release published, release PR waiting for approval, failure. The incoming webhook address is a **secret**, never stored in the repository:

```bash
gh secret set REPOWARDEN_WEBHOOK      # address pasted with masked input
```

```yaml
jobs:
  release:
    uses: SimBienvenueHoulBoumi/repowarden/.github/workflows/release-auto.yml@v4
    secrets:
      webhook: ${{ secrets.REPOWARDEN_WEBHOOK }}
    with:
      notify: release attente echec   # default: all three
```

The format follows the platform recognised from the address (Slack, Discord, Microsoft Teams; otherwise `{"text"}` for Mattermost, Rocket.Chat…) and the message uses the project's language. A failed delivery is reported but never interrupts a release.

## Traceability and emergency stop

- Every merge, approval, deployment and bypass is recorded (PR history, *Environments* tab, audit log).
- `v*` tags can only be created by the workflows (ruleset "repowarden (tags)"); each published package carries a verifiable provenance attestation.
- Suspend automatic releases: *Actions → release → Disable workflow*.
