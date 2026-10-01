# Shows the CLI default mode app removal options. Loops until a valid option is selected.
function Show-CliDefaultModeAppRemovalOptions {
    Write-CliHeader (Get-ConsoleText 'Default Mode')

    Write-Host (Get-ConsoleText "Please note: The default selection of apps includes Microsoft Teams, Spotify, Sticky Notes and more. Select option 2 to verify and change what apps are removed by the script") -ForegroundColor DarkGray
    Write-Host ""

    Do {
        Write-Host (Get-ConsoleText "Options:") -ForegroundColor Yellow
        Write-Host (Get-ConsoleText " (n) Don't remove any apps") -ForegroundColor Yellow
        Write-Host (Get-ConsoleText " (1) Only remove the default selection of apps") -ForegroundColor Yellow
        Write-Host (Get-ConsoleText " (2) Manually select which apps to remove") -ForegroundColor Yellow
        $RemoveAppsInput = Read-Host (Get-ConsoleText "Do you want to remove any apps? Apps will be removed for all users (n/1/2)")

        # Show app selection form if user entered option 3
        if ($RemoveAppsInput -eq '2') {
            $result = Show-AppSelectionWindow

            if ($result -ne $true) {
                # User cancelled or closed app selection, change RemoveAppsInput so the menu will be shown again
                Write-Host ""
                Write-Host (Get-ConsoleText "Cancelled application selection, please try again") -ForegroundColor Red

                $RemoveAppsInput = 'c'
            }
            
            Write-Host ""
        }
    }
    while ($RemoveAppsInput -ne 'n' -and $RemoveAppsInput -ne '0' -and $RemoveAppsInput -ne '1' -and $RemoveAppsInput -ne '2')

    return $RemoveAppsInput
}