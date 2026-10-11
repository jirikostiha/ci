<#
.SYNOPSIS
Sets the GitHub Packages NuGet token in every repository that consumes the owner's feed.

.DESCRIPTION
Finds each non-archived repository of the owner whose nuget.config refers to the owner's
GitHub Packages NuGet feed, prompts once for the token, and sets it there as an Actions
secret and a Dependabot secret. A personal account has no shared secrets, so run it again
after creating such a repository or after replacing the token.

.PARAMETER Owner
The account that owns the repositories and the feed. Defaults to the signed-in gh user.

.PARAMETER Name
The name of the secret. The reusable workflows of this repository read NUGET_GH_TOKEN.

.EXAMPLE
.\Set-NuGetFeedSecret.ps1
Prompts for the token and sets it in every consuming repository.

.EXAMPLE
.\Set-NuGetFeedSecret.ps1 -WhatIf
Lists the consuming repositories and sets nothing.
#>
<#---
name: Set-NuGetFeedSecret
kind: cmd
description: Sets the GitHub Packages NuGet token as an Actions and a Dependabot secret in every repository whose nuget.config uses the owner's feed. Use after creating such a repository or replacing the token.
version: 1.0.0
---#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Owner,
    [string] $Name = 'NUGET_GH_TOKEN'
)

$ErrorActionPreference = 'Stop'

function Invoke-Gh {
    $output = gh @args
    if ($LASTEXITCODE -ne 0) { throw ("gh {0} failed (exit code: {1})." -f ($args -join ' '), $LASTEXITCODE) }
    $output
}

if (-not $Owner) { $Owner = Invoke-Gh api user --jq .login }
$feed = "nuget.pkg.github.com/$Owner"

$repos = Invoke-Gh repo list $Owner --limit 1000 --no-archived --json 'name,defaultBranchRef' | ConvertFrom-Json
$consumers = foreach ($repo in $repos) {
    # An empty repository has no default branch and so no nuget.config.
    if (-not $repo.defaultBranchRef.name) { continue }

    $branch = [uri]::EscapeDataString($repo.defaultBranchRef.name)
    $tree = Invoke-Gh api "repos/$Owner/$($repo.name)/git/trees/${branch}?recursive=1" | ConvertFrom-Json
    $configs = $tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path -match '(^|/)nuget\.config$' }
    foreach ($config in $configs) {
        $path = ($config.path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        $content = Invoke-Gh api "repos/$Owner/$($repo.name)/contents/${path}?ref=$branch" -H 'Accept: application/vnd.github.raw'
        if (($content -join "`n") -match [regex]::Escape($feed)) {
            $repo.name
            break
        }
    }
}

if (-not $consumers) {
    Write-Warning "No repository of $Owner uses $feed."
    return
}

Write-Host ("Repositories using {0}: {1}" -f $feed, ($consumers -join ', ')) -ForegroundColor Cyan
if (-not $PSCmdlet.ShouldProcess(($consumers -join ', '), "Set secret $Name for Actions and Dependabot")) {
    return
}

$token = [System.Net.NetworkCredential]::new('', (Read-Host "Token with read:packages" -AsSecureString)).Password
if (-not $token) { throw 'No token was entered.' }

foreach ($repo in $consumers) {
    foreach ($app in 'actions', 'dependabot') {
        # Piped, not passed as --body, so the token does not show in the process command line;
        # gh trims the trailing newline that the pipe adds.
        $token | gh secret set $Name --app $app --repo "$Owner/$repo"
        if ($LASTEXITCODE -ne 0) { throw ("Setting {0} for {1} in {2}/{3} failed (exit code: {4})." -f $Name, $app, $Owner, $repo, $LASTEXITCODE) }
    }
    Write-Host "Set $Name in $Owner/$repo" -ForegroundColor Green
}
