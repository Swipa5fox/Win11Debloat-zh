<#
    .SYNOPSIS
        Saves active feature settings, excluding control parameters, unless running in WhatIf mode.
#>
function Save-Settings {
    if ($script:Params.ContainsKey("WhatIf")) {
        Write-Host (Get-ConsoleText "[WhatIf] Save settings to LastUsedSettings.json") -ForegroundColor Cyan
        return
    }

    $settings = @{
        "Version" = "1.0"
        "Settings" = @()
    }
    
    # Irreversible actions are never replayed from a saved preset: the user selects them again and
    # confirms explicitly, so "run saved settings" cannot silently retry a destructive removal.
    $excludedSettings = @('RemoveWindowsDefender')

    foreach ($param in $script:Params.Keys) {
        if ($script:ControlParams -notcontains $param -and $excludedSettings -notcontains $param -and $script:Features.ContainsKey($param)) {
            $value = $script:Params[$param]

            $settings.Settings += @{
                "Name" = $param
                "Value" = $value
            }
        }
    }

    if (-not (Save-ToFile -Config $settings -FilePath $script:SavedSettingsFilePath)) {
        Write-Output ""
        Write-Host (Get-ConsoleText "Error: Failed to save settings to LastUsedSettings.json file") -ForegroundColor Red
    }
}
