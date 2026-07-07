# GitHub Actions Docker Publishing + Main-Based Development — Design

- **Date:** 2026-07-07
- **Status:** Approved (design); implementation pending
- **Scope:** Replace Bitbucket Pipelines with GitHub Actions for publishing the Alpine base image; adopt main-based development; capture remaining modernization work as a prioritized TODO.

## 1. Context

`image-alpine` builds a customized Alpine base image and publishes it to the DigitalOcean
Container Registry (`registry.digitalocean.com/cwimmer/alpine`). It is the root of an image
chain: `alpine` → `image-golang`, `image-hugo`, `image-imagemagick`.

The repository already lives on GitHub (`origin` → `github.com:cwimmer/image-alpine.git`) while
still carrying a `bitbucket-origin` remote and a `bitbucket-pipelines.yml`. This design moves CI to
GitHub Actions and retires the Bitbucket setup.

### Current Bitbucket behavior (to preserve unless noted)

`bitbucket-pipelines.yml` runs on the custom image `cwimmer/build:stable` with a Docker service:

- **`custom.update-dependencies`** (triggered by a Bitbucket schedule/manual run, not visible in
  the YAML): `make update-versions` → `make update-submodule` → print `*_VERSION` files →
  `make commit-updates` (commits the Alpine version bump and pushes).
- **`branches.main`** (on push to `main`), deployment `Digital_Ocean_Registry`:
  `make update-submodule` → `make build` → `make upload` → `make commit-updates-pipeline`
  (commits the new `ALPINE_LOCAL_VERSION` with `[skip ci]`).
- Then **parallel fan-out** via the `atlassian/trigger-pipeline` pipe rebuilds downstream repos:
  `image-golang` (`main`), `image-hugo` (`develop`), `image-imagemagick` (`develop`).

Build/publish mechanics live in the `Makefile`:

- Builds the `docker-alpine/x86_64` submodule as `…/alpine:intermediate`, then builds
  `dockerfile/Dockerfile` (which is `FROM …/alpine:intermediate`).
- Tags `:<ALPINE_LOCAL_VERSION>` (`3.x.<timestamp>`) and `:<ALPINE_VERSION>` (`3.x.y`); pushes both.
- `x86_64` only. Uses raw `docker build` / `docker push`.
- Secrets: `DO_REG_USERNAME`, `DO_REG_PASSWORD`; fan-out used `BITBUCKET_APP_PASSWORD`.

Version discovery lives in `Makefile.update`: it fetches Alpine's `latest-releases.yaml` and parses
it with `docker run mikefarah/yq:3.3.4` (yq **v3** syntax) + `jq`.

## 2. Goals / Non-goals

**Goals**

- Publish the Alpine image from GitHub Actions with the same registry, tags, and conditions.
- Adopt main-based development; remove Gitflow (`develop`) assumptions.
- Provide a config-driven fan-out **stub** that is trivial to enable later.
- Capture remaining modernization work (versions, tooling) as a prioritized TODO.

**Non-goals (this change)**

- Implementing the workflow YAML (a follow-up plan does that).
- Performing dependency/package upgrades.
- Redesigning the application/image architecture.
- Introducing a complex (SemVer/tag-based) release process.
- Migrating downstream repos (`image-golang`/`image-hugo`/`image-imagemagick`) — only the fan-out
  contract and stub are defined here.

## 3. Decisions (resolved)

| Topic | Decision |
| --- | --- |
| Registry | **Keep** `registry.digitalocean.com/cwimmer/alpine`. |
| Triggers | `push: [main]` + daily `schedule` + `workflow_dispatch`. |
| Schedule cadence | **Daily** (`cron: '0 6 * * *'`, UTC). |
| Version files | **Commit all** back (`ALPINE_VERSION`, `ALPINE_SHORT_VERSION`, `ALPINE_LOCAL_VERSION`) — preserve current behavior. |
| Fan-out | **Deferred but stubbed**; enabling later ≈ uncommenting a line + adding a token. |
| Workflow structure | **Approach A**: single `publish.yml` with `update` → `build-publish` → `fanout` jobs. |
| Runner | **`ubuntu-latest`** for all jobs (see §5.1 rationale). |
| Build engine | Keep the `Makefile` as the source of truth for build/upload/commit. |

## 4. Design

### 4.1 Workflow structure & triggers

Single file `.github/workflows/publish.yml`.

- **Triggers:** `push: branches: [main]`, `schedule: - cron: '0 6 * * *'`, `workflow_dispatch`.
- **Runner:** `ubuntu-latest`. Checkout with `actions/checkout@v4`, `fetch-depth: 0`,
  `submodules: recursive`.
- **Permissions:** `contents: write` (for the version commit-back). Default `GITHUB_TOKEN`.
- **Concurrency:** `group: publish-main`, `cancel-in-progress: false` — serializes scheduled and
  push runs so the commit-back and the build job's checkout of `main` never race.

Three jobs:

1. **`update`** — runs only on `schedule` / `workflow_dispatch`
   (`if: github.event_name != 'push'`).
   - Checkout `main`, configure git identity (`github-actions[bot]`).
   - `make update-versions` → `make update-submodule`.
   - Commit + push the Alpine version bump via `make commit-updates` (no-op when nothing changed;
     pushed with `GITHUB_TOKEN`, which by design does **not** re-trigger a workflow).
   - **Output `changed`**: whether `ALPINE_VERSION`/`ALPINE_SHORT_VERSION` actually changed
     (e.g. from `git diff --quiet` before the commit).

2. **`build-publish`** — `needs: [update]`.
   - **Run condition:** run when the `update` job was **skipped** (push events) **or** the `update`
     job **succeeded and** (`event == workflow_dispatch` **or** `update.outputs.changed == 'true'`).
     Expressed as:
     `if: always() && (needs.update.result == 'skipped' || (needs.update.result == 'success' && (github.event_name == 'workflow_dispatch' || needs.update.outputs.changed == 'true')))`.
     This preserves today's behavior: the scheduled path builds **only** when the Alpine version
     bumped; push and manual dispatch always build.
   - Checkout the **tip of `main`** (`ref: main`) so it includes any bump the `update` job just
     pushed (safe because of the concurrency guard).
   - `make update-submodule` → `make build` → `make upload` → `make commit-updates-pipeline`.

3. **`fanout`** — `needs: [build-publish]`, `if: needs.build-publish.result == 'success'`.
   - Config-driven stub (see §4.5). No-ops while the config is empty or the token is absent.

### 4.2 Registry & secrets

- Registry unchanged: `registry.digitalocean.com/cwimmer/alpine`.
- GitHub repository secrets: **`DO_REG_USERNAME`**, **`DO_REG_PASSWORD`**, supplied to the
  `make upload` step via `env:` (Make reads environment variables as Make variables, so
  `$(DO_REG_USERNAME)` / `$(DO_REG_PASSWORD)` resolve unchanged).
- Optional: a GitHub **Environment** named `Digital_Ocean_Registry` to scope these secrets and add
  an approval gate, mirroring the old Bitbucket "deployment". Optional, not required for parity.

### 4.3 Tagging & build (unchanged)

- `make build` builds the `docker-alpine/x86_64` intermediate, then `dockerfile/Dockerfile`, tagging
  `:<ALPINE_LOCAL_VERSION>` and `:<ALPINE_VERSION>`. `make upload` logs in and pushes both tags.
- `x86_64` only; raw `docker build` / `docker push` retained. (buildx/multi-arch are P3 TODOs.)

### 4.4 Version commit-back & loop prevention

- `update` job commits Alpine version bumps (`make commit-updates`).
- `build-publish` job commits `ALPINE_LOCAL_VERSION` via `make commit-updates-pipeline`, whose
  message carries **`[skip ci]`**.
- **Loop prevention is twofold and both mechanisms apply:**
  1. Commits pushed with the default `GITHUB_TOKEN` do **not** trigger new workflow runs (built-in
     GitHub behavior).
  2. The build-publish commit additionally contains `[skip ci]`, which GitHub honors to skip runs.
- A `git config user.name/user.email` step (github-actions[bot]) is added so Make's `git commit`
  has an author. `actions/checkout` persists credentials by default, so `git push` works with
  `contents: write`.

### 4.5 Fan-out stub (config-driven, easy-enable)

**Goal:** enabling a downstream rebuild later should be ≈ uncommenting a line and adding a token.

- **Config file:** `.github/downstream-repos.txt` — one repo per line, all commented out initially:

  ```
  # image-golang
  # image-hugo
  # image-imagemagick
  ```

- **`fanout` job:** reads the non-comment, non-blank lines into a matrix and, for each repo, creates
  a GitHub `repository_dispatch` event:

  ```
  gh api repos/cwimmer/<repo>/dispatches \
    -f event_type=base-image-updated \
    -F client_payload[tag]="$(cat ALPINE_VERSION)" \
    -F client_payload[local_tag]="$(cat ALPINE_LOCAL_VERSION)" \
    -F client_payload[image]="registry.digitalocean.com/cwimmer/alpine"
  ```

- **Auth:** a PAT secret **`FANOUT_TOKEN`** with permission to create `repository_dispatch` events
  on the downstream repos (classic PAT: `repo` scope; fine-grained: "Contents" read/write on the
  target repos).
- **Guard / no-op:** the job does nothing when the config yields no enabled repos or when
  `FANOUT_TOKEN` is unset. Because job-level `if:` cannot read `secrets`, the guard is implemented
  as a first step that computes an `enabled` output from (a) the parsed repo list being non-empty
  and (b) `env.FANOUT_TOKEN != ''`; the dispatch step/matrix runs only when `enabled == 'true'`.

**Downstream contract (documented for when those repos migrate):**

- Event type: `base-image-updated`.
- `client_payload`: `{ image, tag, local_tag }`.
- Downstream repos opt in by adding:

  ```yaml
  on:
    repository_dispatch:
      types: [base-image-updated]
  ```

- `repository_dispatch` targets a repo's **default branch** (`main`), so the old `develop` targets
  for `image-hugo` / `image-imagemagick` disappear naturally as they migrate.

**Enabling later** = uncomment the repo line(s) in `.github/downstream-repos.txt` + add the
`FANOUT_TOKEN` secret. No workflow code changes required.

### 4.6 Main-based development & Gitflow cleanup

- **`main`** is the integration branch. Feature work uses short-lived `feat/*` / `fix/*` branches →
  PR → merge to `main`. No `develop` / `release` / `hotfix` branches.
- **The image tags are the release artifact**, not git tags. The repo has zero git tags today;
  versioning tracks upstream Alpine, not SemVer. Keep conventional-commit **message** linting
  (commitizen) but drop the implied SemVer git-release/tagging story (see §6 for the follow-up
  decision on `.cz.toml`).
- Concrete cleanups in scope:
  - Delete `bitbucket-pipelines.yml`.
  - The two `REF_NAME: 'develop'` fan-out targets become `main` (encoded as commented defaults in
    the fan-out config).
- Out of scope but noted: `Makefile`'s `git checkout master` refers to the **upstream Alpine**
  submodule's branch (`alpinelinux/docker-alpine`), not this repo — left as-is; see §6 TODO to
  verify the upstream branch/tag scheme.
- A short **`README.md`** (none exists today) documenting build, publish, and the main-based flow.
- Optional: branch protection on `main` (require PR + passing checks).

## 5. Runner rationale

### 5.1 Why `ubuntu-latest` and not `cwimmer/build:stable`

Inspection of `cwimmer/build:stable` (pulled 2026-07-07): **Alpine 3.19.1 / musl libc, amd64-only**.
Present: git 2.43, make 4.4.1, python3 3.11.8, yq **3.3.4** (v3), jq 1.7.1, bash. **Missing:**
`docker`, `node`, `hadolint`, `shellcheck`, `yamllint`, `pre-commit`.

Using it as a job `container:` was rejected because:

1. **musl breaks JavaScript actions.** GitHub mounts a glibc-linked Node into the job container to
   run actions like `actions/checkout@v4`; on a musl image it fails without `gcompat`/`libc6-compat`
   and is fragile even then.
2. **No `docker` CLI** in the image — the build/publish steps need it.
3. **No Docker daemon by default** in a container job — would require mounting
   `/var/run/docker.sock`.
4. **Volume-mount correctness bug:** `make update-versions` runs `docker run -v $(PWD):/src …`; from
   inside a container talking to the host daemon, `$(PWD)` is the container path but the daemon
   resolves bind mounts on the host filesystem, so `/src` mounts empty and version parsing silently
   yields wrong output.
5. **No modernization benefit:** it lacks the lint tools and still ships the old yq 3.3.4.

Everything useful it provides (git, make, jq, python) is already on `ubuntu-latest`, which also
gives a native Docker daemon and glibc Node. Decision: retire the image from CI.

## 6. Modernization TODO (prioritized — execute later, with approval)

**P1 — required for the scheduled job to work correctly**

- `YQ_VERSION=3.3.4` uses yq **v3** syntax (`yq read … -j`) which breaks on yq v4. Update
  `Makefile.update` to yq v4 syntax **or** replace the yq step with `jq` (the `latest-releases.yaml`
  is small). *(Confirmed: `cwimmer/build:stable` also ships only yq 3.3.4.)*
- Verify the `docker-alpine` submodule's upstream branch (`master`) and the `v3.x` tag scheme still
  resolve; adjust `make update-submodule` if upstream changed defaults.

**P2 — CI hygiene / tooling**

- Bump pre-commit hooks: commitizen `v2.39.1`, yamllint `v1.28.0`, shellcheck-py `v0.9.0.2`,
  hadolint `v2.12.1-beta` → current (run `pre-commit autoupdate`).
- Add a CI **lint job** (yamllint / hadolint / shellcheck) to replace what the retired
  `cwimmer/build:stable` image bundled — noting the image never actually contained those tools.
- Decide the commitizen/versioning story (`.cz.toml` `version = 0.0.1`, `tag_format = "$version"`):
  keep conventional-commit message linting only, or wire real tag-based releases. Recommendation:
  message linting only; images remain the release artifact.

**P3 — nice-to-have, YAGNI-guarded (list only)**

- `docker/build-push-action` + buildx layer caching instead of raw `docker build`/`push`.
- Multi-arch (`arm64`) — only if a consumer needs it; currently `x86_64`-only.
- Pin GitHub Actions by commit SHA (supply-chain hardening).
- Remove the `bitbucket-origin` git remote once migration is complete.
- Reconcile the stale `ALPINE_LOCAL_VERSION` (`3.19.…`) vs `ALPINE_VERSION` (`3.24.1`).
- Confirm whether `.envrc` / direnv (in `.gitignore`) is still used.

## 7. Verification steps (for the eventual implementation)

- **Static:** run `actionlint` on `publish.yml`; `pre-commit run --all-files` is green.
- **Local build:** `make update-versions` produces a correct `ALPINE_VERSION` with the new yq/jq;
  `make build` builds the image locally.
- **First manual run** (`workflow_dispatch`): both `:<ALPINE_VERSION>` and `:<ALPINE_LOCAL_VERSION>`
  tags appear in the DO registry; the version commit-back lands with `[skip ci]` and does **not**
  spawn a second workflow run.
- **Scheduled no-op:** a scheduled run with no Alpine version change performs no build and no commit.
- **Fan-out stub:** the `fanout` job no-ops while `.github/downstream-repos.txt` has no enabled
  entries and/or `FANOUT_TOKEN` is unset.
- **Migration cleanup:** a search confirms no lingering `bitbucket` or `develop` references remain
  in tracked files after `bitbucket-pipelines.yml` is removed.

## 8. Rollout / cutover notes

1. Add `DO_REG_USERNAME` / `DO_REG_PASSWORD` as GitHub secrets.
2. Merge `publish.yml` + `.github/downstream-repos.txt` + README to `main`.
3. Validate with a manual `workflow_dispatch` run before deleting `bitbucket-pipelines.yml`.
4. Delete `bitbucket-pipelines.yml`; optionally remove the `bitbucket-origin` remote (P3).
5. Address P1 TODOs (yq) as part of, or immediately after, the workflow implementation so the
   scheduled path is correct.
