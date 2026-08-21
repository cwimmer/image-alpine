---
title: Open Questions
type: open-questions
updated: 2026-07-22
confidence: high
---

# Open Questions

Known unknowns and decisions that the current source does not pin down.

## 1. Is the `intermediate` image published to the registry?

`dockerfile/Dockerfile:1` reads:

```
FROM registry.digitalocean.com/cwimmer/alpine:intermediate
```

But `Makefile:41-46` (`build`) only `docker build`s and locally tags
`IMAGE_NAME_INTERMEDIATE = IMAGE_NAME:intermediate` — it is never
`docker push`ed (the `upload` target only pushes
`$(IMAGE_NAME):$(ALPINE_LOCAL_VERSION)` and `$(IMAGE_NAME):$(ALPINE_VERSION)`).

So either:

- The first build that ever happened pushed it manually, and later builds
  rely on that artifact being available, OR
- There is a separate pipeline that publishes `intermediate`, OR
- The reference is intentional dead code / a future idea, and the actual
  build flow does not need it.

The README and `Makefile` do not explain this. To verify: `docker pull
registry.digitalocean.com/cwimmer/alpine:intermediate` against the registry.

## 2. The `ALPINE_LOCAL_VERSION` file is stale

The working tree has `ALPINE_SHORT_VERSION=3.24` and
`ALPINE_VERSION=3.24.1`, but `ALPINE_LOCAL_VERSION=3.19.2024-01-27T04-39-33`.

`ALPINE_LOCAL_VERSION` is meant to be regenerated on every `make build` and
should always start with the current `ALPINE_SHORT_VERSION`. The on-disk
value suggests:

- The short-version was bumped from `3.19` to `3.24` without an accompanying
  build, OR
- The file is expected to be reset by a fresh build but has not been
  cleaned up.

Not a bug per se — the file is overwritten on the next build — but the
mismatch is a smell worth understanding.

## 3. What protects `main` from bot pushes?

The `update` and `build-publish` jobs both push commits back to `main`:

- `update` runs `make commit-updates` after a version bump.
- `build-publish` runs `make commit-updates-pipeline` to record the new
  `ALPINE_LOCAL_VERSION`.

If branch protection on `main` requires PR reviews or status checks, the
workflow would fail. The repo files do not reveal the branch-protection
settings — confirm in GitHub repo settings.

## 4. Where does the registry credential in `.envrc` actually come from?

`.envrc` (gitignored) contains what look like real DigitalOcean registry
credentials (`dop_v1_...`), with the same value for username and password.
Either:

- This is a developer placeholder the local devcontainer is expected to
  overwrite, OR
- It is a real PAT. The fact that `.envrc` is gitignored reduces the
  blast radius if it is real, but operators should treat on-disk values as
  illustrative and rotate the token if it ever leaked.

## 5. Are downstream repos actually being notified?

`.github/downstream-repos.txt` has every line commented out and the
`FANOUT_TOKEN` secret is described as optional. The README mentions
`image-golang`, `image-hugo`, `image-imagemagick` as the intended
downstream chain, but they are not currently listed. To enable:

1. Uncomment the repo names in `.github/downstream-repos.txt`.
2. Add the `FANOUT_TOKEN` PAT with `repo` scope on the downstream repos.

## 6. Is there a staging / test path for the fanout?

The `fanout` job sends real `repository_dispatch` events to real
downstream repos. There is no dry-run flag, no `if: github.event_name !=
'schedule'` guard on `fanout`, and no test target repo. A typo in
`downstream-repos.txt` (e.g. an uncommented misspelled repo) would dispatch
to a real or non-existent repo with no rollback.

## 7. Submodule authentication

`.gitmodules` uses `https://github.com/alpinelinux/docker-alpine.git`. On
the CI runners this works without auth (public repo), but
`make update-submodule` issues `git pull` inside `docker-alpine/`, which
requires the submodule's remote to be reachable from the runner. If a
future change moves to a private upstream, the workflow will break unless
a `GITHUB_TOKEN` with read access is wired in.

## Source map
- `dockerfile/Dockerfile` — `intermediate` `FROM` reference (Q1)
- `Makefile` — `build` / `upload` targets (Q1, Q2)
- `.github/workflows/publish.yml` — bot commits and fanout (Q3, Q6, Q7)
- `.envrc`, `.gitignore` — local creds (Q4)
- `.github/downstream-repos.txt`, `README.md` — fanout enablement (Q5)

## Confidence / gaps
- Solid: each open question is grounded in a specific file reference.
- Uncertain / to verify: every question above is answerable from outside
  the repo (registry inspection, GitHub settings, secrets config). They are
  open here because they are not pinned down by the source code itself.
