---
title: Operations
type: operations
updated: 2026-07-22
confidence: high
---

# Operations

How to build, publish, and update versions — both locally (Makefile) and via
CI (GitHub Actions).

## Makefile targets

The default target is `all`, which runs `update-submodule -> build -> upload ->
commit-updates`.

| Target | Purpose | Notes |
| --- | --- | --- |
| `all` | Convenience: full local cycle | `update-submodule build upload commit-updates` |
| `update-versions` | Refresh `ALPINE_VERSION` / `ALPINE_SHORT_VERSION` | Delegates to `Makefile.update` |
| `commit-updates` | Commit + push version bumps and submodule pointer change | No-op if no diff (`git diff-index --quiet HEAD`) |
| `commit-updates-pipeline` | Same as `commit-updates` but message is prefixed `[skip ci]` | Used by CI to avoid retriggering the workflow |
| `update-submodule` | `git submodule update --init --recursive`, then `cd docker-alpine && git checkout master && git pull && git checkout v<ALPINE_SHORT_VERSION>` | Pinned to upstream Alpine's tag for the current `MAJOR.MINOR` |
| `build` | Write timestamp to `ALPINE_LOCAL_VERSION`, build `intermediate` from `docker-alpine/x86_64`, build published image from `dockerfile/`, tag with both `ALPINE_VERSION` and `ALPINE_LOCAL_VERSION` | Two-stage `docker build` |
| `upload` | `docker login` to DigitalOcean registry, push both tags | Requires `DO_REG_USERNAME` / `DO_REG_PASSWORD` in env |
| `pre-commit` | `pre-commit install && pre-commit autoupdate && pre-commit run --all-files` | Local hook maintenance |
| `postCreateCommand` | `echo "Post create command executed"` | No-op, invoked by the devcontainer |

`.PHONY` declares `update-versions` and `commit-updates` (the others are file
targets).

## Local build cycle

```sh
# One-time env setup
direnv allow  # or export DO_REG_USERNAME=... DO_REG_PASSWORD=... manually

# Full cycle
make all

# Or step-by-step
make update-versions
make update-submodule
make build
make upload
make commit-updates
```

The `upload` step is a no-op without registry creds, and `commit-updates`
no-ops if nothing changed (guarded by `git diff-index --quiet HEAD`).

## CI workflow (`.github/workflows/publish.yml`)

Triggers:

- `push` to `main`
- schedule `0 6 * * *` UTC
- `workflow_dispatch`

Concurrency group `publish-main` with `cancel-in-progress: false`. Job-level
`permissions: contents: write` for all three jobs.

### `update` job

Runs only when `github.event_name != 'push'` (so manual + scheduled runs
only). Steps:

1. `actions/checkout@v4` (`ref: main`, `fetch-depth: 0`, `submodules: recursive`).
2. Configure git identity (`github-actions[bot]`).
3. `make update-versions` then `make update-submodule`.
4. Diff `ALPINE_VERSION` before/after -> emit `changed=true|false` output.
5. `make commit-updates` (push the version bump to `main`).

### `build-publish` job

Runs when:

- the `update` job was skipped (`github.event_name == 'push'`), OR
- the `update` job succeeded AND
  - the trigger was `workflow_dispatch` (always build), OR
  - the `update` job reported `changed == 'true'`.

Steps:

1. Checkout with submodules.
2. Configure git identity.
3. `make update-submodule` (idempotent re-sync).
4. `make build`.
5. `make upload` with `DO_REG_USERNAME` / `DO_REG_PASSWORD` from secrets.
6. `make commit-updates-pipeline` to commit the timestamped
   `ALPINE_LOCAL_VERSION` bump using the `[skip ci]` message, preventing an
   infinite retrigger loop.

### `fanout` job

Runs on `build-publish` success. Two steps:

1. **Determine enabled downstream repos (`cfg`):**
   - Read `.github/downstream-repos.txt`, strip comments / blank lines,
     join with commas.
   - Emit `repos=...` and `enabled=true` only if both `repos` and
     `FANOUT_TOKEN` are non-empty.
2. **Dispatch (`base-image-updated`):** if enabled, iterate the comma list,
   for each repo `cwimmer/<repo>` call `gh api
   repos/cwimmer/<repo>/dispatches` with payload:

   ```json
   {
     "event_type": "base-image-updated",
     "client_payload": {
       "image": "registry.digitalocean.com/cwimmer/alpine",
       "tag": "<ALPINE_VERSION>",
       "local_tag": "<ALPINE_LOCAL_VERSION>"
     }
   }
   ```

   `FANOUT_TOKEN` must be a PAT with `repo` scope on the downstream repos.

## Branching / release flow

- `main` is the integration branch and the only branch that publishes images.
- Short-lived `feat/*` and `fix/*` branches; PRs merged into `main`.
- No `develop` / `release` / `hotfix` branches.
- Conventional Commits enforced via commitizen pre-commit hook.
- No git tags; published image tags are the release artifact.

## Source map
- `Makefile` — local target definitions
- `Makefile.update` — `update-versions` sub-target
- `.github/workflows/publish.yml` — CI orchestration and triggers
- `dockerfile/Dockerfile` — what `build` produces
- `README.md` — branching and CI summary

## Confidence / gaps
- Solid: every Makefile target, every CI step, and the trigger/gating logic.
- Uncertain / to verify: the `update` job's `make commit-updates` step pushes
  to `main` from the workflow — branch-protection policy on `main` (if any) is
  not visible from this repo.
