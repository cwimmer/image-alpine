---
title: Testing
type: testing
updated: 2026-07-22
confidence: high
---

# Testing

This repository has **no application code and no test suite**. Verification is
performed by four pre-commit hooks plus the CI build itself.

## Pre-commit hooks (`.pre-commit-config.yaml`)

| Hook | Rev | Stages / scope | What it checks |
| --- | --- | --- | --- |
| `commitizen` (`commitizen-tools/commitizen`) | `v2.39.1` | `commit-msg` | Enforces Conventional Commits on every commit message |
| `yamllint` (`adrienverge/yamllint.git`) | `v1.28.0` | `files: \.(yaml|yml)$`, `types: [file, yaml]`, `entry: yamllint --strict` | Lints all YAML files in strict mode against `.yamllint` rules |
| `shellcheck` (`shellcheck-py/shellcheck-py`) | `v0.9.0.2` | (default) | Lints shell scripts embedded in the Makefile |
| `hadolint` (`hadolint/hadolint`) | `v2.12.1-beta` | (default) | Lints `dockerfile/Dockerfile` for best-practice violations |

`.yamllint` extends the default ruleset with:

- `line-length.max: 120`
- `truthy.check-keys: false` (relaxed)

## Local hook maintenance

`make pre-commit` runs:

```sh
pre-commit install
pre-commit autoupdate
pre-commit run --all-files
```

## CI as verification

Beyond the hooks, `.github/workflows/publish.yml` itself is the strongest
end-to-end verification:

- A successful `build-publish` run proves the Makefile, the submodule update,
  the `docker build`, and the registry push all work end-to-end against the
  real DigitalOcean registry.
- The `update` job's `changed=true|false` output gates `build-publish`, so
  no-op schedule runs do not consume build minutes.

## Manual smoke checks (outside this repo)

- `make build` locally (with Docker available) produces both an `intermediate`
  and a tagged image. Inspecting the resulting image with
  `docker run --rm <image> apk version` should show the latest available
  packages for the pinned Alpine release.

## What is NOT tested

- There is **no Go/Python/Node test suite** — the project is configuration
  and orchestration only.
- There is **no integration test against the downstream fanout**; the
  fanout job's only check is its own exit status. Downstream consumers are
  expected to react idempotently to repeated `base-image-updated` events.
- The submodule's own tests (in `docker-alpine/`) are not exercised by this
  repo's CI.

## Source map
- `.pre-commit-config.yaml` — hook definitions
- `.yamllint` — yamllint ruleset
- `Makefile` — `pre-commit` target
- `.github/workflows/publish.yml` — CI as verification
- `dockerfile/Dockerfile` — subject of hadolint

## Confidence / gaps
- Solid: every hook ID, its upstream repo, its pinned revision, its scope,
  and the lint config it runs against.
- Uncertain / to verify: whether `pre-commit run --all-files` is also
  enforced in CI — the workflow does not appear to run pre-commit directly
  (the hooks are installable locally only).
