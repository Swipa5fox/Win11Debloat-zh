# Builds a self-contained Get-ConsoleText for a background runspace, which does not inherit the
# parent scope's dot-sourced functions. Only Console.json is read, and only for scriptblocks that
# actually report through Get-ConsoleText, so runspaces that don't never pay for it.
function Get-ConsoleLocalizerPreamble {
    $languagesPath = $script:LanguagesPath
    if (-not $languagesPath) {
        $languagesPath = Join-Path (Join-Path $PSScriptRoot '..\..\Config') 'Languages'
    }

    $languageCode = if ($script:Lang) { $script:Lang.LanguageCode } else { [System.Globalization.CultureInfo]::CurrentUICulture.Name }
    $safePath = $languagesPath.Replace("'", "''")
    $safeCode = $languageCode.Replace("'", "''")

    return @"
`$script:__ConsoleTextLanguage = '$safeCode'
`$script:__ConsoleTextLanguagesPath = '$safePath'
function Get-ConsoleText {
    param(
        [Parameter(Mandatory, Position = 0)][string]`$Text,
        [object[]]`$FormatArgs = `$null
    )

    if (-not `$script:__ConsoleTextMap) {
        `$script:__ConsoleTextMap = @{}
        `$candidates = @(`$script:__ConsoleTextLanguage, 'en-US') | Select-Object -Unique
        foreach (`$code in `$candidates) {
            `$path = Join-Path (Join-Path `$script:__ConsoleTextLanguagesPath `$code) 'Console.json'
            if (-not (Test-Path -LiteralPath `$path)) { continue }
            `$json = Get-Content -LiteralPath `$path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach (`$prop in `$json.PSObject.Properties) { `$script:__ConsoleTextMap[`$prop.Name] = [string]`$prop.Value }
            break
        }
    }

    `$resolved = if (`$script:__ConsoleTextMap.ContainsKey(`$Text)) { `$script:__ConsoleTextMap[`$Text] } else { `$Text }
    if (`$null -ne `$FormatArgs -and `$FormatArgs.Count -gt 0) {
        try { return `$resolved -f `$FormatArgs } catch { return `$resolved }
    }
    return `$resolved
}
"@
}

# Runs a scriptblock in a background PowerShell runspace while keeping the UI responsive.
# In GUI mode, the work executes on a separate thread and the UI thread pumps messages (~60fps).
# In CLI mode, the scriptblock runs directly in the current session.
function Invoke-NonBlocking {
    param(
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 0
    )

    # CLI mode without timeout: run directly in-process
    if (-not $script:GuiWindow -and $TimeoutSeconds -eq 0) {
        return (& $ScriptBlock @ArgumentList)
    }

    $ps = [powershell]::Create()
    try {
        $scriptText = $ScriptBlock.ToString()

        if ($scriptText -match '\bGet-ConsoleText\b') {
            $preamble = Get-ConsoleLocalizerPreamble

            # param() has to remain the first statement, so the injected helper goes after it.
            $paramMatch = [regex]::Match($scriptText, '^\s*param\s*\((?:[^()]|\([^()]*\))*\)\s*')
            if ($paramMatch.Success) {
                $scriptText = $paramMatch.Value + "`n" + $preamble + "`n" + $scriptText.Substring($paramMatch.Length)
            }
            else {
                $scriptText = $preamble + "`n" + $scriptText
            }
        }

        $null = $ps.AddScript($scriptText)
        foreach ($arg in $ArgumentList) {
            $null = $ps.AddArgument($arg)
        }

        $handle = $ps.BeginInvoke()

        if ($script:GuiWindow) {
            # GUI mode: pump UI messages while waiting
            $stopwatch = if ($TimeoutSeconds -gt 0) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }

            while (-not $handle.IsCompleted) {
                if ($stopwatch -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    $ps.Stop()
                    throw "Operation timed out after $TimeoutSeconds seconds"
                }
                Invoke-DoEvents
                Start-Sleep -Milliseconds 16
            }
        }
        else {
            # CLI mode with timeout: block until completion or timeout
            if (-not $handle.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
                $ps.Stop()
                throw "Operation timed out after $TimeoutSeconds seconds"
            }
        }

        $result = $ps.EndInvoke($handle)

        # Surface non-terminating errors raised inside the runspace so GUI-mode operations
        # (e.g. failed app removals) don't fail silently - the runspace keeps its own error
        # stream that is otherwise discarded on Dispose.
        if ($ps.HadErrors) {
            foreach ($runspaceError in $ps.Streams.Error) {
                Write-Error -ErrorRecord $runspaceError
            }
        }

        if ($result.Count -eq 0) { return $null }
        if ($result.Count -eq 1) { return $result[0] }
        return @($result)
    }
    finally {
        $ps.Dispose()
    }
}
