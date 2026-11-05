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

# A test file dot-sources the one script under test and nothing else, but those scripts report through
# Get-ConsoleText. Stand in for the language loader with the same passthrough it uses when no
# Console.json applies: the English source string comes back unchanged, which is what the assertions
# expect. Files that care define their own replacement inside their own scope.
function global:Get-ConsoleText {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [object[]]$FormatArgs = $null
    )

    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        try { return ($Text -f $FormatArgs) } catch { return $Text }
    }

    return $Text
}

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 })) {
    if (-not $Bootstrap) {
        Write-Error 'Pester 5 is required. Install it with: .\Scripts\Run-Tests.ps1 -Bootstrap'
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
        Write-Error "Unable to install Pester 5: $($_.Exception.Message)"
        exit 1
    }

    if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -eq 5 })) {
        Write-Error 'Pester 5 was not installed. Update PowerShellGet or install Pester 5 manually, then run the tests again.'
        exit 1
    }
}

Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999.999 -Force
$result = Invoke-Pester -Path $testPath -Output Detailed -PassThru

if ($result.Result -ne 'Passed' -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0) {
    exit 1
}
