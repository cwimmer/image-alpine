---
title: Overview
type: overview
updated: 2026-07-22
confidence: high
---

# Overview

`image-alpine` produces a customized [Alpine Linux](https://alpinelinux.org/)
base image and publishes it to the DigitalOcean container registry
`registry.digitalocean.com/cwimmer/alpine`. It is the **base of a downstream
image chain** (`image-golang`, `image-hugo`, `image-imagemagick`).

## What the project produces

The published image carries **two tags**:

1. `registry.digitalocean.com/cwimmer/alpine:<ALPINE_VERSION>` — the upstream
   Alpine release version (e.g. `3.24.1`). Moved only when Alpine itself
   releases.
2. `registry.digitalocean.com/cwimmer/alpine:<ALPINE_LOCAL_VERSION>` — a
   timestamped local version (e.g. `3.19.2024-01-27T04-39-33`). Refreshed on
   every rebuild.

The Dockerfile is intentionally minimal: it `FROM`s an intermediate image
produced by the upstream [`docker-alpine`](https://github.com/alpinelinux/docker-alpine)
submodule, then runs `apk update && apk upgrade --available`. The "customization"
is therefore essentially **always up-to-date** rather than content-additive.

## How it fits in the wider system

- **Upstream:** `https://github.com/alpinelinux/docker-alpine` (git submodule
  pinned by tag `v<ALPINE_SHORT_VERSION>`, e.g. `v3.24`).
- **This repo:** builds the intermediate into the published image and bumps
  versions on a schedule.
- **Downstream:** `image-golang`, `image-hugo`, `image-imagemagick` consume the
  published image as their base and are notified via GitHub
  `repository_dispatch` events (`base-image-updated`).

## How the project is operated

- **Local:** the `Makefile` drives `make build`, `make upload`,
  `make update-versions`, `make update-submodule`.
- **CI:** `.github/workflows/publish.yml` runs on push to `main`, a daily
  schedule (`0 6 * * *` UTC), or manual dispatch. The scheduled/manual `update`
  job bumps versions; the `build-publish` job builds and pushes; the `fanout`
  job optionally notifies downstream repos.
- **Branching:** `main` is the integration branch and the only branch that
  publishes images. Short-lived `feat/*` / `fix/*` branches merge via PR.
- **Commits:** follow
  [Conventional Commits](https://www.conventionalcommits.org/) (enforced by
  commitizen via pre-commit). The repository does not use SemVer git tags —
  the published image tags are the release artifact.

See [architecture](architecture.md) for the build pipeline and
[operations](operations.md) for the Makefile and CI flow.

## Source map
- `README.md` — high-level purpose, CI/CD overview, secrets, branching model
- `Makefile` — build / upload / update targets
- `dockerfile/Dockerfile` — the published image's definition
- `.gitmodules` — submodule definition for upstream `docker-alpine`

## Confidence / gaps
- Solid: image name, tag scheme, downstream consumer list, branch policy, CI
  schedule.
- Uncertain / to verify: whether `intermediate` is a published tag in the
  registry (the `dockerfile/Dockerfile` references
  `registry.digitalocean.com/cwimmer/alpine:intermediate`, but the Makefile
  only pushes the two release tags). See
  [open-questions](open-questions.md).
