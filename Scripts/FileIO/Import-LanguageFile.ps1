<#
    .SYNOPSIS
        Returns the required language catalog names.

    .OUTPUTS
        System.String. The required catalog names.
#>
function Get-LanguageCatalogNames {
    return @('Chrome', 'Features', 'Categories', 'Apps')
}

<#
    .SYNOPSIS
        Lists language folders containing every required JSON catalog.

    .PARAMETER LanguagesPath
        The directory containing language folders. Defaults to $script:LanguagesPath.

    .OUTPUTS
        System.IO.DirectoryInfo. The available language folders.
#>
function Get-AvailableLanguageFolders {
    param([string]$LanguagesPath = $script:LanguagesPath)

    $catalogNames = Get-LanguageCatalogNames
    foreach ($folder in (Get-ChildItem -LiteralPath $LanguagesPath -Directory | Sort-Object Name)) {
        $missingCatalogs = @($catalogNames | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $folder.FullName "$_.json") -PathType Leaf)
        })
        if ($missingCatalogs.Count -eq 0) { $folder }
    }
}

<#
    .SYNOPSIS
        Resolves a language code to an available Config/Languages folder, or falls back to en-US.
#>
function Resolve-LanguageFolder {
    param(
        [Parameter(Mandatory)]
        [string]$LanguageCode,
        [string]$LanguagesPath = $script:LanguagesPath
    )

    $exactPath = Join-Path $LanguagesPath $LanguageCode
    if (Test-Path $exactPath -PathType Container) {
        return $LanguageCode
    }

    $languagePrefix = ($LanguageCode -split '-')[0]
    $prefixMatch = Get-ChildItem -Path $LanguagesPath -Directory -Filter "$languagePrefix-*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($prefixMatch) {
        return $prefixMatch.Name
    }

    return 'en-US'
}

<#
    .SYNOPSIS
        Loads Chrome/Features/Categories/Apps JSON for a language folder, or returns $null on failure.
#>
function Import-LanguageContent {
    param(
        [Parameter(Mandatory)]
        [string]$LanguageFolder,
        [string]$LanguagesPath = $script:LanguagesPath
    )

    $folderPath = Join-Path $LanguagesPath $LanguageFolder
    $catalogs = @{}
    foreach ($name in (Get-LanguageCatalogNames)) {
        $catalogs[$name] = Import-JsonFile -filePath (Join-Path $folderPath "$name.json")
    }
    if (@($catalogs.Values | Where-Object { -not $_ }).Count) { return $null }

    # Console.json is optional and not part of the required catalog list: only this fork ships one, so a
    # language folder without it has to load anyway. Get-ConsoleText falls back to the English source
    # text when the section is missing or lacks the key.
    $console = Import-JsonFile -filePath (Join-Path $folderPath 'Console.json') -optionalFile

    return [PSCustomObject]@{
        LanguageCode = $LanguageFolder
        Chrome       = $catalogs.Chrome
        Features     = $catalogs.Features.Features
        UiGroups     = $catalogs.Features.UiGroups
        Categories   = $catalogs.Categories
        Apps         = $catalogs.Apps
        Console      = $console
    }
}

<#
    .SYNOPSIS
        Loads the active language content, falling back to en-US when the requested language fails to load.
#>
function Import-LanguageFile {
    param(
        [string]$LanguageCode = ([System.Globalization.CultureInfo]::CurrentUICulture.Name),
        [string]$LanguagesPath = $script:LanguagesPath
    )

    $resolvedFolder = Resolve-LanguageFolder -LanguageCode $LanguageCode -LanguagesPath $LanguagesPath
    $content = Import-LanguageContent -LanguageFolder $resolvedFolder -LanguagesPath $LanguagesPath

    if (-not $content -and $resolvedFolder -ne 'en-US') {
        Write-Warning "Failed to load language '$resolvedFolder', falling back to en-US."
        $content = Import-LanguageContent -LanguageFolder 'en-US' -LanguagesPath $LanguagesPath
    }

    if (-not $content) {
        Write-Error "Unable to load the en-US language files. The GUI cannot continue without them."
        return $null
    }

    if ($content.LanguageCode -ne 'en-US') {
        $content | Add-Member -MemberType NoteProperty -Name 'Fallback' -Value (Import-LanguageContent -LanguageFolder 'en-US' -LanguagesPath $LanguagesPath)
    }

    return $content
}

<#
    .SYNOPSIS
        Returns the CLDR plural category ('one', 'other', etc.) for a count in the given language.

    .DESCRIPTION
        Each language's CLDR plural rule is its own case, keyed by language prefix ('en' matches
        both 'en-US' and 'en-GB'). A language without a case falls back to the English rule, which
        is also correct for Dutch and German but wrong for languages with 3+ plural categories or
        a different singular/plural split.
#>
function Get-PluralCategory {
    param(
        [Parameter(Mandatory)]
        [string]$LanguageCode,
        [Parameter(Mandatory)]
        [int]$Count
    )

    $languagePrefix = ($LanguageCode -split '-')[0].ToLowerInvariant()

    switch ($languagePrefix) {
        'zh' { return 'other' }
        # Portuguese CLDR rule: 'one' for 0 and 1, 'many' for positive multiples
        # of 1,000,000, and 'other' for every remaining count.
        'pt' {
            if ($Count -le 1) {
                return 'one'
            }

            if ($Count % 1000000 -eq 0) {
                return 'many'
            }

            return 'other'
        }
        # French CLDR rule: 'one' covers 0 and 1, 'other' every remaining count. CLDR also
        # defines 'many' for whole multiples of 1,000,000, but it is deliberately not
        # returned here: the catalogs ship no '_many' variants, and a category with no
        # matching key falls through to the bare key (which does not exist) rather than
        # to '_other', so returning 'many' would print the raw key name at that count.
        'fr' {
            if ($Count -le 1) {
                return 'one'
            }

            return 'other'
        }
        # Japanese CLDR rule: no grammatical plural, every count is 'other'.
        'ja' {
            return 'other'
        }
        # Russian CLDR rule for whole numbers: 'one' for 1, 21, 31... (not 11), 'few' for 2-4, 22-24...
        # (not 12-14), 'many' for every other count (0, 5-20, 25-30...).
        'ru' {
            $absoluteCount = [Math]::Abs($Count)
            $lastDigit = $absoluteCount % 10
            $lastTwoDigits = $absoluteCount % 100
            if ($lastDigit -eq 1 -and $lastTwoDigits -ne 11) {
                return 'one'
            }

            if ($lastDigit -ge 2 -and $lastDigit -le 4 -and ($lastTwoDigits -lt 12 -or $lastTwoDigits -gt 14)) {
                return 'few'
            }

            return 'many'
        }
        # Korean has no grammatical plural, like Japanese, so every count is 'other'.
        'ko' {
            return 'other'
        }
        # English CLDR rule: singular only for exactly 1, plural otherwise. Also correct for Dutch/German.
        default {
            if ($Count -eq 1) {
                return 'one'
            }

            return 'other'
        }
    }
}

<#
    .SYNOPSIS
        Returns a language and its Fallback (if any) as an ordered lookup chain, skipping nulls.
#>
function Get-LanguageFallbackChain {
    param(
        [object]$Lang
    )

    return @($Lang, $Lang.Fallback) | Where-Object { $_ }
}

<#
    .SYNOPSIS
        Finds the named section object (Chrome, Features, UiGroups, Categories, or Apps) that owns a key.

    .DESCRIPTION
        A FeatureId, GroupId, and CategoryId aren't guaranteed to be disjoint (Config/Features.json
        can and does reuse the same string as both a GroupId and a FeatureId), so the default search
        order below is only a fallback for callers who don't know which section their key belongs to.
        Pass -Section to look in exactly one section instead of guessing from the order.
#>
function Find-TranslationSection {
    param(
        [Parameter(Mandatory)]
        [object]$Lang,
        [Parameter(Mandatory)]
        [string]$Key,
        [ValidateSet('', 'Chrome', 'Features', 'UiGroups', 'Categories', 'Apps')]
        [string]$Section = ''
    )

    if ($Section) {
        $sectionObject = $Lang.$Section
        if ($sectionObject -and $sectionObject.PSObject.Properties[$Key]) {
            return $sectionObject
        }
        return $null
    }

    foreach ($sectionName in 'Chrome', 'Features', 'UiGroups', 'Categories', 'Apps') {
        $sectionObject = $Lang.$sectionName
        if ($sectionObject -and $sectionObject.PSObject.Properties[$Key]) {
            return $sectionObject
        }
    }

    return $null
}

<#
    .SYNOPSIS
        Looks up a translated value from the active language, falling back to en-US, then to the key itself.

    .DESCRIPTION
        Chrome.json keys are flat strings, so -Field is omitted for those. Features/UiGroups/Categories/Apps
        keys (FeatureId/GroupId/CategoryId/AppId) resolve to an object, so -Field picks the property on it
        (Label, ToolTip, ApplyText, UndoLabel, ApplyUndoText for Features/UiGroups/Categories;
        FriendlyName, Description for Apps). One generic lookup covers every section instead of a
        separate function per section.

        A FeatureId and a GroupId aren't guaranteed to be distinct strings, so pass -Section
        ('Features', 'UiGroups', 'Categories', or 'Apps') whenever the caller knows which one it
        means, rather than relying on Find-TranslationSection's search order to guess correctly.

        When -Count is supplied, tries the plural-suffixed key ("$Key`_$category") before the bare key,
        so callers don't need to add a plural variant for every string, only the ones that need one.
    .OUTPUTS
        System.String. The translated string, or the original Key if no language has it.
#>
function Get-Translation {
    param(
        [Parameter(Mandatory)]
        [string]$Key,
        [string]$Field = $null,
        [object]$Lang = $script:Lang,
        [Nullable[int]]$Count = $null,
        [object[]]$FormatArgs = $null,
        [ValidateSet('', 'Chrome', 'Features', 'UiGroups', 'Categories', 'Apps')]
        [string]$Section = ''
    )

    if (-not $Lang) {
        return $Key
    }

    $lookupKeys = @($Key)
    if ($null -ne $Count) {
        $category = Get-PluralCategory -LanguageCode $Lang.LanguageCode -Count $Count
        $lookupKeys = @("${Key}_$category", $Key)
    }

    $resolved = $Key
    :langLoop foreach ($candidateLang in (Get-LanguageFallbackChain -Lang $Lang)) {
        foreach ($lookupKey in $lookupKeys) {
            $sectionObject = Find-TranslationSection -Lang $candidateLang -Key $lookupKey -Section $Section
            if (-not $sectionObject) { continue }

            $entry = $sectionObject.$lookupKey
            if ($Field) {
                if ($entry.PSObject.Properties[$Field]) {
                    $resolved = [string]$entry.$Field
                    break langLoop
                }
                continue
            }

            $resolved = [string]$entry
            break langLoop
        }
    }

    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        try {
            return $resolved -f $FormatArgs
        }
        catch {
            Write-Warning "Translation '$Key' has a placeholder mismatch with its format arguments: $($_.Exception.Message)"
            return $resolved
        }
    }

    return $resolved
}

<#
    .SYNOPSIS
        Looks up a translated label for one value of a UiGroup, falling back to en-US, then to the raw label.

    .DESCRIPTION
        UiGroups[GroupId].Values in the language files is a FeatureId -> Label map, one level deeper
        than Get-Translation's -Field lookup handles, so this has its own small fallback walk instead
        of overloading Get-Translation's flat-field shape.
#>
function Get-GroupValueTranslation {
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,
        [Parameter(Mandatory)]
        [string]$FeatureId,
        [Parameter(Mandatory)]
        [string]$FallbackLabel,
        [object]$Lang = $script:Lang
    )

    if (-not $Lang) {
        return $FallbackLabel
    }

    foreach ($candidateLang in (Get-LanguageFallbackChain -Lang $Lang)) {
        if (-not $candidateLang.UiGroups) { continue }

        $group = $candidateLang.UiGroups.$GroupId
        if (-not $group -or -not $group.Values) { continue }

        $valueEntry = $group.Values.PSObject.Properties[$FeatureId]
        if ($valueEntry) {
            return [string]$valueEntry.Value
        }
    }

    return $FallbackLabel
}

<#
    .SYNOPSIS
        Flattens a loaded language object into a sorted set of dotted key paths.

    .DESCRIPTION
        Chrome.json keys are already flat and are used as-is. Features/UiGroups/Categories/Apps
        keys are one level deeper (EntryId -> {Field: value}), so each field becomes its own
        "Section.EntryId.Field" path (e.g. "Features.DisableTelemetry.Label"). UiGroups' nested
        Values map becomes "UiGroups.GroupId.Values.FeatureId". Used by Test-LanguageKeyCoverage
        to diff one language's key set against another's.
#>
function Get-LanguageKeyPaths {
    param(
        [Parameter(Mandatory)]
        [object]$Lang
    )

    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($chromeKey in @($Lang.Chrome.PSObject.Properties.Name)) {
        if ([string]::IsNullOrEmpty($chromeKey)) { continue }
        $paths.Add($chromeKey)
    }

    foreach ($sectionName in 'Features', 'Categories', 'Apps') {
        $section = $Lang.$sectionName
        if (-not $section) { continue }

        foreach ($entryId in @($section.PSObject.Properties.Name)) {
            if ([string]::IsNullOrEmpty($entryId)) { continue }
            foreach ($field in @($section.$entryId.PSObject.Properties.Name)) {
                if ([string]::IsNullOrEmpty($field)) { continue }
                $paths.Add("$sectionName.$entryId.$field")
            }
        }
    }

    foreach ($groupId in @($Lang.UiGroups.PSObject.Properties.Name)) {
        if ([string]::IsNullOrEmpty($groupId)) { continue }
        $group = $Lang.UiGroups.$groupId
        foreach ($field in @($group.PSObject.Properties.Name)) {
            if ([string]::IsNullOrEmpty($field)) { continue }
            if ($field -eq 'Values') {
                foreach ($featureId in @($group.Values.PSObject.Properties.Name)) {
                    if ([string]::IsNullOrEmpty($featureId)) { continue }
                    $paths.Add("UiGroups.$groupId.Values.$featureId")
                }
                continue
            }
            $paths.Add("UiGroups.$groupId.$field")
        }
    }

    return @($paths | Sort-Object -Unique)
}

<#
    .SYNOPSIS
        Diffs a language's key set against a baseline language, reporting missing and extra keys.

    .DESCRIPTION
        Loads both languages fresh from disk (independent of any already-cached $script:Lang),
        flattens each with Get-LanguageKeyPaths, and compares the two sets. Intended to run
        against en-US as the baseline; useful today (catches a key present in one en-US file but
        not another) and becomes the real translation-completeness check once non-English
        language folders are contributed.

    .OUTPUTS
        PSCustomObject with ResolvedLanguageCode (the folder actually compared, after the same
        exact/prefix/en-US resolution Import-LanguageFile applies), MissingKeys (present in
        Baseline, absent from LanguageCode), and ExtraKeys (present in LanguageCode, absent from
        Baseline) properties, the latter two sorted arrays.
#>
function Test-LanguageKeyCoverage {
    param(
        [Parameter(Mandatory)]
        [string]$LanguageCode,
        [string]$BaselineLanguageCode = 'en-US',
        [string]$LanguagesPath = $script:LanguagesPath
    )

    $resolvedLanguageCode = Resolve-LanguageFolder -LanguageCode $LanguageCode -LanguagesPath $LanguagesPath
    $baseline = Import-LanguageContent -LanguageFolder $BaselineLanguageCode -LanguagesPath $LanguagesPath
    $target = Import-LanguageContent -LanguageFolder $resolvedLanguageCode -LanguagesPath $LanguagesPath

    if (-not $baseline -or -not $target) {
        Write-Error "Unable to load language content for coverage comparison ('$BaselineLanguageCode' vs '$resolvedLanguageCode')."
        return $null
    }

    $baselineKeys = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-LanguageKeyPaths -Lang $baseline))
    $targetKeys = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-LanguageKeyPaths -Lang $target))

    $missingKeys = @($baselineKeys | Where-Object { -not $targetKeys.Contains($_) } | Sort-Object)
    $extraKeys = @($targetKeys | Where-Object { -not $baselineKeys.Contains($_) } | Sort-Object)

    return [PSCustomObject]@{
        ResolvedLanguageCode = $resolvedLanguageCode
        MissingKeys          = $missingKeys
        ExtraKeys            = $extraKeys
    }
}

<#
    .SYNOPSIS
        Replaces %LANG:Key% markers with translated text or dynamic language resources.

    .DESCRIPTION
        Resolves Chrome catalog markers using the active language and its English fallback.
        Supports embedded text or dynamic resources for windows that allow language changes.
        Throws when a marker's key is missing from both languages.

    .PARAMETER Xaml
        The XAML text containing %LANG:Key% markers to replace.

    .PARAMETER Lang
        The loaded language object and its optional Fallback. Defaults to $script:Lang.

    .PARAMETER DynamicResources
        Uses DynamicResource references to Language_<key> resources for live language updates.
        The window must provide those resources. When omitted, embeds XML-escaped translated text.

    .OUTPUTS
        System.String. The XAML text with localization markers replaced.
#>
function ConvertTo-LocalizedXaml {
    param(
        [Parameter(Mandatory)]
        [string]$Xaml,
        [object]$Lang = $script:Lang,
        # For live windows, keep a resource reference instead of embedding the translated text.
        [switch]$DynamicResources
    )

    $missingKeys = New-Object System.Collections.Generic.List[string]

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $key = $match.Groups[1].Value
        $resolvesSomewhere = @(Get-LanguageFallbackChain -Lang $Lang) | Where-Object { $_.Chrome -and $_.Chrome.PSObject.Properties[$key] }
        if (-not $resolvesSomewhere) { $missingKeys.Add($key) }
        if ($DynamicResources) { return "{DynamicResource Language_$key}" }
        $value = if ($resolvesSomewhere) { Get-Translation -Key $key -Lang $Lang } else { $key }
        return [System.Security.SecurityElement]::Escape($value)
    }

    $result = [System.Text.RegularExpressions.Regex]::Replace($Xaml, '%LANG:([A-Za-z0-9_]+)%', $evaluator)

    if ($missingKeys.Count -gt 0) {
        throw "Unresolved localization marker(s) in XAML, key(s) not found in any language: $($missingKeys -join ', ')"
    }

    return $result
}

<#
    .SYNOPSIS
        Returns the localized text for a console or log message, keyed by its English source text.

    .DESCRIPTION
        Console and log output is written as inline English literals all over the scripts, well
        before the GUI localization framework existed. Rather than inventing a semantic key for
        every one of those strings and parking them in Chrome.json (a GUI-shaped file), the English
        source text itself is the key: a Console.json in the active language folder maps English
        source -> localized text.

        Lookup walks the same chain as every other translation (active language, then en-US), and
        falls back to the English source text itself. That fallback is what keeps a partially
        translated or entirely missing Console.json printing readable English instead of a key
        name or an empty line.

        Callers that run without an active language (the standalone launcher and the background
        runspaces that load the apps list) resolve Console.json for the current UI culture on
        first use instead, so console text stays localized there too.

        -FormatArgs fills the {0}, {1}... placeholders in the resolved text. Call sites that used
        string interpolation convert their variables into placeholders in first-seen order, so the
        numbering here matches the order the call site passed them in.
#>
function Get-ConsoleText {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,
        [object[]]$FormatArgs = $null,
        [object]$Lang = $script:Lang
    )

    # $global:Win11DebloatConsoleLanguage pins console output to one language. The Pester suite sets
    # it so assertions can match the English source strings regardless of the machine's UI culture;
    # it is never set during a normal run.
    if ($global:Win11DebloatConsoleLanguage) {
        $Lang = Get-ConsoleFallbackLanguage
    }

    $chain = @(Get-LanguageFallbackChain -Lang $Lang)
    if ($chain.Count -eq 0) {
        $chain = @(Get-ConsoleFallbackLanguage)
    }

    $resolved = $Text

    foreach ($candidateLang in $chain) {
        if (-not $candidateLang.Console) { continue }

        $entry = $candidateLang.Console.PSObject.Properties[$Text]
        if ($entry) {
            $resolved = [string]$entry.Value
            break
        }
    }

    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        try {
            return $resolved -f $FormatArgs
        }
        catch {
            # A malformed placeholder in a translation must never take down a console message.
            return $resolved
        }
    }

    return $resolved
}

<#
    .SYNOPSIS
        Lazily loads Console.json for the current UI culture, for callers with no active language.

    .DESCRIPTION
        Standalone launcher scripts and background runspaces print console text without ever calling
        Import-LanguageFile, so $script:Lang is empty there. Rather than making every such call site
        load a full language, Get-ConsoleText falls back to this: resolve the folder for the current
        UI culture (same exact/prefix/en-US rules) and read just Console.json. The result is cached
        per runspace, including the negative case, so a language without Console.json pays the
        directory probe only once.
#>
function Get-ConsoleFallbackLanguage {
    if (-not $script:ConsoleFallbackLoaded) {
        $script:ConsoleFallbackLoaded = $true
        $script:ConsoleFallbackLanguage = $null

        # $PSScriptRoot is Scripts/FileIO, so two levels up is the Win11Debloat root.
        $languagesPath = $script:LanguagesPath
        if (-not $languagesPath) {
            $languagesPath = Join-Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) 'Config\Languages'
        }

        if (Test-Path -LiteralPath $languagesPath -PathType Container) {
            $cultureName = if ($global:Win11DebloatConsoleLanguage) {
                [string]$global:Win11DebloatConsoleLanguage
            }
            else {
                [System.Globalization.CultureInfo]::CurrentUICulture.Name
            }

            $resolved = Resolve-LanguageFolder -LanguageCode $cultureName -LanguagesPath $languagesPath
            $consolePath = Join-Path (Join-Path $languagesPath $resolved) 'Console.json'

            $script:ConsoleFallbackLanguage = [PSCustomObject]@{
                LanguageCode = $resolved
                Console      = if (Test-Path -LiteralPath $consolePath) { Import-JsonFile -filePath $consolePath } else { $null }
            }
        }
    }

    return $script:ConsoleFallbackLanguage
}
