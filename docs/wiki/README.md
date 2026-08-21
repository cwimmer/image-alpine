# image-alpine Wiki

LLM-maintained documentation for the `image-alpine` repository. The source of
truth is the code; each page's **Source map** links back to it.

This repository builds a customized [Alpine Linux](https://alpinelinux.org/)
base image and publishes it to the DigitalOcean container registry
`registry.digitalocean.com/cwimmer/alpine`. It serves as the base of a
downstream image chain (`image-golang`, `image-hugo`, `image-imagemagick`).

## Pages

- [overview](overview.md) — what this project does and how it fits in
- [repo-map](repo-map.md) — directory and module map
- [architecture](architecture.md) — components, build pipeline, data flow
- [configuration](configuration.md) — version pins, env vars, registry config
- [operations](operations.md) — Makefile targets, CI workflow, build pipeline
- [integrations](integrations.md) — DigitalOcean registry, downstream repos
- [domain-model](domain-model.md) — image tags, version identifiers
- [testing](testing.md) — pre-commit hooks, linting
- [open-questions](open-questions.md) — known unknowns and pending decisions
- [roadmap](roadmap.md) — planned future work (unprioritized, undated)

_Updated: 2026-08-21_
