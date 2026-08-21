---
title: Integrations
type: integrations
updated: 2026-07-22
confidence: high
---

# Integrations

External systems this repo talks to.

## Upstream — `alpinelinux/docker-alpine`

- **Type:** Git submodule.
- **URL:** `https://github.com/alpinelinux/docker-alpine.git` (declared in
  `.gitmodules`).
- **Path:** `docker-alpine/`.
- **Use:** provides the `Dockerfile` (under `docker-alpine/x86_64/`) that
  produces the **intermediate** image, which `dockerfile/Dockerfile` then
  extends with `apk update && apk upgrade`.
- **Pinning:** the submodule is checked out at the tag `v<ALPINE_SHORT_VERSION>`
  (e.g. `v3.24`) by `make update-submodule`. Updates flow in when
  `ALPINE_SHORT_VERSION` is bumped by `make update-versions`.

## Alpine Linux release metadata

- **Endpoint:** `http://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml`.
- **Use:** the source of truth for the latest Alpine release version, fetched
  by `Makefile.update` (`update-versions`).
- **Parser:** `mikefarah/yq:<YQ_VERSION>` running in a container, then `jq
  .[0].version` to pick the newest entry, then `cut -d. -f1-2` for the short
  version.
- **Local artifact:** `latest-releases.yaml` (gitignored).

## Container registry — DigitalOcean

- **Registry:** `registry.digitalocean.com`.
- **Image name:** `cwimmer/alpine`.
- **Tags pushed:**
  - `registry.digitalocean.com/cwimmer/alpine:<ALPINE_VERSION>` — moves only
    on upstream Alpine releases.
  - `registry.digitalocean.com/cwimmer/alpine:<ALPINE_LOCAL_VERSION>` — moves
    on every build.
- **Auth:** `DO_REG_USERNAME` and `DO_REG_PASSWORD` secrets (DigitalOcean
  container registry token). Supplied to CI via repository secrets; supplied
  locally via `.envrc` (gitignored).
- **Referenced but not pushed:** `registry.digitalocean.com/cwimmer/alpine:intermediate`
  is used as a `FROM` source by `dockerfile/Dockerfile`. The Makefile only
  pushes the two release tags — the `intermediate` is built and tagged
  locally but is never `docker push`ed.

## GitHub Actions

- **Workflow file:** `.github/workflows/publish.yml`.
- **Triggers:** push on `main`, schedule `0 6 * * *` UTC, manual dispatch.
- **Concurrency:** group `publish-main`, `cancel-in-progress: false`.
- **Permissions:** `contents: write` for all jobs.
- **Runner:** `ubuntu-latest`.
- **Checkout:** `actions/checkout@v4` with `submodules: recursive` for the
  `update` and `build-publish` jobs.

## Downstream consumers

- **Mechanism:** GitHub `repository_dispatch` event type
  `base-image-updated`.
- **Targets:** repositories named in `.github/downstream-repos.txt`
  (currently all commented out). The README lists `image-golang`, `image-hugo`,
  `image-imagemagick` as the intended consumers.
- **Dispatch tool:** `gh api repos/cwimmer/<repo>/dispatches` with payload
  `{ image, tag, local_tag }`.
- **Auth:** `FANOUT_TOKEN` PAT with `repo` scope on the downstream repos. The
  fanout job short-circuits if either `repos` or `FANOUT_TOKEN` is empty.

### How a downstream repo opts in

```yaml
on:
  repository_dispatch:
    types: [base-image-updated]
```

### How an operator enables a downstream

1. Uncomment the repo name in `.github/downstream-repos.txt`.
2. Ensure `FANOUT_TOKEN` is set on the repository.

## devcontainer / OpenCode (developer tooling, not runtime)

- `.devcontainer/devcontainer.json` uses `ghcr.io/cwimmer/devcontainer:opencode`
  with the `docker-in-docker` feature and a persistent OpenCode data volume.
- `opencode.json` loads the `superpowers` and `repo-wiki-superpowers` plugins.

## Source map
- `.gitmodules` — submodule declaration
- `Makefile`, `Makefile.update` — upstream and registry interactions
- `dockerfile/Dockerfile` — intermediate-image `FROM` reference
- `.github/workflows/publish.yml` — CI and fanout integration
- `.github/downstream-repos.txt` — downstream target list
- `.envrc` — local registry credentials (gitignored)
- `README.md` — secrets and fanout opt-in docs

## Confidence / gaps
- Solid: all external endpoints, the auth model, the fanout payload shape,
  and the downstream opt-in protocol.
- Uncertain / to verify: whether the `intermediate` tag is pushed manually
  (the Makefile does not push it). The `dockerfile/Dockerfile` references
  it as if it is reachable in the registry; if so, it must be either pushed
  by a separate process or built and tagged locally only. See
  [open-questions](open-questions.md).
