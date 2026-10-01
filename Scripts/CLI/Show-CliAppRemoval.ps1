# Shows the CLI app removal menu and prompts the user to select which apps to remove.
function Show-CliAppRemoval {
    Write-CliHeader (Get-ConsoleText "App Removal")

    Write-Output (Get-ConsoleText "> Opening app selection form...")

    $result = Show-AppSelectionWindow

    if ($result -eq $true) {
        Write-Output (Get-ConsoleText "You have selected {0} apps for removal" -FormatArgs @($($script:SelectedApps.Count)))
        Add-Parameter 'RemoveApps'
        Add-Parameter 'Apps' ($script:SelectedApps -join ',')

        Save-Settings

        # Suppress prompt if Silent parameter was passed
        if (-not $Silent) {
            Write-Output ""
            Write-Output ""
            Write-Output (Get-ConsoleText "Press enter to remove the selected apps or press CTRL+C to quit...")
            Read-Host | Out-Null
            Write-CliHeader (Get-ConsoleText "App Removal")
        }
    }
    else {
        Write-Host (Get-ConsoleText "Selection was cancelled, no apps have been removed") -ForegroundColor Red
        Write-Output ""
    }
}