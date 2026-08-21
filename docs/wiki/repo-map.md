---
title: Repo Map
type: repo-map
updated: 2026-07-22
confidence: high
---

# Repo Map

A directory and file map of `image-alpine`. Files prefixed `.` are hidden in
the standard `ls` listing.

| Path | Purpose |
| ---- | ------- |
| `README.md` | Project description, CI/CD overview, secrets, branching model |
| `Makefile` | Local build targets (`build`, `upload`, `commit-updates`, `update-submodule`) |
| `Makefile.update` | Sub-makefile: fetches latest Alpine release and writes `ALPINE_VERSION` |
| `dockerfile/Dockerfile` | The published image — `FROM` intermediate, runs `apk update && apk upgrade` |
| `docker-alpine/` | Git submodule: pinned clone of `alpinelinux/docker-alpine` (intermediate image source) |
| `.github/workflows/publish.yml` | GitHub Actions workflow: update + build-publish + fanout jobs |
| `.github/downstream-repos.txt` | List of downstream repos (commented out by default) the fanout job may dispatch to |
| `ALPINE_VERSION` | Pinned full Alpine version (e.g. `3.24.1`) |
| `ALPINE_SHORT_VERSION` | Pinned `MAJOR.MINOR` (e.g. `3.24`); used to checkout the submodule tag |
| `ALPINE_LOCAL_VERSION` | Timestamp-suffixed local version written during `make build` (e.g. `3.19.2024-01-27T04-39-33`) |
| `YQ_VERSION` | Version of the `mikefarah/yq` container used to parse Alpine's `latest-releases.yaml` |
| `.gitmodules` | Submodule definition: `docker-alpine` -> `https://github.com/alpinelinux/docker-alpine.git` |
| `.envrc` | `direnv` file exporting `DO_REG_USERNAME` / `DO_REG_PASSWORD` for local `docker login` |
| `.cz.toml` | commitizen configuration: `cz_conventional_commits`, tag_format `$version` |
| `.pre-commit-config.yaml` | Pre-commit hooks: commitizen, yamllint, shellcheck, hadolint |
| `.yamllint` | yamllint rules (line-length 120, allows `check-keys: false`) |
| `.gitignore` | Ignores `.envrc` and `latest-releases.yaml` |
| `.devcontainer/devcontainer.json` | devcontainer definition (Docker-in-Docker feature, OpenCode plugins) |
| `.devcontainer/devcontainer-lock.json` | devcontainer lockfile pinning feature versions |
| `docs/superpowers/specs/` | Design specs (e.g. CI design doc) |
| `docs/superpowers/plans/` | Implementation plans (e.g. CI publishing plan) |
| `opencode.json` | OpenCode config; loads `superpowers` and `repo-wiki-superpowers` plugins |

## Source map
- `README.md` — purpose statement
- `Makefile`, `Makefile.update` — top-level orchestration
- `dockerfile/Dockerfile` — published-image definition
- `.github/` — CI definitions and downstream config
- `*_VERSION` files — pinned dependencies

## Confidence / gaps
- Solid: every file in the repository was inspected; map is exhaustive for
  the tracked tree.
- Uncertain / to verify: `docs/superpowers/specs/` and `docs/superpowers/plans/`
  contents were not read in full; one file each is present but their
  relationship to the live state of the workflow is unclear. The specs/plans
  appear to be authored in the Superpowers workflow, not project documentation
  per se.
