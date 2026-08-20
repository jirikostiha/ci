# ci

Centralized, reusable GitHub Actions workflows and composite actions shared
across repositories. One source of truth; consumers stay thin.

## Versioning

Consumers pin by tag; Dependabot converts tags to commit SHAs and keeps them
current. Releases are immutable — a published tag never moves.

- `@v1` — latest v1.x, backwards compatible
- `@v1.2.0` — exact release
- `@<sha>` — hardened pin (recommended for production; Dependabot maintains it)

Breaking changes ship as a new major (`v2`) and require an explicit bump.

## Catalog

### Composite action

| Action | Purpose |
| --- | --- |
| `actions/setup-dotnet` | Install the .NET SDK and print info |

### Reusable workflows (`workflow_call`)

| Workflow | Purpose | Key inputs |
| --- | --- | --- |
| `dotnet-build.yml` | Restore, build, test, optional pack + artifacts | `solution`, `configuration`, `artifacts` |
| `gh-release.yml` | Zip `binaries` artifact, create GitHub release, prune old | `tag`, `keep-latest` |
| `nuget-publish.yml` | Push `packages` artifact to nuget.org via OIDC | `user` |
| `code-analysis.yml` | CodeQL | `language` |
| `lint-code.yml` | `dotnet format` with auto fix | `dir` |
| `lint-commit.yml` | commitlint + fixup guard | `config` |
| `benchmark.yml` | BenchmarkDotNet + result storage | `project` |
| `clean-history.yml` | Prune old workflow runs | `retain-days` |
| `auto-approve.yml` | Approve trusted bot PRs | `actors` |

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
    uses: jirikostiha/ci/.github/workflows/gh-release.yml@v1
    with: { tag: ${{ github.ref_name }} }
  publish:
    needs: release
    uses: jirikostiha/ci/.github/workflows/nuget-publish.yml@v1
    with: { user: jiri }
    permissions: { contents: read, id-token: write }
```

## Notes

- Reusable workflows reference the composite action by **full path**
  (`jirikostiha/ci/.github/actions/setup-dotnet@v1`), never `./` — a local path
  would resolve against the consumer repo.
- Secrets are not inherited. Pass only what a workflow needs via `secrets:`;
  OIDC (`id-token: write`) avoids long-lived keys entirely.
- `environment` approval gates and their secrets live in the **consumer** repo.
