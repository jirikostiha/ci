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
| `actions/setup-dotnet` | Install the .NET SDK (`dotnet-version` plus the SDK pinned in the repository's `global.json`, if any) and print info |

### Reusable workflows (`workflow_call`)

| Workflow | Purpose | Key inputs |
| --- | --- | --- |
| `dotnet-build.yml` | Restore, build, test (VSTest, or Microsoft.Testing.Platform when `global.json` selects that runner), optional pack + artifacts | `solution`, `configuration`, `artifacts` |
| `github-release.yml` | Verify the tag against the version file (opt-in), zip `binaries` artifact as `<product>_<tag>.zip`, create GitHub release, prune old | `tag`, `product-name`, `keep-latest`, `version-file` |
| `github-publish.yml` | Push `packages` artifact to GitHub Packages (via `GITHUB_TOKEN`) | `packages-dir`, `environment` |
| `godot-publish.yml` | Publish/update asset in Godot Asset Library | `username`, `asset-id`, `asset-template` |
| `docs.yml` | Build DocFX documentation and deploy to GitHub Pages | `version`, `include-benchmarks`, `ref` |
| `code-analysis.yml` | CodeQL; uploads to code scanning where the repository has it, otherwise keeps the SARIF as the `codeql-results` artifact. Inherits the caller's permissions: grant `contents: read`, `security-events: write`, plus `actions: read` in a private repository | `language` |
| `lint-code.yml` | `dotnet format` with auto fix, or check-only as a release gate; inherits the caller's permissions: grant `contents: write`, `checks: write` for auto fix, `contents: read`, `checks: write` for check-only | `dir`, `check-only`, `ref` |
| `lint-commit.yml` | commitlint + fixup guard; skipped on Dependabot PRs. Without `config` it uses the shared config inside the workflow: the ai-kit commit types plus `product` | `config` |
| `benchmark.yml` | BenchmarkDotNet + result storage | `project`, `ref` |
| `clean-history.yml` | Prune old workflow runs | `retain-days` |
| `auto-approve.yml` | Approve trusted bot PRs | `actors` |
| `auto-merge.yml` | Merge a trusted bot PR once every check passes (Dependabot squash commits are rewritten to `<type>(deps): bump ...`); trigger via `workflow_run` of `Auto Approve` and grant `contents: write`, `pull-requests: write`, `actions: read`, `checks: read`, `statuses: read` | `head-branch` |

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

## Private NuGet feed

A consumer of the owner's GitHub Packages NuGet feed keeps no credentials in its
`nuget.config`; it reads them from the environment:

```xml
<packageSourceCredentials>
  <github-jirikostiha>
    <add key="Username" value="%NUGET_GH_USER%" />
    <add key="ClearTextPassword" value="%NUGET_GH_TOKEN%" />
  </github-jirikostiha>
</packageSourceCredentials>
```

`dotnet-build.yml`, `lint-code.yml` and `code-analysis.yml` set both variables
from the optional `NUGET_GH_TOKEN` secret. The caller passes it:

```yaml
    secrets:
      NUGET_GH_TOKEN: ${{ secrets.NUGET_GH_TOKEN }}
```

Dependabot reads the feed through a registry with the same secret:

```yaml
registries:
  github-jirikostiha:
    type: nuget-feed
    url: https://nuget.pkg.github.com/jirikostiha/index.json
    token: ${{ secrets.NUGET_GH_TOKEN }}
```

The secret is a classic PAT with `read:packages` only. A personal account has
no shared secrets, so `cmd/Set-NuGetFeedSecret.ps1` finds every repository whose
`nuget.config` uses the feed and sets the token there as an Actions and a
Dependabot secret. Run it after creating such a repository or replacing the token.

## Licenses

`cmd/Set-NoAiLicense.ps1` writes the `LICENSE` of one or more repositories from a template
in `templates/`, keeping the holder of the existing `LICENSE`:

| Template | Use for | Year |
|---|---|---|
| `templates/LICENSE-no-ai.template` | public repositories: MIT NON-AI License of [non-ai-licenses](https://github.com/non-ai-licenses/non-ai-licenses), forbids AI training | kept from the existing `LICENSE` |
| `templates/LICENSE-proprietary.template` (`-Proprietary`) | private repositories: all rights reserved | year of the first commit |

The script refuses to replace one of these licenses with the other. It does not edit project
files: it warns about every `PackageLicenseExpression` of `MIT`, which must become
`PackageLicenseFile` with `LICENSE` packed.

`godot-sharp-some` stays on plain MIT: it is published to the Godot Asset Library, which takes
open-source licenses only.

## Notes

- Reusable workflows reference the composite action by **full path**
  (`jirikostiha/ci/.github/actions/setup-dotnet@v1`), never `./` — a local path
  would resolve against the consumer repo.
- Secrets are not inherited. Pass only what a workflow needs via `secrets:`;
  OIDC (`id-token: write`) avoids long-lived keys entirely.
- `environment` approval gates and their secrets live in the **consumer** repo.
