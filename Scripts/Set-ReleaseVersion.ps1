<#
    .SYNOPSIS
        Updates the release version shown in the About window.

    .DESCRIPTION
        The script version written by the release workflow is the upstream date (yyyy.MM.dd).
        This repository also ships its own v0.1.x release number so the About window shows which
        build of the Chinese edition is running. Only that single assignment is rewritten; the
        date version stays untouched because Build-Release.ps1 replaces it during packaging.

    .PARAMETER Tag
        Release tag to write, for example v0.1.5.2.

    .PARAMETER SourcePath
        Repository root containing Win11Debloat.ps1. Defaults to the parent of this script's folder.

    .EXAMPLE
        .\Scripts\Set-ReleaseVersion.ps1 -Tag v0.1.5.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+\.\d+(?:\.\d+)?$')]
    [string]$Tag,

    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $SourcePath 'Win11Debloat.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Cannot find Win11Debloat.ps1 under: $SourcePath"
}

$text = [IO.File]::ReadAllText($scriptPath)
$pattern = '(?m)^\$script:ReleaseVersion = "[^"\r\n]*"\r?$'
$versionMatches = [regex]::Matches($text, $pattern)
if ($versionMatches.Count -ne 1) {
    throw "Expected exactly one release version assignment, found $($versionMatches.Count)."
}

$match = $versionMatches[0]
$replacement = '$script:ReleaseVersion = "' + $Tag + '"'
if ($match.Value.TrimEnd() -eq $replacement) {
    Write-Host "ReleaseVersion is already $Tag."
    return
}

# Splice by index so the replacement text is never parsed as a regex substitution pattern.
$updated = $text.Substring(0, $match.Index) + $replacement + $text.Substring($match.Index + $match.Length)
[IO.File]::WriteAllText($scriptPath, $updated, [Text.UTF8Encoding]::new($true))

Write-Host "ReleaseVersion set to $Tag."
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  git add Win11Debloat.ps1'
Write-Host "  git commit -m `"release: $Tag`""
Write-Host "  git tag $Tag"
Write-Host "  git push origin master $Tag"
