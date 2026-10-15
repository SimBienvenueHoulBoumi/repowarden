# Moving from repogarde 3 to repowarden 4

**lefthook is no longer supported** since v4.0.0, and **repogarde is called repowarden** since v4.1.0. The old names are still read throughout v4, with a warning: nothing breaks on the day you update. They will be ignored in v5.

## What changes

| Before (v3) | After (v4) | In v4 |
|---|---|---|
| `npm install -g @simbie/repogarde`, `repogarde` command | `npm install -g repowarden`, `repowarden` command | `repogarde` forwards to `repowarden`, with a warning |
| `.repogarde.conf`, `[repogarde]` section | `.repowarden.conf`, `[repowarden]` section | old file read; the new one wins |
| `git config repogarde.*` | `git config repowarden.*` | old keys read; `repowarden install` renames them |
| `REPOGARDE_*` variables | `REPOWARDEN_*` variables | old ones read; the new ones win |
| project hooks in `.repogarde/<hook>` | `.repowarden/<hook>` | old folder run when the new one is absent |
| `uses: SimBienvenueHoulBoumi/repogarde@v3` (action) | `uses: simdevWarden/repowarden@v4` | the action keeps working (GitHub redirects the renamed repository) |
| `uses: SimBienvenueHoulBoumi/repogarde/.github/workflows/<file>.yml@v3` (reusable workflow) | `uses: simdevWarden/repowarden/.github/workflows/<file>.yml@v4` | **broken**: GitHub does not redirect reusable workflows; the run fails without starting any job, and releases, tickets and cleanup stop silently. Fix this first |
| required check `repogarde` | required check `repowarden` | run `repowarden proteger` again |
| lefthook (`lefthook.yml`, `lefthook-remote.yml`) | removed | lefthook hook ignored, with the steps to follow |
| site `…github.io/repogarde/` | `…github.io/repowarden/` |  |

## On each machine

```bash
repogarde uninstall --global          # with the old package
npm uninstall -g @simbie/repogarde
npm install -g repowarden
repowarden install --global           # also renames the old repogarde.* keys
repowarden                            # check: machine status and next step
```

## In each project

**In one command**, at the project root: `repowarden migrer` performs steps 1 to 3, completes an outdated ticket tracking (`push`, review, assignment, closing events: prefilled draft PR on the first push), reports what remains (lefthook hooks, `REPOGARDE_*` secrets to recreate, files still mentioning repogarde, labels to create with `repowarden tickets init`) and does nothing on a project already migrated. `repowarden migrer --pr` does the same on a `chore/migration-repowarden-v4` branch, then commits, pushes and opens the PR. `--hooks` sets aside the leftover lefthook hooks in `.git/hooks`. The details, to check or migrate by hand:

1. Rename `.repogarde.conf` to `.repowarden.conf`, and its `[repogarde]` section to `[repowarden]`; set `version = 4` in it.
2. Rename the `.repogarde/` folder to `.repowarden/`, if it exists.
3. In workflows, **reusable workflows first** (`release-auto.yml`, `tickets.yml`, `nettoyage-branches.yml`, `npm-publish.yml`): replace **the whole path**, not just the version. Changing `@v3` to `@v4` without changing the repository fixes nothing:
   - `SimBienvenueHoulBoumi/repogarde/.github/workflows/release-auto.yml@v3` → `simdevWarden/repowarden/.github/workflows/release-auto.yml@v4`
   - likewise for every `uses:` that does not start with `simdevWarden/repowarden/`.

   Symptom of a forgotten line: a failed run **without any job**. Then the action: `simdevWarden/repowarden@v4`, and the `REPOGARDE_*` variables to `REPOWARDEN_*`.
4. Project using lefthook: move its commands to `.repowarden/<hook>`, then `lefthook uninstall` and delete `lefthook.yml`.
5. Update branch protection, since the required check is now called `repowarden`: `repowarden proteger`. An old ruleset requiring `repogarde` is taken over, whatever its name; `repowarden proteger --verifier` reports any that remain.
