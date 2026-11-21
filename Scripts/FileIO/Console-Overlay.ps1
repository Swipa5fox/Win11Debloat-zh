# Runtime console localization overlay.
#
# Console.json keys are the English source strings and its values are the localized
# text. Upstream scripts call Write-Host with their own English text; this proxy
# translates the first argument before handing it to the real cmdlet. Call sites
# therefore do not need a Get-ConsoleText wrapper, which keeps the upstream files
# byte-identical and keeps them out of future merge conflicts.
#
# Two lookups are used:
#   * exact   - a plain hash table, for messages without placeholders
#   * regex   - one compiled regex per placeholder template. A script interpolates
#               its variables before Write-Host sees the text, so the template
#               "Unblocking {0} file(s)..." has to be matched against the already
#               formatted "Unblocking 3 file(s)...".

$script:ConsoleOverlayExact = @{}
$script:ConsoleOverlayTemplates = @()
$script:ConsoleOverlayReady = $false
$script:ConsoleOverlayCmdlet = $null
$script:ConsoleOverlayWarningCmdlet = $null

function Initialize-ConsoleOverlay {
    param(
        [Parameter(Mandatory)][string]$LanguagesPath,
        [object]$Lang
    )

    $script:ConsoleOverlayExact = @{}
    $script:ConsoleOverlayTemplates = @()
    $script:ConsoleOverlayReady = $false

    # The test suite pins the console language to English so assertions can match
    # the source strings; the overlay must stay out of the way when it does.
    if ($global:Win11DebloatConsoleLanguage) { return }

    $catalog = $null
    if ($Lang -and $Lang.Console) {
        $catalog = $Lang.Console
    }
    else {
        $code = if ($Lang -and $Lang.LanguageCode) { $Lang.LanguageCode } else { 'en-US' }
        $path = Join-Path (Join-Path $LanguagesPath $code) 'Console.json'
        if (Test-Path -LiteralPath $path) {
            $catalog = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    if (-not $catalog) { return }

    $templates = New-Object System.Collections.ArrayList
    foreach ($prop in $catalog.PSObject.Properties) {
        $key = $prop.Name
        $value = [string]$prop.Value
        if ([string]::IsNullOrEmpty($key) -or [string]::IsNullOrEmpty($value)) { continue }

        if ($key -notmatch '\{\d+\}') {
            $script:ConsoleOverlayExact[$key] = $value
            continue
        }

        $indices = @([regex]::Matches($key, '\{(\d+)\}') | ForEach-Object { [int]$_.Groups[1].Value })
        $parts = [regex]::Split($key, '\{\d+\}')
        $pattern = '^'
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($i -gt 0) { $pattern += '(.+?)' }
            $pattern += [regex]::Escape($parts[$i])
        }
        $pattern += '$'

        try { $regex = [regex]::new($pattern) } catch { continue }

        [void]$templates.Add([pscustomobject]@{
                Regex        = $regex
                Translation  = $value
                Indices      = $indices
                MaxIndex     = ($indices | Measure-Object -Maximum).Maximum
                FirstLiteral = $parts[0]
                FixedLength  = ($parts | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum
            })
    }

    # More constrained templates first: "> {0} for user {1}..." also matches
    # "> Disabling ... for user {1}...", so the generic one must not win.
    $script:ConsoleOverlayTemplates = @($templates | Sort-Object -Property FixedLength -Descending)
    $script:ConsoleOverlayReady = $true
}

function ConvertTo-ConsoleOverlayText {
    param([string]$Text)

    if (-not $script:ConsoleOverlayReady) { return $Text }
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    if ($script:ConsoleOverlayExact.ContainsKey($Text)) { return $script:ConsoleOverlayExact[$Text] }

    foreach ($t in $script:ConsoleOverlayTemplates) {
        if ($t.FirstLiteral.Length -gt 0 -and -not $Text.StartsWith($t.FirstLiteral, [System.StringComparison]::Ordinal)) { continue }

        $match = $t.Regex.Match($Text)
        if (-not $match.Success) { continue }

        $values = New-Object object[] ($t.MaxIndex + 1)
        for ($i = 0; $i -lt $t.Indices.Count; $i++) {
            $values[$t.Indices[$i]] = $match.Groups[$i + 1].Value
        }
        try { return [string]::Format($t.Translation, $values) } catch { return $t.Translation }
    }

    return $Text
}

# A function defined in this scope takes precedence over the cmdlet of the same
# name, so dot-sourcing this file shadows Write-Host for every script that is
# dot-sourced into the same scope afterwards. The wrapped cmdlet is called by its
# module-qualified name, which the proxy cannot shadow.
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [object]${Object},
        [object]${Separator},
        [switch]${NoNewline},
        [System.ConsoleColor]${ForegroundColor},
        [System.ConsoleColor]${BackgroundColor}
    )

    if ($script:ConsoleOverlayReady -and $PSBoundParameters.ContainsKey('Object')) {
        # ValueFromRemainingArguments makes PowerShell collect the positional arguments into a
        # List[object], so a single Write-Host "text" call still arrives as a one-item list.
        $value = $PSBoundParameters['Object']
        if ($value -is [string]) {
            $PSBoundParameters['Object'] = ConvertTo-ConsoleOverlayText -Text $value
        }
        elseif ($value -is [System.Collections.IList]) {
            $items = @($value)
            $translated = New-Object object[] $items.Count
            for ($i = 0; $i -lt $items.Count; $i++) {
                $item = $items[$i]
                $translated[$i] = if ($item -is [string]) { ConvertTo-ConsoleOverlayText -Text $item } else { $item }
            }
            $PSBoundParameters['Object'] = $translated
        }
    }

    if (-not $script:ConsoleOverlayCmdlet) {
        $script:ConsoleOverlayCmdlet = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Write-Host', [System.Management.Automation.CommandTypes]::Cmdlet)
    }
    & $script:ConsoleOverlayCmdlet @PSBoundParameters
}

# Warnings reach the user the same way, and Write-Warning only writes to the warning
# stream, so translating it cannot change a function's result. Write-Error is
# deliberately not wrapped: it has five parameter sets, and a proxy that mishandles
# -ErrorRecord would change how terminating errors are raised.
function Write-Warning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]${Message}
    )

    if ($script:ConsoleOverlayReady -and $PSBoundParameters.ContainsKey('Message')) {
        $PSBoundParameters['Message'] = ConvertTo-ConsoleOverlayText -Text $PSBoundParameters['Message']
    }

    if (-not $script:ConsoleOverlayWarningCmdlet) {
        $script:ConsoleOverlayWarningCmdlet = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Write-Warning', [System.Management.Automation.CommandTypes]::Cmdlet)
    }
    & $script:ConsoleOverlayWarningCmdlet @PSBoundParameters
}
