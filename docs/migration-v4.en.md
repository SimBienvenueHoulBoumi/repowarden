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
| `uses: SimBienvenueHoulBoumi/repogarde@v3` | `uses: simdevWarden/repowarden@v4` | `@v3` keeps working (GitHub redirects the renamed repository) |
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

1. Rename `.repogarde.conf` to `.repowarden.conf`, and its `[repogarde]` section to `[repowarden]`; set `version = 4` in it.
2. Rename the `.repogarde/` folder to `.repowarden/`, if it exists.
3. In workflows: `simdevWarden/repowarden@v4`, and the `REPOGARDE_*` variables to `REPOWARDEN_*`.
4. Project using lefthook: move its commands to `.repowarden/<hook>`, then `lefthook uninstall` and delete `lefthook.yml`.
5. Update branch protection, since the required check is now called `repowarden`: `repowarden proteger`.
