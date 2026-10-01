<#
    .SYNOPSIS
        Loads the optional per-language display text overlay for the app catalog.

    .DESCRIPTION
        Config/Apps.json is the single, language-neutral source of truth for the catalog and is
        never translated in place. A language folder may ship an optional Apps.json alongside
        Chrome/Features/Categories.json that maps an AppId to replacement display text, so app
        descriptions follow the active language without forking the catalog.

        The overlay is resolved relative to Apps.json (Config/Languages/<code>/Apps.json) rather
        than through $script:LanguagesPath, because this loader also runs inside the app-loading
        background runspace, which has neither the language helper functions nor $script:Lang.

        A missing, unreadable, or malformed overlay resolves to an empty map, so the catalog
        always renders: in English, and in any other language that ships no overlay.

    .PARAMETER LanguageCode
        Language folder to read the overlay from. Defaults to the active GUI language, then to
        the current UI culture.

    .PARAMETER AppsListFilePath
        Path to Config/Apps.json, used to locate the sibling Languages folder.

    .OUTPUTS
        System.Collections.Hashtable mapping AppId to its overlay entry. Empty when none applies.
#>
function Get-AppLocalizationMap {
    param (
        [string]$LanguageCode = $null,
        [string]$AppsListFilePath = $script:AppsListFilePath
    )

    $emptyMap = @{}

    if (-not $LanguageCode) {
        $activeLang = Get-Variable -Name 'Lang' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        $LanguageCode = if ($activeLang -and $activeLang.LanguageCode) {
            $activeLang.LanguageCode
        }
        else {
            [System.Globalization.CultureInfo]::CurrentUICulture.Name
        }
    }

    if (-not $LanguageCode -or -not $AppsListFilePath) { return $emptyMap }

    $cacheKey = "$LanguageCode|$AppsListFilePath"
    if ($script:AppLocalizationCache -and $script:AppLocalizationCache.ContainsKey($cacheKey)) {
        return $script:AppLocalizationCache[$cacheKey]
    }

    $map = $emptyMap
    try {
        $languagesRoot = Join-Path (Split-Path -Path $AppsListFilePath -Parent) 'Languages'
        $languageFolder = Join-Path $languagesRoot $LanguageCode

        if (-not (Test-Path -LiteralPath $languageFolder -PathType Container)) {
            # Same resolution order as Resolve-LanguageFolder: exact folder, then language prefix, then en-US.
            $languagePrefix = ($LanguageCode -split '-')[0]
            $prefixMatch = Get-ChildItem -Path $languagesRoot -Directory -Filter "$languagePrefix-*" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            $languageFolder = if ($prefixMatch) { $prefixMatch.FullName } else { Join-Path $languagesRoot 'en-US' }
        }

        $overlayPath = Join-Path $languageFolder 'Apps.json'
        if (Test-Path -LiteralPath $overlayPath -PathType Leaf) {
            # -Encoding UTF8 matches Import-JsonFile: the language files carry no BOM, and a
            # default read would decode them as ANSI and garble every non-ASCII character.
            $overlay = Get-Content -LiteralPath $overlayPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $map = @{}
            foreach ($entry in @($overlay.Apps)) {
                if (-not $entry -or -not $entry.AppId) { continue }
                $map[[string]$entry.AppId] = $entry
            }
        }
    }
    catch {
        # A broken overlay must never break app loading, so warn and keep the English catalog.
        Write-Warning (Get-ConsoleText "Failed to load the app localization overlay for '{0}': {1}" -FormatArgs @($LanguageCode, $_))
        $map = $emptyMap
    }

    if (-not $script:AppLocalizationCache) { $script:AppLocalizationCache = @{} }
    $script:AppLocalizationCache[$cacheKey] = $map
    return $map
}

<#
    .SYNOPSIS
        Loads application details from Apps.json.

    .DESCRIPTION
        Reads the application definitions from Apps.json, optionally filters the
        results to installed applications, and returns normalized app objects for
        display and selection.

        Config/Apps.json stays the single, language-neutral source of truth. A language folder
        may ship an optional Apps.json that overrides display text per AppId, which is applied
        on top of the catalog here so descriptions follow the active language without forking
        the catalog itself. When no overlay applies, every field renders exactly as before.

    .PARAMETER OnlyInstalled
        Filters the results to applications detected through Appx or the supplied
        winget installation list.

    .PARAMETER InstalledList
        A pre-fetched winget installation list used when filtering installed apps.

    .PARAMETER InitialCheckedFromJson
        Sets each returned app's IsChecked value from its SelectedByDefault setting.

    .PARAMETER LanguageCode
        Language folder to read the optional app text overlay from. Defaults to the active GUI
        language, then to the current UI culture. Supplied explicitly by callers that run this
        loader in a background runspace, which cannot see the active language.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Application detail objects containing display, selection, and removal data.
#>
function Import-AppDetailsFromJson {
    param (
        [switch]$OnlyInstalled,
        [object[]]$InstalledList = $null,
        [switch]$InitialCheckedFromJson,
        [string]$LanguageCode = $null
    )

    $apps = @()
    try {
        $jsonContent = Get-Content -Path $script:AppsListFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error (Get-ConsoleText "Failed to read Apps.json: {0}" -FormatArgs @($_))
        return $apps
    }

    # Optional per-language display text. Empty when the active language ships no overlay,
    # in which case every app keeps the catalog's own English text.
    $appLocalization = Get-AppLocalizationMap -LanguageCode $LanguageCode -AppsListFilePath $script:AppsListFilePath

    foreach ($appData in $jsonContent.Apps) {
        # Handle AppId as array (could be single or multiple IDs)
        $appIdArray = @(
            foreach ($rawAppId in @($appData.AppId)) {
                if ($rawAppId -isnot [string]) { continue }
                $normalizedAppId = $rawAppId.Trim()
                if ($normalizedAppId.Length -gt 0) { $normalizedAppId }
            }
        )
        if ($appIdArray.Count -eq 0) { continue }

        if ($OnlyInstalled) {
            $isInstalled = $false
            foreach ($appId in $appIdArray) {
                # Check Get-AppxPackage first (fast, no process launch)
                if (Get-AppxPackage -Name $appId) {
                    $isInstalled = $true
                    break
                }

                # Then check the pre-fetched winget list
                if ($InstalledList -and (Test-AppInWingetList -appId $appId -InstalledList $InstalledList)) {
                    $isInstalled = $true
                    break
                }
            }

            if (-not $isInstalled) { continue }
        }

        # Use first AppId for fallback names, join all for display
        $primaryAppId = $appIdArray[0]
        $appIdDisplay = $appIdArray -join ', '
        $friendlyName = if ($appData.FriendlyName) { $appData.FriendlyName } else { $primaryAppId }
        $displayName = if ($appData.FriendlyName) { "$($appData.FriendlyName) ($appIdDisplay)" } else { $appIdDisplay }
        $isChecked = if ($InitialCheckedFromJson) { $appData.SelectedByDefault } else { $false }

        # Language overlay wins, but only where it actually supplies text; anything it omits,
        # and every app it doesn't mention, keeps the catalog's original description.
        $description = $appData.Description
        if ($appLocalization.ContainsKey($primaryAppId)) {
            $localizedDescription = $appLocalization[$primaryAppId].Description
            if ($localizedDescription) { $description = [string]$localizedDescription }
        }

        $apps += [PSCustomObject]@{
            AppId = $appIdArray
            AppIdDisplay = $appIdDisplay
            FriendlyName = $friendlyName
            DisplayName = $displayName
            IsChecked = $isChecked
            Description = $description
            SelectedByDefault = $appData.SelectedByDefault
            Recommendation = $appData.Recommendation
            RemovalMethod = if ($appData.RemovalMethod -and $appData.RemovalMethod -eq 'WinGet') { 'WinGet' } else { 'Appx' }
        }
    }

    return $apps
}
