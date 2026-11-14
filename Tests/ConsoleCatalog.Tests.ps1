BeforeAll {
    # Console.json maps an English console string to its localized text. It is not part of
    # Get-LanguageCatalogNames (Chrome/Features/Categories/Apps), so nothing else in the suite
    # notices missing, blank, or half-translated console entries.
    $script:languagesPath = Join-Path $PSScriptRoot '..\Config\Languages'
    $script:placeholderPattern = '\{\d+(?:,[^{}]+)?(?::[^{}]+)?\}'

    function Get-ConsoleCatalogTable {
        param([Parameter(Mandatory)][string]$LanguageCode)

        $path = Join-Path $script:languagesPath "$LanguageCode/Console.json"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing console catalog: $LanguageCode/Console.json"
        }

        $catalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $table = @{}
        foreach ($property in $catalog.PSObject.Properties) {
            $table[$property.Name] = [string]$property.Value
        }
        return $table
    }

    $script:english = Get-ConsoleCatalogTable -LanguageCode 'en-US'
    $script:chinese = Get-ConsoleCatalogTable -LanguageCode 'zh-CN'
}

Describe 'Console catalog contract' {
    It 'ships a populated baseline and Chinese catalog' {
        $script:english.Count | Should -BeGreaterThan 0 -Because 'en-US/Console.json is the key baseline'
        $script:chinese.Count | Should -BeGreaterThan 0 -Because 'zh-CN/Console.json carries the console translations'
    }

    It 'keeps the zh-CN key set identical to the en-US baseline' {
        $missing = @($script:english.Keys | Where-Object { -not $script:chinese.ContainsKey($_) } | Sort-Object)
        $extra = @($script:chinese.Keys | Where-Object { -not $script:english.ContainsKey($_) } | Sort-Object)

        ($missing -join ' | ') | Should -Be '' -Because 'every English console string needs a Chinese entry'
        ($extra -join ' | ') | Should -Be '' -Because 'zh-CN must not keep keys the English baseline dropped'
    }

    It 'has no blank translations' {
        foreach ($key in ($script:chinese.Keys | Sort-Object)) {
            [string]::IsNullOrWhiteSpace($script:chinese[$key]) | Should -BeFalse -Because "zh-CN/$key must not be blank"
        }
    }

    It 'preserves the format placeholders of every English string' {
        foreach ($key in ($script:chinese.Keys | Sort-Object)) {
            $expected = @([regex]::Matches($key, $script:placeholderPattern).Value | Sort-Object)
            $actual = @([regex]::Matches($script:chinese[$key], $script:placeholderPattern).Value | Sort-Object)
            ($actual -join ',') | Should -Be ($expected -join ',') -Because "zh-CN/$key must keep its {n} placeholders"
        }
    }

    It 'translates every long console sentence instead of copying the English source' {
        # Short entries are usually product names or flags and legitimately stay unchanged.
        $allowList = @()
        $untranslated = @($script:chinese.Keys | Where-Object {
                $key = $_
                $key.Length -gt 25 -and $script:chinese[$key] -eq $key -and $key -notin $allowList
            } | Sort-Object)

        ($untranslated -join ' | ') | Should -Be '' -Because 'an untranslated sentence leaves the Chinese console half English'
    }
}
