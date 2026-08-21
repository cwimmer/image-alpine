---
title: Architecture
type: architecture
updated: 2026-07-22
confidence: high
---

# Architecture

## Components

| Component | Where | Role |
| --- | --- | --- |
| Upstream Alpine builder | `docker-alpine/` (git submodule) | Vendored copy of `alpinelinux/docker-alpine`; produces an `intermediate` image |
| Published image builder | `dockerfile/Dockerfile` | One-step `FROM intermediate` + `apk update && apk upgrade` |
| Local orchestrator | `Makefile`, `Makefile.update` | Wires submodule update, version bump, `docker build`, tag, push |
| CI workflow | `.github/workflows/publish.yml` | Schedules daily version bumps; builds and pushes; fans out to downstream |
| Version pins | `ALPINE_VERSION`, `ALPINE_SHORT_VERSION`, `ALPINE_LOCAL_VERSION`, `YQ_VERSION` | Drive reproducibility and tag naming |
| Secrets | `DO_REG_USERNAME`, `DO_REG_PASSWORD`, `FANOUT_TOKEN` | DigitalOcean registry auth and downstream dispatch auth |

## Build pipeline (local)

`make all` (the default target) runs `update-submodule -> build -> upload ->
commit-updates`:

1. **Update submodule** (`update-submodule`):
   - `git submodule update --init --recursive` then, inside `docker-alpine/`,
     `git checkout master && git pull && git checkout v<ALPINE_SHORT_VERSION>`.
   - The submodule therefore tracks upstream Alpine's tag for the pinned
     `MAJOR.MINOR` series.
2. **Build** (`build`):
   - Writes a new timestamp into `ALPINE_LOCAL_VERSION`
     (`<short>.YYYY-MM-DDTHH-MM-SS`).
   - `docker build` against `docker-alpine/x86_64` to produce
     `IMAGE_NAME:intermediate`.
   - `docker build` against `dockerfile/` to produce
     `IMAGE_NAME:<ALPINE_LOCAL_VERSION>`.
   - Tags the same image as `IMAGE_NAME:<ALPINE_VERSION>`.
3. **Upload** (`upload`):
   - `docker login` to `registry.digitalocean.com` using env-supplied creds.
   - Pushes both the local-version tag and the Alpine-version tag.
4. **Commit updates** (`commit-updates`):
   - Stages `*_VERSION` files, the submodule pointer, and `.gitmodules`.
   - Commits only if there is a diff (`git diff-index --quiet HEAD || ...`).
   - Pushes back to the repo.

`make update-versions` (delegating to `Makefile.update`) refreshes the version
files independently:

1. `curl http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml`
   -> `latest-releases.yaml` (gitignored).
2. `docker run mikefarah/yq:<YQ_VERSION> yq read ... -j | jq .[0].version`
   -> `ALPINE_VERSION`.
3. `cut -d '.' -f 1-2 ALPINE_VERSION` -> `ALPINE_SHORT_VERSION`.

## CI pipeline (`.github/workflows/publish.yml`)

Triggers: `push` on `main`, schedule `0 6 * * *` UTC, or `workflow_dispatch`.

Three jobs with `contents: write` permission:

1. **`update`** — gated by `if: github.event_name != 'push'`, so it only runs on
   schedule / manual.
   - Checks out with `submodules: recursive`.
   - Runs `make update-versions` then `make update-submodule`.
   - Emits an output `changed=true|false` based on whether `ALPINE_VERSION`
     moved.
   - Runs `make commit-updates` to persist the version bump.
2. **`build-publish`** — gated by
   `needs.update.result == 'skipped'` OR
   `(needs.update.result == 'success' AND
   (github.event_name == 'workflow_dispatch' OR
   needs.update.outputs.changed == 'true'))`.
   - Re-runs `make update-submodule` (in case the prior job advanced it).
   - Runs `make build` and `make upload` with `DO_REG_USERNAME` /
     `DO_REG_PASSWORD` from secrets.
   - Runs `make commit-updates-pipeline` which uses the `[skip ci]` commit
     message so the timestamped local-version bump does not retrigger the
     workflow.
3. **`fanout`** — runs only on `build-publish` success.
   - Reads `.github/downstream-repos.txt`, strips comments/blank lines, joins
     with commas.
   - If both `repos` and `FANOUT_TOKEN` are non-empty, iterates the list and
     sends a `base-image-updated` `repository_dispatch` to each
     `cwimmer/<repo>` via `gh api .../dispatches`.
   - Payload: `{ image, tag: ALPINE_VERSION, local_tag: ALPINE_LOCAL_VERSION }`.

## Data flow

```
                +--------------------+
                | alpinelinux/       |
                | docker-alpine      |
                | (submodule,        |
                | pinned vMAJOR.MINOR) |
                +----------+---------+
                           |
                           v
                +----------+---------+
                | intermediate image |
                | (local build only) |
                +----------+---------+
                           |
                           v
              +------------+-------------+
              | dockerfile/Dockerfile    |
              | apk update && apk upgrade|
              +------------+-------------+
                           |
                  +--------+--------+
                  |                 |
                  v                 v
     :ALPINE_LOCAL_VERSION   :ALPINE_VERSION
                  |                 |
                  +--------+--------+
                           |
                           v
        registry.digitalocean.com/cwimmer/alpine
                           |
                           v
                 downstream image-* repos
                 (via repository_dispatch fanout)
```

## Boundaries

- **No application code** lives in this repo. There is nothing to compile or
  unit-test beyond the Dockerfile and Makefile.
- **The published image is intentionally minimal** — it adds no packages,
  only refreshes the apk index and upgrades installed packages. Any
  customization belongs in the downstream `image-*` repos.
- **Tagging discipline:** `ALPINE_VERSION` only changes when upstream Alpine
  releases. `ALPINE_LOCAL_VERSION` changes on every CI build. The
  `intermediate` tag is only referenced as a `FROM` source and is not in the
  push set.
- **Single integration branch** (`main`); `feat/*` and `fix/*` short-lived
  branches via PR. No `develop` / `release` / `hotfix` branches.

## Source map
- `Makefile` — build orchestration, default target
- `Makefile.update` — version bump pipeline
- `dockerfile/Dockerfile` — published-image definition
- `.gitmodules` — submodule binding
- `.github/workflows/publish.yml` — CI orchestration
- `.github/downstream-repos.txt` — fanout target list
- `README.md` — high-level flow description

## Confidence / gaps
- Solid: two-stage build (intermediate + published), tag scheme, CI
  triggers/gates, fanout payload shape.
- Uncertain / to verify: the `.github/workflows/publish.yml` `update` job
  uses `actions/checkout@v4` with `fetch-depth: 0`; the version bump commit is
  pushed back to `main`. Whether branch-protection rules block bot pushes on
  `main` is not visible from the repo.
