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
