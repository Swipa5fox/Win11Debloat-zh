<#
    .SYNOPSIS
        Runs the Win11Debloat Pester test suite locally.

    .PARAMETER Bootstrap
        Installs a compatible Pester 5 release for the current user when Pester is
        not already available.
#>
[CmdletBinding()]
param(
    [switch]$Bootstrap
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repositoryRoot 'Tests'

# Test files dot-source the one script under test and nothing else, but those scripts report through
# Get-ConsoleText, so the localizer has to exist before Pester takes over.
$script:LanguagesPath = Join-Path $repositoryRoot 'Config\Languages'
. (Join-Path $PSScriptRoot 'FileIO\Import-JsonFile.ps1')
. (Join-Path $PSScriptRoot 'FileIO\Import-LanguageFile.ps1')

foreach ($consoleFunction in 'Get-ConsoleFallbackLanguage', 'Get-ConsoleText', 'Get-LanguageFallbackChain', 'Resolve-LanguageFolder') {
    Set-Item -Path "function:global:$consoleFunction" -Value (Get-Item -Path "function:$consoleFunction").ScriptBlock
}

# Those functions now run from the global scope with no active language, so they would resolve
# Console.json against the machine's UI culture and hand the assertions translated text. Pin English
# through the supported hook instead, which keeps every call resolving to the source string.
$global:LanguagesPath = $script:LanguagesPath
$global:Win11DebloatConsoleLanguage = 'en-US'

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 })) {
    if (-not $Bootstrap) {
        Write-Error (Get-ConsoleText 'Pester 5 is required. Install it with: .\Scripts\Run-Tests.ps1 -Bootstrap')
        exit 1
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false | Out-Null
        }

        Install-Module -Name Pester -RequiredVersion 5.9.0 -Scope CurrentUser -Force -AllowClobber -Confirm:$false
    }
    catch {
        Write-Error (Get-ConsoleText "Unable to install Pester 5: {0}" -FormatArgs @($($_.Exception.Message)))
        exit 1
    }

    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 })) {
        Write-Error (Get-ConsoleText 'Pester 5 was not installed. Update PowerShellGet or install Pester 5 manually, then run the tests again.')
        exit 1
    }
}

Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999.999 -Force
$result = Invoke-Pester -Path $testPath -Output Detailed -PassThru

if ($result.Result -ne 'Passed' -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0) {
    exit 1
}
