# Win11Debloat (Chinese Localized)

<h3 align="center">

English | <a href="./README.zh-CN.md">简体中文</a>

</h3>

A fully Chinese-localized build of [Win11Debloat](https://github.com/Raphire/Win11Debloat) — a lightweight, easy-to-use PowerShell script that declutters Windows: removes pre-installed apps, disables telemetry, and strips intrusive interface elements. No installation required.

This fork ships a complete zh-CN language pack on top of the upstream project, so the **GUI, command-line menus, and launcher prompts all display in Chinese** when your system language is Chinese. The script logic is untouched apart from the localization layer.

![Win11Debloat Menu](/Assets/Images/menu.png)

## What's Localized

| Part | Content | Entries |
|---|---|---|
| Graphical interface | Main window, app selection, dialogs, tray tips, import/export — 9 forms | 322 strings |
| Features | Name / description / progress / undo text for every feature, plus UI groups | 103 items + 10 groups |
| App list | Chinese names & removal advice for pre-installed apps (incl. HP / Dell / Lenovo OEM) | 141 entries |
| App categories | Category labels in the app-selection window | 12 entries |
| Command-line mode | Menus, options, prompts, error messages | 263 strings |
| Launcher | `Run.bat` and the one-click script follow the system language automatically | — |

Around **850 strings** in total.

## Requirements

- Windows 10 / 11
- **Windows PowerShell 5.1** (built into Windows). PowerShell 7 (pwsh) is not supported — the script detects it and exits.
- **Administrator privileges.** The script requests UAC elevation automatically.

## Usage

> [!Warning]
> Great care went into making sure this script does not unintentionally break any OS functionality, but use at your own risk! Please report issues on the [upstream repository](https://github.com/Raphire/Win11Debloat/issues).

### Method 1: One-click run (recommended)

Open PowerShell or Terminal and paste:

```PowerShell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/Swipa5fox/Win11Debloat-zh/master/Scripts/Get.ps1")))
```

The script downloads the latest version to a temp folder and launches it. Accept the UAC prompt and follow the on-screen instructions.

> If `raw.githubusercontent.com` is unreachable from your network, use method 2.

### Method 2: Manual download

1. [Download this repository as a ZIP](https://github.com/Swipa5fox/Win11Debloat-zh/archive/refs/heads/master.zip) and extract it.
2. Open the extracted `Win11Debloat-zh-master` folder.
3. Double-click **`Run.bat`**, accept the UAC prompt, and follow the instructions.

### Method 3: Run from PowerShell (advanced)

1. Extract the ZIP, then open PowerShell as administrator.
2. Temporarily allow script execution:

   ```PowerShell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```

3. Navigate to the extracted folder and run:

   ```PowerShell
   .\Win11Debloat.ps1
   ```

### Command-line parameters

| Parameter | Effect |
|---|---|
| `-RunDefaults` | Apply the recommended settings without showing the menu |
| `-RunDefaultsLite` | Same, but skips changes that are harder to revert |
| `-RunSavedSettings` | Re-run with the settings saved from your last session |
| `-Silent` | Suppress all prompts and run without user interaction |
| `-RemoveApps` | Remove pre-installed apps |
| `-CreateRestorePoint` | Create a system restore point before making changes |
| `-Language zh-CN` | Force a specific language instead of following the system |
| `-Sysprep` | Apply changes to the Windows Default profile so all new users get them (advanced) |

The default language follows the system display language: Chinese (`zh-*`) systems get Chinese, everything else falls back to English. Language files live in `Config/Languages/<code>/` — edit the JSON files to tweak any wording.

## Differences from Upstream

Besides the language packs, only small adaptations were made. No feature logic was changed:

| Change | Details |
|---|---|
| Added `Config/Languages/zh-CN/` | Five Chinese language files (Chrome / Features / Categories / Apps / Console) |
| Added `Config/Languages/en-US/Console.json` | English baseline for console strings, used as fallback |
| `Get-ConsoleText` localizer | Maps console & log output from the English source string, falls back to English when a key is missing |
| One-click script downloads this fork | `Scripts/Get.ps1` pulls this repo (with language packs) by default; `-Dev` fetches the upstream English dev build |
| `Run.bat` bilingual launcher | Detects `LocaleName` and shows Chinese prompts on Chinese systems |
| Auto UAC elevation | Requests elevation directly instead of asking `y/n` first |
| Test language pinned to en-US | Pester assertions match English source strings; normal runs are unaffected |

## Syncing Upstream Updates

```PowerShell
git remote add upstream https://github.com/Raphire/Win11Debloat.git
git fetch upstream
git merge upstream/master
```

After merging, add translations for any new strings to the JSON files under `Config/Languages/zh-CN/`. Missing keys silently fall back to English.

## Reverting Changes

Almost all changes made by the script can be reverted, and removed apps can be reinstalled from the Microsoft Store.

## License & Acknowledgements

- All core functionality belongs to the upstream author: [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat). The Chinese language packs and small adaptations were made in this repository.
- Licensed under the [MIT license](./LICENSE), same as upstream. If you like the script, consider starring the upstream project.
