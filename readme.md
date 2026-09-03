# ci

Centralized, reusable GitHub Actions workflows and composite actions shared
across repositories. One source of truth; consumers stay thin.

## Versioning

Consumers pin by tag; Dependabot converts tags to commit SHAs and keeps them
current.

- `@v1` — **moving major alias**: always points at the latest `v1.x`. This tag
  is repositioned on every `v1.x` release (the GitHub Actions convention), so it
  is the one exception to immutability below.
- `@v1.2.0` — **exact release**: immutable; a published exact tag never moves.
- `@<sha>` — hardened pin (recommended for production; Dependabot maintains it).

Breaking changes ship as a new major (`v2`) and require an explicit bump; the
`v1` alias is never repositioned onto a breaking change.

## Catalog

### Composite action

| Action | Purpose |
| --- | --- |
| `actions/setup-dotnet` | Install the .NET SDK and print info |

### Reusable workflows (`workflow_call`)

| Workflow | Purpose | Key inputs |
| --- | --- | --- |
| `dotnet-build.yml` | Restore, build, test, optional pack + artifacts | `solution`, `configuration`, `artifacts` |
| `github-release.yml` | Zip `binaries` artifact as `<product>_<tag>.zip`, create GitHub release, prune old | `tag`, `product-name`, `keep-latest` |
| `github-publish.yml` | Push `packages` artifact to GitHub Packages (via `GITHUB_TOKEN`) | `packages-dir`, `environment` |
| `godot-publish.yml` | Publish/update asset in Godot Asset Library | `username`, `asset-id`, `asset-template` |
| `docs.yml` | Build DocFX documentation and deploy to GitHub Pages | `version`, `include-benchmarks` |
| `code-analysis.yml` | CodeQL | `language` |
| `lint-code.yml` | `dotnet format` with auto fix | `dir` |
| `lint-commit.yml` | commitlint + fixup guard | `config` |
| `benchmark.yml` | BenchmarkDotNet + result storage | `project` |
| `clean-history.yml` | Prune old workflow runs | `retain-days` |
| `auto-approve.yml` | Approve trusted bot PRs | `actors` |
| `auto-merge.yml` | Auto-merge PR on successful build | `head-branch` |

### Inline templates (`templates/`, copy — do not call)

| Template | Purpose | Target path in consumer |
| --- | --- | --- |
| `templates/nuget-publish.yml` | Publish to **nuget.org** via OIDC trusted publishing | `.github/workflows/nuget-publish.yml` |

nuget.org (and PyPI/npm) trusted publishing **cannot** run from a cross-repo
reusable workflow: nuget.org matches the OIDC token's `repository` /
`repository_id` / `repository_owner_id` (the caller repo) *and* `job_workflow_ref`
(the repo where the job lives). A cross-repo reusable splits those across two
repos, so no policy matches and the token exchange fails (HTTP 401). Copy the
template into the package repo's own `.github/workflows/` instead. GitHub Packages
uses `GITHUB_TOKEN` (no subject matching), so `github-publish.yml` stays a
normal reusable.

## Usage

The consumer owns the **triggers**; this repo owns the **steps**. A caller is a
thin file wiring events to a reusable workflow:

```yaml
# .github/workflows/build.yml in the consumer repo
name: Build
on:
  workflow_dispatch:
    inputs:
      configuration:
        type: choice
        options: [Debug, Release]
        default: Debug
  push:
    paths: ["src/**"]

jobs:
  build:
    uses: jirikostiha/ci/.github/workflows/dotnet-build.yml@v1
    with:
      solution: ./src/smath.slnx
      configuration: ${{ inputs.configuration || 'Debug' }}
```

Orchestration (build once, then release, then publish) is composed in the
caller so each reusable workflow stays single-purpose and flat:

```yaml
jobs:
  build:
    uses: jirikostiha/ci/.github/workflows/dotnet-build.yml@v1
    with: { solution: ./src/smath.slnx, configuration: Release, artifacts: true }
  release:
    needs: build
    uses: jirikostiha/ci/.github/workflows/github-release.yml@v1
    with: { tag: ${{ github.ref_name }} }
  publish:
    needs: release
    uses: jirikostiha/ci/.github/workflows/github-publish.yml@v1
    permissions: { contents: read, packages: write }
```

For **nuget.org** trusted publishing, inline `templates/nuget-publish.yml` into the
consumer repo instead of calling a reusable (see the templates note above).

## Notes

- Reusable workflows reference the composite action by **full path**
  (`jirikostiha/ci/.github/actions/setup-dotnet@v1`), never `./` — a local path
  would resolve against the consumer repo.
- Secrets are not inherited. Pass only what a workflow needs via `secrets:`;
  OIDC (`id-token: write`) avoids long-lived keys entirely.
- `environment` approval gates and their secrets live in the **consumer** repo.
