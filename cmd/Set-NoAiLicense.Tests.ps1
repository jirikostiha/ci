#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'Set-NoAiLicense.ps1'

    # Creates a repository with one commit. The committer date differs from the author date on purpose:
    # a rebase does the same, and the script must read the author date.
    function New-TestRepo {
        param(
            [string] $Name,
            [string] $AuthorDate = '2020-05-01T10:00:00',
            [string] $License
        )

        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root | Out-Null
        if ($License) { [IO.File]::WriteAllText((Join-Path $root 'LICENSE'), $License) }
        Set-Content -LiteralPath (Join-Path $root 'file.txt') -Value 'x'
        git -C $root init -q
        git -C $root add -A
        $env:GIT_AUTHOR_DATE = $AuthorDate
        $env:GIT_COMMITTER_DATE = '2023-05-01T10:00:00'
        try { git -C $root -c user.name=test -c user.email=test@example.com commit -q -m 'initial' }
        finally { Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE }
        $root
    }

    function Read-License($Root) { (Get-Content -LiteralPath (Join-Path $Root 'LICENSE') -Raw) -replace '\r\n', "`n" }

    $script:Mit = "MIT License`n`nCopyright (c) 2021 Some Holder`n`nPermission is hereby granted.`n"
}

Describe 'Set-NoAiLicense' {
    It 'writes the public license for a repository without one' {
        $root = New-TestRepo 'none'

        & $Script -Path $root -Year 2030 6>$null

        $text = Read-License $root
        $text | Should -BeLike 'MIT NON-AI License*'
        $text | Should -Match '(?m)^Copyright \(c\) 2030 Jiri Kostiha$'
    }

    It 'keeps the year and the holder of a plain MIT license' {
        $root = New-TestRepo 'mit' -License $Mit

        & $Script -Path $root 6>$null

        Read-License $root | Should -Match '(?m)^Copyright \(c\) 2021 Some Holder$'
    }

    It 'replaces the holder when -Holder is given' {
        $root = New-TestRepo 'holder' -License $Mit

        & $Script -Path $root -Holder 'Jiri Kostiha' 6>$null

        Read-License $root | Should -Match '(?m)^Copyright \(c\) 2021 Jiri Kostiha$'
    }

    It 'leaves a license that is already current untouched' {
        $root = New-TestRepo 'current'
        & $Script -Path $root 6>$null
        $before = (Get-Item (Join-Path $root 'LICENSE')).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50

        $output = & $Script -Path $root 6>&1 | Out-String

        $output | Should -Match 'already has this license'
        (Get-Item (Join-Path $root 'LICENSE')).LastWriteTimeUtc | Should -Be $before
    }

    It 'rewrites a license of the same title whose text is outdated' {
        $root = New-TestRepo 'outdated' -License "MIT NON-AI License`n`nCopyright (c) 2022 Jiri Kostiha`n`nold text`n"

        & $Script -Path $root 6>$null

        $text = Read-License $root
        $text | Should -Not -Match 'old text'
        $text | Should -Match '(?m)^Copyright \(c\) 2022 Jiri Kostiha$'
    }

    It 'does not write with -WhatIf' {
        $root = New-TestRepo 'whatif'

        & $Script -Path $root -WhatIf 6>$null

        Test-Path (Join-Path $root 'LICENSE') | Should -BeFalse
    }

    It 'takes the proprietary year from the author date, not the committer date' {
        $root = New-TestRepo 'prop'

        & $Script -Path $root -Proprietary 6>$null

        $text = Read-License $root
        $text | Should -BeLike 'Proprietary License.*'
        $text | Should -Match '(?m)^Copyright \(c\) 2020 Jiri Kostiha\. All rights reserved\.$'
    }

    It 'reads the holder back from a proprietary license' {
        $root = New-TestRepo 'prop-holder'
        & $Script -Path $root -Proprietary -Holder 'Other Name' 6>$null

        & $Script -Path $root -Proprietary 6>$null

        Read-License $root | Should -Match '(?m)^Copyright \(c\) 2020 Other Name\. All rights reserved\.$'
    }

    It 'throws for -Proprietary in a repository without commits' {
        $root = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $root | Out-Null
        git -C $root init -q

        { & $Script -Path $root -Proprietary 6>$null 2>$null } | Should -Throw
    }

    It 'refuses to turn a proprietary license into the public one' {
        $root = New-TestRepo 'switch-down'
        & $Script -Path $root -Proprietary 6>$null

        { & $Script -Path $root 6>$null } | Should -Throw '*other license*'
    }

    It 'refuses to turn the public license into the proprietary one' {
        $root = New-TestRepo 'switch-up'
        & $Script -Path $root 6>$null

        { & $Script -Path $root -Proprietary 6>$null } | Should -Throw '*other license*'
    }

    It 'replaces a plain MIT license with the proprietary one' {
        $root = New-TestRepo 'mit-to-prop' -License $Mit

        & $Script -Path $root -Proprietary 6>$null

        Read-License $root | Should -BeLike 'Proprietary License.*'
    }

    It 'refuses to replace a foreign license without -Force' {
        $root = New-TestRepo 'apache' -License "Apache License`nVersion 2.0`n"

        { & $Script -Path $root 6>$null } | Should -Throw '*-Force*'
        Read-License $root | Should -BeLike 'Apache License*'
    }

    It 'replaces a foreign license with -Force' {
        $root = New-TestRepo 'apache-force' -License "Apache License`nVersion 2.0`n"

        & $Script -Path $root -Force 6>$null

        Read-License $root | Should -BeLike 'MIT NON-AI License*'
    }

    It 'warns about a project that still declares MIT' {
        $root = New-TestRepo 'pkg'
        Set-Content -LiteralPath (Join-Path $root 'p.csproj') -Value '<Project><PropertyGroup><PackageLicenseExpression>MIT</PackageLicenseExpression></PropertyGroup></Project>'

        & $Script -Path $root -WarningVariable warnings -WarningAction SilentlyContinue 6>$null

        $warnings | Should -Not -BeNullOrEmpty
        "$warnings" | Should -BeLike '*p.csproj*declares MIT*'
    }
}
