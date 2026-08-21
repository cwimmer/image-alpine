---
title: Configuration
type: configuration
updated: 2026-07-22
confidence: high
---

# Configuration

All configuration is plain files at the repo root (or in well-known dotfile
locations). There are no `.env`-style runtime configs and no central config
file — every value is a one-line pin.

## Version pins

| File | Holds | Read by | Written by |
| --- | --- | --- | --- |
| `ALPINE_VERSION` | Full upstream Alpine version, e.g. `3.24.1` | `Makefile` (image tag, commit message) | `Makefile.update` (`update-versions`) |
| `ALPINE_SHORT_VERSION` | `MAJOR.MINOR`, e.g. `3.24` | `Makefile.update` (submodule checkout tag `v<short>`), commit messages | `Makefile.update` (`cut -d. -f1-2 ALPINE_VERSION`) |
| `ALPINE_LOCAL_VERSION` | `<short>.YYYY-MM-DDTHH-MM-SS` (UTC), e.g. `3.19.2024-01-27T04-39-33` | `Makefile` (image tag, push target), `publish.yml` fanout payload | `Makefile` `build` target |
| `YQ_VERSION` | Version of `mikefarah/yq` image used to parse Alpine's release YAML, e.g. `3.3.4` | `Makefile.update` | Not written by the project |

`ALPINE_LOCAL_VERSION` is therefore the **build-timestamp** identifier —
distinct from `ALPINE_VERSION`, which moves only on upstream Alpine releases.

## Makefile variables

Derived inline (not stored in files):

- `alpine_short_version` — `$(shell cat ALPINE_SHORT_VERSION)`
- `alpine_version` — `$(shell cat ALPINE_VERSION)`
- `DATE` — `$(shell date -u +%Y-%m-%dT%H-%M-%S)`
- `IMAGE_NAME` — `registry.digitalocean.com/cwimmer/alpine`
- `IMAGE_NAME_INTERMEDIATE` — `$(IMAGE_NAME):intermediate`

## Environment / secrets

### Local (`.envrc`, gitignored)

```
export DO_REG_USERNAME=<dop_v1_...>
export DO_REG_PASSWORD=<dop_v1_...>
```

These are consumed by the `upload` target via `make`'s normal env propagation
and are loaded automatically by `direnv` if `.envrc` is allowed.

> Note: the on-disk values look like `dop_v1_…` placeholders for both username
> and password, but `.envrc` is in `.gitignore`. The actual deployment uses
> GitHub repository secrets; operators should treat any value found on disk as
> illustrative.

### CI (GitHub Actions secrets)

| Secret | Used in | Purpose |
| --- | --- | --- |
| `DO_REG_USERNAME` | `build-publish` job, `Publish image` step | `docker login` to `registry.digitalocean.com` |
| `DO_REG_PASSWORD` | `build-publish` job, `Publish image` step | same |
| `FANOUT_TOKEN` | `fanout` job, `cfg` and `Dispatch` steps | PAT with `repo` scope on the downstream repos; used by `gh api .../dispatches` |

## Commit conventions

`.cz.toml` configures commitizen:

```
name = "cz_conventional_commits"
version = "0.0.1"
tag_format = "$version"
```

Combined with the `.pre-commit-config.yaml` commitizen hook on
`commit-msg`, every commit must follow Conventional Commits. The repository
does not emit SemVer git tags; the published image tags are the release
artifact.

## Lint / hook config

- `.yamllint` — extends default; line-length max 120; `truthy.check-keys: false`.
- `.pre-commit-config.yaml` — four hooks: `commitizen`, `yamllint` (`.yaml|.yml`,
  `yamllint --strict`), `shellcheck`, `hadolint`.

See [testing](testing.md) for hook details.

## devcontainer

`.devcontainer/devcontainer.json` pins:

- Base image: `ghcr.io/cwimmer/devcontainer:opencode`
- Features: `docker-in-docker:3`
- VS Code extensions: `makefile-tools`, `todo-tree`, `markdownlint`,
  `sst-dev.opencode`
- `postCreateCommand: make postCreateCommand` (no-op echo)

## Source map
- `ALPINE_VERSION`, `ALPINE_SHORT_VERSION`, `ALPINE_LOCAL_VERSION`, `YQ_VERSION` — version pins
- `Makefile`, `Makefile.update` — derived vars and write sites
- `.envrc` — local-only registry creds (gitignored)
- `.cz.toml` — commit message policy
- `.pre-commit-config.yaml`, `.yamllint` — lint policy
- `.devcontainer/devcontainer.json` — dev environment pin

## Confidence / gaps
- Solid: every file in the repo was inspected; the configuration surface is
  intentionally tiny.
- Uncertain / to verify: the committed-looking credential values in `.envrc`
  appear to be placeholders or example values (the file is in `.gitignore`),
  but the wiki does not assume what the real values are. Operators should
  treat any value seen on disk as illustrative.
