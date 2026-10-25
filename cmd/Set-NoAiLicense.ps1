<#
.SYNOPSIS
Writes the LICENSE with the AI training restriction into one or more repositories.

.DESCRIPTION
Renders templates/LICENSE-no-ai.template, or with -Proprietary templates/LICENSE-proprietary.template,
into the LICENSE file at the root of each given repository. The holder is taken from the copyright
line of the existing LICENSE, so a repository keeps its own. The year is taken from there too, except
with -Proprietary, where it is the year of the first commit of the repository. The script does not
edit project files: it lists the ones that
still declare the MIT expression, because NuGet then shows MIT instead of this license.
Commit the result in each repository yourself.

.PARAMETER Path
Root folder of each repository to update.

.PARAMETER Proprietary
Writes the all-rights-reserved license for a private repository instead of MIT with the restriction.

.PARAMETER Holder
The copyright holder, used when a repository has no LICENSE to read it from.

.PARAMETER Year
The copyright year, used when a repository has no LICENSE to read it from.

.EXAMPLE
.\Set-NoAiLicense.ps1 -Path ..\..\smath, ..\..\atin
Updates the LICENSE of both repositories and lists the project files that need a change.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string[]] $Path,

    [switch] $Proprietary,

    [string] $Holder = 'jirikostiha',

    [int] $Year = (Get-Date).Year
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$templateName = $Proprietary ? 'LICENSE-proprietary.template' : 'LICENSE-no-ai.template'
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\templates\$templateName") -Raw
# The title line tells which license a repository has.
$title = ($template -split '\r?\n')[0]

foreach ($root in $Path) {
    $root = (Resolve-Path -LiteralPath $root).Path
    $licensePath = Join-Path $root 'LICENSE'
    $repoHolder = $Holder
    $repoYear = $Year

    if (Test-Path -LiteralPath $licensePath) {
        $existing = Get-Content -LiteralPath $licensePath -Raw
        if ($existing.StartsWith($title)) {
            Write-Host "$root already has this license." -ForegroundColor Yellow
            continue
        }
        if ($existing -match '(?m)^Copyright \(c\) (\d{4}) (.+?)\.?(?: All rights reserved\.)?\s*$') {
            $repoYear = $Matches[1]
            $repoHolder = $Matches[2]
        }
    }

    if ($Proprietary) {
        # The author date survives a rebase, which rewrites the committer date.
        $commitYears = git -C $root log --format=%ad --date=format:%Y
        if ($LASTEXITCODE -ne 0 -or -not $commitYears) { throw "Cannot read the commits of $root." }
        $repoYear = @($commitYears | Sort-Object)[0]
    }

    $text = $template.Replace('{{YEAR}}', "$repoYear").Replace('{{HOLDER}}', $repoHolder)
    if ($PSCmdlet.ShouldProcess($licensePath, "Write LICENSE from $templateName")) {
        Set-Content -LiteralPath $licensePath -Value $text -NoNewline -Encoding utf8
        Write-Host "Updated $licensePath" -ForegroundColor Green
    }

    $stale = Get-ChildItem -LiteralPath $root -Recurse -Include *.csproj, *.props -File |
        Where-Object { $_.FullName -notmatch '[\\/](\.claude|bin|obj)[\\/]' } |
        Select-String -Pattern '<PackageLicenseExpression>\s*MIT\s*</PackageLicenseExpression>'
    foreach ($hit in $stale) {
        Write-Warning "$($hit.Path):$($hit.LineNumber) declares MIT; switch to PackageLicenseFile and pack LICENSE."
    }
}
