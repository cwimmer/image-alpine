---
title: Roadmap
type: roadmap
updated: 2026-08-21
confidence: medium
---

# Roadmap

Planned future work. Items are unprioritized and undated.

## Multi-arch container artifact (Intel + ARM)

The current build pipeline (`Makefile:41-46`) only produces an `x86_64`
artifact: `docker build -t $(IMAGE_NAME_INTERMEDIATE) docker-alpine/x86_64`.
There is no ARM build step, no `docker buildx` invocation, and no manifest
list / multi-arch push.

Goal: produce a single image that resolves to the correct architecture on
pull — e.g. via `docker buildx build --platform linux/amd64,linux/arm64`
with a manifest list pushed by `docker buildx imagetools create` (or
equivalent) in the `upload` target (`Makefile:47-52`).

Touchpoints:
- `Makefile` — `build` and `upload` targets
- `dockerfile/Dockerfile` — must remain platform-neutral (already is)
- `Makefile.update` — `latest-releases.yaml` is currently fetched for
  `x86_64` only (`Makefile.update:9`); ARM release info may need to be
  merged in for version pinning

## Replace bump2version with a supported tool

The `Makefile:15-16` `update-versions` target delegates to
`Makefile.update`, which uses `curl` + `yq` + `jq` to rewrite
`ALPINE_VERSION` and `ALPINE_SHORT_VERSION` from upstream Alpine release
data. No version-bumping tool is invoked.

Goal: swap whatever versioning machinery is currently in place (see
Confidence / gaps) for a maintained, supported alternative. Candidates that
fit this repo's existing pre-commit toolset include `commitizen`
(already present in `.pre-commit-config.yaml:3-7` for commit-message
enforcement) and `bump-my-version` (a maintained successor to
`bump2version`).

Touchpoints:
- `Makefile` — `update-versions`, `commit-updates`, `commit-updates-pipeline`
- `Makefile.update` — version-write logic
- `ALPINE_VERSION`, `ALPINE_SHORT_VERSION`, `ALPINE_LOCAL_VERSION` —
  the files being rewritten
- `.pre-commit-config.yaml` — if the new tool exposes a pre-commit hook

## Add actionlint to pre-commit

`.pre-commit-config.yaml:1-23` currently configures `commitizen`,
`yamllint`, `shellcheck`, and `hadolint`. There is no `actionlint` hook,
even though `actionlint` is referenced in the project's historical design
and plan docs (`docs/superpowers/specs/2026-07-07-github-actions-docker-publishing-design.md:261`,
`docs/superpowers/plans/2026-07-07-github-actions-docker-publishing.md:9,147,295`).

Goal: add a `rhysd/actionlint` repo entry to
`.pre-commit-config.yaml`, scoped to `.github/workflows/*.yml` so every
PR is checked against GitHub Actions semantics.

Touchpoints:
- `.pre-commit-config.yaml` — new repo entry, files regex
- `.github/workflows/publish.yml` — the only workflow in the repo today

## Source map
- `Makefile` — build/upload/commit targets (`Makefile:15-52`)
- `Makefile.update` — version-bump mechanism (`Makefile.update:8-13`)
- `dockerfile/Dockerfile` — platform-neutral FROM and RUN steps
- `.pre-commit-config.yaml` — current pre-commit hook set
- `.github/workflows/publish.yml` — workflow to be linted by actionlint
- `docs/superpowers/specs/2026-07-07-github-actions-docker-publishing-design.md` — historical reference to actionlint
- `docs/superpowers/plans/2026-07-07-github-actions-docker-publishing.md` — historical reference to actionlint

## Confidence / gaps
- **Solid (multi-arch):** `Makefile:43` hard-codes `docker-alpine/x86_64`
  in the intermediate build, and `Makefile:51-52` pushes single-arch
  images. Confirmed by reading the file.
- **Solid (actionlint):** `.pre-commit-config.yaml` does not contain an
  `actionlint` entry as of this update. Confirmed by reading the file.
- **Uncertain (bump2version):** the source contains no `bump2version`
  reference — neither in `Makefile`, `Makefile.update`, nor
  `.pre-commit-config.yaml`. The current version-write path is
  `curl` + `yq` + `jq` rewriting plain `*_VERSION` files. The roadmap
  item as stated ("replace bump2version") does not match the present
  state. Either the request refers to a future/intended bump2version
  rollout that has not landed yet, or the intent is to replace the
  current `curl`/`yq`/`jq` script (which serves the same role as
  `bump2version` would). The page above describes it as replacing the
  current versioning machinery; flag for confirmation.
