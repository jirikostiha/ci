<#
.SYNOPSIS
Writes the LICENSE with the AI training restriction into one or more repositories.

.DESCRIPTION
Renders templates/LICENSE-no-ai.template, or with -Proprietary templates/LICENSE-proprietary.template,
into the LICENSE file at the root of each given repository. The holder is taken from the copyright
line of the existing LICENSE unless -Holder is given. The year is taken from there too, except
with -Proprietary, where it is the year of the first commit of the repository. The script does not
edit project files: it lists the ones that
still declare the MIT expression, because NuGet then shows MIT instead of this license.
Commit the result in each repository yourself.

.PARAMETER Path
Root folder of each repository to update.

.PARAMETER Proprietary
Writes the all-rights-reserved license for a private repository instead of the MIT NON-AI License.

.PARAMETER Force
Replaces a LICENSE that is neither a plain MIT nor a text written by this script, for example Apache-2.0.

.PARAMETER Holder
The copyright holder. When given, it also replaces the holder of an existing LICENSE; otherwise it is used only when there is none to keep.

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

    [switch] $Force,

    [string] $Holder = 'Jiri Kostiha',

    [int] $Year = (Get-Date).Year
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$templateName = $Proprietary ? 'LICENSE-proprietary.template' : 'LICENSE-no-ai.template'
$otherName = $Proprietary ? 'LICENSE-no-ai.template' : 'LICENSE-proprietary.template'
$templateDir = Join-Path $PSScriptRoot '../templates'
$template = Get-Content -LiteralPath (Join-Path $templateDir $templateName) -Raw
# The title line tells which license a repository has.
$title = ($template -split '\r?\n')[0]
$otherTitle = ((Get-Content -LiteralPath (Join-Path $templateDir $otherName) -Raw) -split '\r?\n')[0]

foreach ($root in $Path) {
    $root = (Resolve-Path -LiteralPath $root).Path
    $licensePath = Join-Path $root 'LICENSE'
    $repoYear = $Year
    $existing = $null
    $existingHolder = $null

    if (Test-Path -LiteralPath $licensePath) {
        $existing = (Get-Content -LiteralPath $licensePath -Raw) -replace '\r\n', "`n"
        # Never turn a proprietary license into a permissive one, or the other way round, by accident.
        if ($existing.StartsWith($otherTitle)) {
            throw "$licensePath has the other license of this script. Remove it first to switch."
        }
        # Only a plain MIT and the earlier texts of this script may be replaced; any other license is the author's choice.
        $replaceable = $existing.StartsWith($title) -or $existing -match '^(MIT License|License with AI Training Restriction)'
        if (-not $Force -and -not $replaceable) {
            throw "$licensePath is a license this script does not write. Use -Force to replace it."
        }
        if ($existing -match '(?m)^Copyright \(c\) (\d{4}) (.+?)\.?(?: All rights reserved\.)?\s*$') {
            $repoYear = $Matches[1]
            $existingHolder = $Matches[2]
        }
    }

    # An explicit -Holder wins, so one run can correct the holder in every repository.
    $repoHolder = ($PSBoundParameters.ContainsKey('Holder') -or -not $existingHolder) ? $Holder : $existingHolder

    if ($Proprietary) {
        # The author date survives a rebase, which rewrites the committer date.
        $commitYears = git -C $root log --format=%ad --date=format:%Y
        if ($LASTEXITCODE -ne 0 -or -not $commitYears) { throw "Cannot read the commits of $root." }
        $repoYear = @($commitYears | Sort-Object)[0]
    }

    $text = ($template -replace '\r\n', "`n").Replace('{{YEAR}}', "$repoYear").Replace('{{HOLDER}}', $repoHolder)
    if ($existing -ceq $text) {
        Write-Host "$root already has this license." -ForegroundColor Yellow
        continue
    }

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
