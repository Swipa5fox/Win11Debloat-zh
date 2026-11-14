BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:setVersionScript = Join-Path $script:repositoryRoot 'Scripts/Set-ReleaseVersion.ps1'

    function ConvertTo-ComparableVersion {
        param([Parameter(Mandatory)][string]$Tag)

        $parts = @($Tag.TrimStart('v').Split('.') | ForEach-Object { [int]$_ })
        while ($parts.Count -lt 4) { $parts += 0 }
        return $parts
    }
}

Describe 'Set-ReleaseVersion script' {
    BeforeEach {
        $script:fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
        $script:sourcePath = Join-Path $script:fixtureRoot 'Win11Debloat.ps1'
        $source = @'
$script:Version = "2026.10.31"
$script:ReleaseVersion = "v0.1.5.1"
'@
        [IO.File]::WriteAllText($script:sourcePath, $source, [Text.UTF8Encoding]::new($true))
    }

    It 'rewrites only the release version assignment' {
        & $script:setVersionScript -Tag 'v0.1.5.2' -SourcePath $script:fixtureRoot

        $text = [IO.File]::ReadAllText($script:sourcePath)
        $text | Should -Match '\$script:Version = "2026\.10\.31"'
        $text | Should -Match '\$script:ReleaseVersion = "v0\.1\.5\.2"'
    }

    It 'rejects invalid tags without touching the file' -ForEach @(
        @{ Tag = '0.1.5.2' }
        @{ Tag = 'v0.1' }
        @{ Tag = 'v0.1.5.2-beta' }
        @{ Tag = 'v0.1.5.2 ' }
    ) {
        { & $script:setVersionScript -Tag $Tag -SourcePath $script:fixtureRoot } | Should -Throw
        [IO.File]::ReadAllText($script:sourcePath) | Should -Match 'v0\.1\.5\.1'
    }

    It 'keeps the script UTF-8 with BOM' {
        & $script:setVersionScript -Tag 'v0.1.6' -SourcePath $script:fixtureRoot

        $bytes = [IO.File]::ReadAllBytes($script:sourcePath)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }

    It 'refuses a source tree without a release version assignment' {
        [IO.File]::WriteAllText($script:sourcePath, '$script:Version = "2026.10.31"', [Text.UTF8Encoding]::new($true))

        { & $script:setVersionScript -Tag 'v0.1.6' -SourcePath $script:fixtureRoot } | Should -Throw '*release version*'
    }
}

Describe 'Shipped release version' {
    BeforeAll {
        $script:text = [IO.File]::ReadAllText((Join-Path $script:repositoryRoot 'Win11Debloat.ps1'))
        $script:declared = [regex]::Match($script:text, '(?m)^\$script:ReleaseVersion = "(?<tag>[^"]+)"\r?$')
    }

    It 'uses a v-prefixed numeric version' {
        $script:declared.Success | Should -BeTrue
        $script:declared.Groups['tag'].Value | Should -Match '^v\d+\.\d+\.\d+(\.\d+)?$'
    }

    It 'is not older than the newest reachable git tag' {
        $latest = & git -C $script:repositoryRoot describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($latest)) {
            Set-ItResult -Skipped -Because 'no reachable tag in this checkout (shallow clone or fresh repository)'
            return
        }

        $latestParts = ConvertTo-ComparableVersion -Tag $latest.Trim()
        $declaredParts = ConvertTo-ComparableVersion -Tag $script:declared.Groups['tag'].Value
        $behind = $false
        for ($index = 0; $index -lt 4; $index++) {
            if ($declaredParts[$index] -lt $latestParts[$index]) { $behind = $true; break }
            if ($declaredParts[$index] -gt $latestParts[$index]) { break }
        }
        $behind | Should -BeFalse -Because "ReleaseVersion must not lag behind tag $($latest.Trim())"
    }
}
