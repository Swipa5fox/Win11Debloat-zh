<#
    .SYNOPSIS
        Imports a JSON file, optionally validates its version, and returns $null on failure.
#>
function Import-JsonFile {
    param (
        [string]$filePath,
        [string]$expectedVersion = $null,
        [switch]$optionalFile
    )
    
    if (-not (Test-Path $filePath)) {
        if (-not $optionalFile) {
            Write-Error (Get-ConsoleText "File not found: {0}" -FormatArgs @($filePath))
        }
        return $null
    }
    
    try {
        $jsonContent = Get-Content -Path $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # Validate version if specified
        if ($expectedVersion -and $jsonContent.Version -and $jsonContent.Version -ne $expectedVersion) {
            Write-Error (Get-ConsoleText "{0} version mismatch (expected {1}, found {2})" -FormatArgs @($(Split-Path $filePath -Leaf), $expectedVersion, $($jsonContent.Version)))
            return $null
        }
        
        return $jsonContent
    }
    catch {
        Write-Error (Get-ConsoleText "Failed to parse JSON file: {0}" -FormatArgs @($filePath))
        return $null
    }
}
