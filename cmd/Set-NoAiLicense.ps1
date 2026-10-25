<#
.SYNOPSIS
Writes the LICENSE with the AI training restriction into one or more repositories.

.DESCRIPTION
Renders templates/LICENSE-no-ai.template into the LICENSE file at the root of each given
repository. The year and the holder are taken from the copyright line of the existing LICENSE,
so a repository keeps its own. The script does not edit project files: it lists the ones that
still declare the MIT expression, because NuGet then shows MIT instead of this license.
Commit the result in each repository yourself.

.PARAMETER Path
Root folder of each repository to update.

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

    [string] $Holder = 'jirikostiha',

    [int] $Year = (Get-Date).Year
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\templates\LICENSE-no-ai.template') -Raw

foreach ($root in $Path) {
    $root = (Resolve-Path -LiteralPath $root).Path
    $licensePath = Join-Path $root 'LICENSE'
    $repoHolder = $Holder
    $repoYear = $Year

    if (Test-Path -LiteralPath $licensePath) {
        $existing = Get-Content -LiteralPath $licensePath -Raw
        if ($existing -match 'AI Training Restriction') {
            Write-Host "$root already has the restriction." -ForegroundColor Yellow
            continue
        }
        if ($existing -match '(?m)^Copyright \(c\) (\d{4}) (.+?)\s*$') {
            $repoYear = $Matches[1]
            $repoHolder = $Matches[2]
        }
    }

    $text = $template.Replace('{{YEAR}}', "$repoYear").Replace('{{HOLDER}}', $repoHolder)
    if ($PSCmdlet.ShouldProcess($licensePath, 'Write LICENSE with AI training restriction')) {
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
