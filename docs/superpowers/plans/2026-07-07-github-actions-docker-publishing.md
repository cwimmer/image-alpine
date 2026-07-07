# GitHub Actions Docker Publishing + Main-Based Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Bitbucket Pipelines with a GitHub Actions workflow that builds and publishes the Alpine image to the DigitalOcean registry, add a config-driven downstream fan-out stub, document main-based development, and remove the Bitbucket setup.

**Architecture:** A single workflow `.github/workflows/publish.yml` with three jobs — `update` (schedule/manual: bump Alpine version), `build-publish` (build + push both tags + commit-back), and `fanout` (config-driven, disabled stub). The `Makefile` remains the build/publish engine; no application or Makefile changes. A small `.yamllint` config lets the workflow YAML pass the repo's `yamllint --strict` pre-commit hook.

**Tech Stack:** GitHub Actions, Docker, GNU Make, Bash, `gh` CLI + `jq` (fan-out), pre-commit (yamllint/shellcheck/hadolint/commitizen), actionlint (validation).

**Spec:** `docs/superpowers/specs/2026-07-07-github-actions-docker-publishing-design.md`

## Global Constraints

- Registry (unchanged): `registry.digitalocean.com/cwimmer/alpine`.
- Runner: `ubuntu-latest` for all jobs (not `cwimmer/build:stable` — see spec §5).
- Triggers: `push:` on `main`, `schedule: '0 6 * * *'` (UTC), `workflow_dispatch`.
- Preserve commit-back of all version files; the build-publish commit message carries `[skip ci]`.
- Secrets: `DO_REG_USERNAME`, `DO_REG_PASSWORD` (required); `FANOUT_TOKEN` (optional, fan-out only).
- The repo runs `yamllint --strict` via pre-commit; YAML must pass with the `.yamllint` from Task 1 (`line-length.max: 120`, `truthy.check-keys: false`).
- Do **not** modify the `Makefile`, upgrade dependencies, or change yq (all deferred TODOs in spec §6).
- Do **not** stage or revert the pre-existing uncommitted `Makefile` change already in the working tree; it is unrelated to this work.
- Do all work on a short-lived feature branch. The workflow publishes **only** on push to `main`, so feature-branch commits never publish; the cutover is the merge to `main` (Task 6).

---

## Prerequisites (one-time, before Task 1)

- [ ] **P1: Create the feature branch**

```bash
git switch -c feat/github-actions-ci
```

- [ ] **P2: Ensure pre-commit hooks are installed with a valid interpreter**

The repo shipped a stale macOS `commit-msg` hook; reinstalling regenerates both hooks for this environment.

Run:

```bash
pre-commit install --install-hooks --hook-type pre-commit --hook-type commit-msg
```

Expected: `pre-commit installed at .git/hooks/pre-commit` and `.git/hooks/commit-msg`.

- [ ] **P3: (Maintainer) Add repository secrets before Task 6 merge**

In GitHub → Settings → Secrets and variables → Actions, add `DO_REG_USERNAME` and `DO_REG_PASSWORD`. `FANOUT_TOKEN` is only needed when enabling fan-out later. These are not needed to develop Tasks 1–5, but the publish on merge to `main` (Task 6) fails without them.

---

## Task 1: Add yamllint configuration

**Files:**
- Create: `.yamllint`

**Interfaces:**
- Produces: a repo-root `.yamllint` auto-discovered by the pre-commit `yamllint` hook; relaxes line length to 120 and stops the `on:` key from tripping the `truthy` rule. Consumed by Task 3's workflow.

- [ ] **Step 1: Create `.yamllint`**

````yaml
---
extends: default

rules:
  line-length:
    max: 120
  truthy:
    check-keys: false
````

- [ ] **Step 2: Validate all YAML still passes under the new config**

Run:

```bash
pre-commit run yamllint --all-files
```

Expected: `yamllint...Passed`.

- [ ] **Step 3: Commit**

```bash
git add .yamllint
git commit -m "ci: add yamllint config for GitHub Actions YAML"
```

---

## Task 2: Add downstream fan-out config stub

**Files:**
- Create: `.github/downstream-repos.txt`

**Interfaces:**
- Produces: `.github/downstream-repos.txt` — a newline list of downstream repo names, all commented out. Task 3's `fanout` job parses non-comment, non-blank lines. Enabling a downstream rebuild later = uncomment a line (+ set `FANOUT_TOKEN`).

- [ ] **Step 1: Create `.github/downstream-repos.txt`**

````text
# Downstream repositories to notify after a successful publish.
#
# Uncomment a repository (one name per line, in the cwimmer org) to have the
# fanout job send it a `base-image-updated` repository_dispatch event.
# Enabling also requires the FANOUT_TOKEN secret to be set.
#
# image-golang
# image-hugo
# image-imagemagick
````

- [ ] **Step 2: Verify the parser yields an empty (disabled) list**

This is the exact expression the `fanout` job uses; it must print nothing while all entries are commented.

Run:

```bash
grep -vE '^[[:space:]]*(#|$)' .github/downstream-repos.txt | tr -d '[:blank:]' | paste -sd ',' - || true
```

Expected: empty output (a single blank line), confirming the stub is disabled.

- [ ] **Step 3: Commit**

```bash
git add .github/downstream-repos.txt
git commit -m "ci: add downstream fan-out config stub (disabled)"
```

---

## Task 3: Add the GitHub Actions publish workflow

**Files:**
- Create: `.github/workflows/publish.yml`

**Interfaces:**
- Consumes: `Makefile` targets `update-versions`, `update-submodule`, `build`, `upload`, `commit-updates`, `commit-updates-pipeline`; version files `ALPINE_VERSION`, `ALPINE_LOCAL_VERSION`; `.github/downstream-repos.txt` (Task 2); secrets `DO_REG_USERNAME`, `DO_REG_PASSWORD`, `FANOUT_TOKEN`; the `.yamllint` from Task 1.
- Produces: the publish workflow. Job `update` outputs `changed` (`'true'`/`'false'`); `build-publish` gates on it; `fanout` sends `base-image-updated` `repository_dispatch` events with `client_payload {image, tag, local_tag}`.

- [ ] **Step 1: Create `.github/workflows/publish.yml`**

This exact content passes `yamllint --strict` (with Task 1's `.yamllint`) and `actionlint`.

````yaml
---
name: Build and publish Alpine image

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: publish-main
  cancel-in-progress: false

jobs:
  update:
    name: Update Alpine version
    if: github.event_name != 'push'
    runs-on: ubuntu-latest
    outputs:
      changed: ${{ steps.bump.outputs.changed }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: main
          fetch-depth: 0
          submodules: recursive
      - name: Configure git identity
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email \
            '41898282+github-actions[bot]@users.noreply.github.com'
      - name: Update versions and submodule
        id: bump
        run: |
          before="$(cat ALPINE_VERSION)"
          make update-versions
          make update-submodule
          after="$(cat ALPINE_VERSION)"
          if [ "$before" != "$after" ]; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
          else
            echo "changed=false" >> "$GITHUB_OUTPUT"
          fi
      - name: Commit version bump
        run: make commit-updates

  build-publish:
    name: Build and publish
    needs: [update]
    if: >-
      always() &&
      (needs.update.result == 'skipped' ||
      (needs.update.result == 'success' &&
      (github.event_name == 'workflow_dispatch' ||
      needs.update.outputs.changed == 'true')))
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: main
          fetch-depth: 0
          submodules: recursive
      - name: Configure git identity
        run: |
          git config user.name 'github-actions[bot]'
          git config user.email \
            '41898282+github-actions[bot]@users.noreply.github.com'
      - name: Update submodule
        run: make update-submodule
      - name: Build image
        run: make build
      - name: Publish image
        run: make upload
        env:
          DO_REG_USERNAME: ${{ secrets.DO_REG_USERNAME }}
          DO_REG_PASSWORD: ${{ secrets.DO_REG_PASSWORD }}
      - name: Commit local version
        run: make commit-updates-pipeline

  fanout:
    name: Trigger downstream rebuilds
    needs: [build-publish]
    if: needs.build-publish.result == 'success'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: main
      - name: Determine enabled downstream repos
        id: cfg
        env:
          FANOUT_TOKEN: ${{ secrets.FANOUT_TOKEN }}
        run: |
          repos=""
          if [ -f .github/downstream-repos.txt ]; then
            repos="$(grep -vE '^[[:space:]]*(#|$)' \
              .github/downstream-repos.txt | tr -d '[:blank:]' \
              | paste -sd ',' - || true)"
          fi
          echo "repos=$repos" >> "$GITHUB_OUTPUT"
          if [ -n "$repos" ] && [ -n "$FANOUT_TOKEN" ]; then
            echo "enabled=true" >> "$GITHUB_OUTPUT"
          else
            echo "enabled=false" >> "$GITHUB_OUTPUT"
          fi
      - name: Dispatch downstream rebuilds
        if: steps.cfg.outputs.enabled == 'true'
        env:
          GH_TOKEN: ${{ secrets.FANOUT_TOKEN }}
          REPOS: ${{ steps.cfg.outputs.repos }}
        run: |
          tag="$(cat ALPINE_VERSION)"
          local_tag="$(cat ALPINE_LOCAL_VERSION)"
          image="registry.digitalocean.com/cwimmer/alpine"
          IFS=',' read -ra list <<< "$REPOS"
          for repo in "${list[@]}"; do
            echo "Dispatching base-image-updated to cwimmer/$repo"
            jq -n \
              --arg image "$image" \
              --arg tag "$tag" \
              --arg local_tag "$local_tag" \
              '{event_type: "base-image-updated",
                client_payload: {image: $image, tag: $tag,
                                 local_tag: $local_tag}}' \
              | gh api "repos/cwimmer/$repo/dispatches" --input -
          done
````

- [ ] **Step 2: Validate YAML lint (uses Task 1's `.yamllint`)**

Run:

```bash
pre-commit run yamllint --files .github/workflows/publish.yml
```

Expected: `yamllint...Passed`.

- [ ] **Step 3: Validate GitHub Actions semantics with actionlint**

Run (Docker is available; the repo is a git project so no init is needed):

```bash
docker run --rm -v "$(pwd):/repo" -w /repo rhysd/actionlint:latest -color
```

Expected: no output, exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/publish.yml
git commit -m "ci: add GitHub Actions workflow to build and publish Alpine image"
```

---

## Task 4: Add README documenting build, publish, and main-based development

**Files:**
- Create: `README.md`

**Interfaces:**
- Produces: developer-facing docs for the build/publish flow, required secrets, how to enable fan-out, and the main-based branching model. No code depends on it.

- [ ] **Step 1: Create `README.md`**

````markdown
# image-alpine

Builds a customized [Alpine Linux](https://alpinelinux.org/) base image and
publishes it to the DigitalOcean container registry
`registry.digitalocean.com/cwimmer/alpine`. It is the base of a downstream
image chain (`image-golang`, `image-hugo`, `image-imagemagick`).

## How it works

- `dockerfile/Dockerfile` builds `FROM` an intermediate image produced from the
  pinned [`docker-alpine`](https://github.com/alpinelinux/docker-alpine)
  submodule (`docker-alpine/x86_64`).
- The image is tagged with both the full Alpine version (`ALPINE_VERSION`, e.g.
  `3.24.1`) and a timestamped local version (`ALPINE_LOCAL_VERSION`).
- The `Makefile` drives everything: `make build`, `make upload`,
  `make update-versions`, `make update-submodule`.

## CI/CD (GitHub Actions)

`.github/workflows/publish.yml` builds and publishes the image:

- **Triggers:** push to `main`, a daily schedule (`0 6 * * *` UTC), and manual
  `workflow_dispatch`.
- **`update` job** (schedule/manual): checks for a new Alpine release and
  commits the version bump.
- **`build-publish` job:** builds the image and pushes both tags, then commits
  the timestamped local version with `[skip ci]`. On the scheduled path it runs
  only when the Alpine version changed; push and manual runs always build.
- **`fanout` job:** optionally notifies downstream repositories (disabled by
  default — see below).

### Required secrets

| Secret            | Purpose                                          |
| ----------------- | ------------------------------------------------ |
| `DO_REG_USERNAME` | DigitalOcean registry login                      |
| `DO_REG_PASSWORD` | DigitalOcean registry login                      |
| `FANOUT_TOKEN`    | Optional PAT to trigger downstream rebuilds      |

### Enabling downstream rebuilds

Uncomment the relevant repositories in `.github/downstream-repos.txt` and add
the `FANOUT_TOKEN` secret. Downstream repositories opt in with:

```yaml
on:
  repository_dispatch:
    types: [base-image-updated]
```

The dispatch payload is `{ image, tag, local_tag }`.

## Development workflow

- `main` is the integration branch and the only branch that publishes images.
- Create short-lived `feat/*` or `fix/*` branches, open a pull request, and
  merge into `main`. There is no `develop`, `release`, or `hotfix` branch.
- Commit messages follow
  [Conventional Commits](https://www.conventionalcommits.org/) (enforced by
  commitizen via pre-commit). The published image tags are the release
  artifact; the repository does not use SemVer git tags.
````

- [ ] **Step 2: Verify pre-commit is clean for the new file**

Run:

```bash
pre-commit run --files README.md
```

Expected: each hook reports `(no files to check)Skipped` (Markdown matches no configured hook); exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README with build, publish, and main-based dev workflow"
```

---

## Task 5: Remove Bitbucket Pipelines

**Files:**
- Delete: `bitbucket-pipelines.yml`

**Interfaces:**
- Produces: a repo with a single CI system (GitHub Actions). No code references `bitbucket-pipelines.yml`.

- [ ] **Step 1: Remove the Bitbucket pipeline file**

```bash
git rm bitbucket-pipelines.yml
```

- [ ] **Step 2: Verify no lingering Bitbucket/Gitflow references in non-doc files**

The design/plan under `docs/` intentionally mention Bitbucket and `develop`, so exclude that directory. The `Makefile`'s upstream `git checkout master` targets the Alpine submodule and is expected to remain.

Run:

```bash
git grep -nEi 'bitbucket' -- ':(exclude)docs/'
```

Expected: no output (exit code `1` from `git grep`) — Bitbucket is fully removed from non-doc files. A follow-up `git grep -nEi 'develop' -- ':(exclude)docs/'` should return only the two legitimate `README.md` lines (the `## Development workflow` heading and the "no `develop` branch" statement), not any operational `develop`-branch usage.

- [ ] **Step 3: Verify the full pre-commit suite is green**

Run:

```bash
pre-commit run --all-files
```

Expected: all hooks `Passed` or `Skipped`.

- [ ] **Step 4: Commit**

```bash
git commit -m "ci: remove Bitbucket Pipelines in favor of GitHub Actions"
```

---

## Task 6: Cutover & verification (maintainer)

This task is the integration test. It requires GitHub UI access, the registry secrets from Prerequisite P3, and produces the first real publish. It cannot be validated purely locally.

**Pre-cutover checks:**

- [ ] **Step 1: Confirm secrets exist** — `DO_REG_USERNAME` and `DO_REG_PASSWORD` are set in repo Actions secrets (P3).
- [ ] **Step 2: Branch-protection compatibility** — the `build-publish`/`update` jobs push the version commit-back **directly to `main`** using the default `GITHUB_TOKEN`. If you enable branch protection on `main`, you MUST allow the GitHub Actions bot to bypass required PRs/pushes, or the commit-back `git push` will fail. If in doubt, leave direct pushes enabled for now.

**Cutover:**

- [ ] **Step 3: Open a PR** from `feat/github-actions-ci` into `main` and confirm local/CI pre-commit is green.
- [ ] **Step 4: Merge to `main`.** The merge push triggers `publish.yml`. Because it is a `push` event, the `update` job is skipped and `build-publish` runs.

**Verify the run (GitHub → Actions):**

- [ ] **Step 5:** The workflow run succeeds; the `build-publish` job completes `make build` and `make upload`.
- [ ] **Step 6:** Both tags are present in the registry. Check via:

```bash
docker manifest inspect registry.digitalocean.com/cwimmer/alpine:$(cat ALPINE_VERSION)
```

Expected: a manifest is returned (exit `0`). The timestamped `ALPINE_LOCAL_VERSION` tag is also pushed.

- [ ] **Step 7:** The commit-back appears on `main` with a `[skip ci]` message, and it does **not** trigger a second workflow run (confirm only one run exists for the merge).
- [ ] **Step 8:** The `fanout` job ran and no-opped (the "Dispatch downstream rebuilds" step is skipped because the config is empty / `FANOUT_TOKEN` unset).

**Optional follow-ups (spec §6 P3 — do not block cutover):**

- [ ] **Step 9:** Trigger a `workflow_dispatch` run to confirm the manual path builds and publishes end-to-end.
- [ ] **Step 10:** Remove the stale Bitbucket remote once satisfied:

```bash
git remote remove bitbucket-origin
```

- [ ] **Step 11:** Observe (over time) that a scheduled run with no Alpine version change skips `build-publish` (job shows as skipped), confirming the "build only on version bump" behavior.

---

## Self-Review

**Spec coverage** (spec → task):

- §3/§4.1 triggers, jobs, runner, permissions, concurrency → Task 3.
- §4.2 registry & secrets → Task 3 (`env` mapping) + P3/Task 6 (secrets).
- §4.3 tagging & build (Makefile unchanged) → Task 3 (`make build`/`upload`).
- §4.4 version commit-back & loop prevention (`[skip ci]`, `GITHUB_TOKEN`) → Task 3 + verified Task 6 Step 7.
- §4.5 fan-out stub + downstream contract → Task 2 (config) + Task 3 (`fanout` job).
- §4.6 main-based dev & Gitflow cleanup → Task 4 (README) + Task 5 (remove Bitbucket) + Task 6 Step 2 (branch protection note).
- §5 runner rationale (`ubuntu-latest`) → Global Constraints + Task 3.
- §6 modernization TODO → intentionally deferred; not implemented here (called out in Global Constraints).
- §7 verification steps → Task 1–5 validation steps (yamllint/actionlint/parse/grep) + Task 6 (registry, commit-back, no double-run, fan-out no-op).
- §8 rollout/cutover → Prerequisites + Task 6.
- `.yamllint` need (yamllint `--strict` vs `on:`/line-length) → Task 1.

**Placeholder scan:** none — every file's full content is inline; all commands have expected output. The only "TODO"-style items are the explicitly deferred spec §6 modernization items, which are out of scope by design.

**Type/name consistency:** `update.outputs.changed` (set in Task 3 Step 1, gated in the same file); `steps.cfg.outputs.repos`/`enabled` consistent within the `fanout` job; event type `base-image-updated` and payload `{image, tag, local_tag}` match between Task 3 and Task 4's README; parser expression in Task 2 Step 2 is identical to the `fanout` job's parser in Task 3.
