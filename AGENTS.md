# AGENTS.md · Win11Debloat 中文增强版

> 面向在本仓库工作的编码代理与贡献者。
> 验收在独立窗口按另一套规范执行，见文末「验收与交接」。

---

## 1. 项目定位

上游 [`Raphire/Win11Debloat`](https://github.com/Raphire/Win11Debloat) 的中文增强分支。在上游基础上只做两件事：

1. **彻底移除 Microsoft Defender** —— 上游从不做的功能，不可逆
2. **全链路中文** —— 界面之外，控制台与日志也有中文（`Config/Languages/*/Console.json`，351 条）

定位是「中文增强版」不是「汉化版」：README、仓库简介、topics 都按上面两件事讲，界面校订只占一小段。启动性能（4.7s → 3.7s）是附带结果，不作卖点，数据见 §9。

本地汉化规模：Chrome 386 / Features 105 / Apps 162 / Categories 12 / Console 351 = 1016 条。

**仓库里有两份文件是外部贡献者加的，不要删**：`.github/SECURITY.md`、`.github/dependabot.yml`（2026-11-04 由贡献者提交）。

README 顶部用**三行对比表**（界面语言 / 控制台与日志 / 移除 Defender）说明「比官方中文版多什么」；「启动性能」**不作为卖点**，只在正文留事实——剩下约 3 秒是「纯脚本 + WPF」的固定成本，用户无感知。

---

## 2. 当前状态

| 项 | 值 |
|---|---|
| 发布版本 | `$script:ReleaseVersion = "v0.1.5.2"` |
| 上游日期版本 | `$script:Version = "2026.10.31"` |
| 上游基线 commit | `5d88bfe`（2026.10.30 Release） |
| 测试基线 | **1049 passed / 0 failed**，约 90–120 秒 |
| 相对上游差异 | 73 文件 / +5558 / −1517 |
| 历史 | 605 提交，与上游**有共同祖先**，可直接 merge / rebase |

数字会变。**以实跑为准**：`.\Scripts\Run-Tests.ps1`、`git diff --stat 5d88bfe HEAD`。

---

## 3. 目录地图

```
Win11Debloat.ps1          入口：参数 → 语言 → 提权 → GUI/CLI 分流 → Invoke-AllChanges
Scripts/
  Get.ps1                 一键启动器（独立分发，内联了 Get-ConsoleText）
  Run-Tests.ps1 / Build-Release.ps1 / Set-ReleaseVersion.ps1
  AppRemoval/             应用移除（含强制卸载 Edge）
  CLI/                    控制台菜单与输出
  Features/               Invoke-Changes（总执行器）、注册表应用/备份/还原
  Defender/               Windows-Defender.ps1：Defender 移除 + 确认对话框 + 主窗口页面（自包含，37 个函数）
  FileIO/                 JSON / 语言 / 设置读写，Console-Overlay（控制台翻译层）
  GUI/                    MainWindow-* 分页、各弹窗
  Helpers/                注册表路径、用户目录、构建判定等
  Threading/              Invoke-NonBlocking、Invoke-DoEvents
Config/
  Features.json           12 分类 + 105 个功能项
  Apps.json               162 个预装应用
  Languages/<locale>/     Chrome / Apps / Categories / Features / Console
Regfiles/                 246 个 .reg（含 Undo/ 64 个、Sysprep/ 90 个）
Schemas/                  11 个 XAML
Tests/                    53 个测试文件
Docs/                     设计参考文档
```

---

## 4. 硬规则（违反必挂 CI）

| 规则 | 原因 |
|---|---|
| 含中文的 `.ps1` 必须 **UTF-8 with BOM** | CI 是英文 Windows，1252 解码会破坏引号配对 |
| `Run.bat` 必须存 **GBK** | cmd 按 OEM 码页解析批处理 |
| 语言 JSON 必须 **UTF-8 无 BOM** | 有 BOM 会出现乱码字 |
| JSON 读取必须 `-Encoding UTF8` | 否则中文乱码 |
| 新增 GUI 脚本 → 加进 `Tests/XamlContracts.Tests.ps1` 的 `$receiverSchemas` | 否则 FindName 契约测试挂；扫描范围是 `Scripts/GUI` + `Scripts/Defender` |
| 新增开关 → 同步加进 `Scripts/Get.ps1` | 否则 `FeatureParameterContracts` 挂 |
| 语言包复数键 `_one` / `_other` 必须成对 | 中文两者填同一文本，`{0}`/`{1}` 与英文一一对应 |
| 版本号只改一行：`.\Scripts\Set-ReleaseVersion.ps1 -Tag v0.1.x` | 它保留 BOM、不碰 `$script:Version`；版本按微版本走 |
| 代码文件保持纯 ASCII，中文只进 JSON | Defender 相关脚本尤其如此 |
| 每次改完顺手核对文档里的数字 | 过时数字比没有更害人 |

---

## 5. 同步上游

本仓库与上游**有共同祖先**（2026-11-21 重建），直接三路合并：

```powershell
git fetch upstream --no-tags
git merge upstream/master      # 或 rebase
# 解冲突 → .\Scripts\Run-Tests.ps1 → push
```

**不要压平历史**。`backup/pre-rebase` 是旧孤立历史的兜底，那条腿上的同步才需要用「文件哈希找交集 + `git apply -3`」的老流程。README 的「同步上游更新」一节也已按 merge 流程改写。

同步后必须检查：

1. `grep 'function Get-ConsoleText'` 只应出现在 `Scripts/Get.ps1`、`Scripts/Run-Tests.ps1`
2. `Assets/Images/` 会被上游整目录覆盖 → 重拍预览图
3. `Scripts/FileIO/Console-Overlay.ps1` 仍在（它承载整个控制台汉化）

---

## 6. 已知坑（全部踩过）

**语言与控制台**
- `Import-LanguageFile.ps1` 整份换成上游版会丢掉 `Get-ConsoleText`，症状是横幅/提权/参数校验全 `CommandNotFoundException`，而 GUI 与后续日志正常，极易漏看
- 后台 runspace 不继承父作用域函数/`$script:` 变量 → `Invoke-NonBlocking` 检测到 `Get-ConsoleText` 会注入自包含 preamble
- 函数提到 global 后 `$script:Lang` 解析不到 → 用显式 `$global:` 钩子
- `Console.json` 不在 `Get-LanguageCatalogNames`（那里只有 Chrome / Features / Categories / Apps）→ 漏译不会被常规测试发现，由 `Tests/ConsoleCatalog.Tests.ps1` 单独守键集 / 占位符 / 空值 / 未译句
- 代理层：`ValueFromRemainingArguments` 让 `Write-Host` 的 `$Object` 是 `List[object]` 而非 string，判断要写 `-is [System.Collections.IList]`
- PS 5.1 的 `-f` **不展开** `New-Object object[]` 创建的数组（`@()` 与函数 `[object[]]` 参数可以），重组参数用 `[string]::Format`

**测试**
- **CI Windows runner 自带 Defender**：查 `Get-Service WinDefend` / `Get-Process MsMpEng` 的测试本地过、CI 挂 → 必须 Mock 成 `$null`
- Pester 5.9 + PS 5.1 的 `-ParameterFilter` 拿不到绑定参数：`Should -Invoke X -ParameterFilter { $Path -eq '...' }` 与 mock body 里的 `$Path` 都是 `$null`，断言静默失败。改为断言调用次数 + 用 `$script:` 变量标记是否进入 mock
- 空目录用管道喂 `Remove-Item` 会参数绑定失败（`missing path operand`）→ 改 `| ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }`
- git 原生命令写 stderr，在 `$ErrorActionPreference='Stop'` 下会抛 `NativeCommandError`：`git describe --tags --abbrev=0` 在无 tag 时 `2>$null` 挡不住，测试的 skip 分支永远走不到。要在子作用域 `& { $ErrorActionPreference='SilentlyContinue'; ... }` 里调用，用 `$LASTEXITCODE` 判断是否 skip
- `Tests/XamlContracts.Tests.ps1` 只扫代码里写死的目录（`Scripts/GUI`，2026-11-21 起加 `Scripts/Defender`）：把 GUI 代码移出这两个目录，FindName 契约会**静默失效**，必须同步加扫描路径
- `$receiverSchemas` 是哈希表：`Window` 与 `window` 是同一个键，写两个会直接解析失败（`哈希文本中不允许包含重复的键`）
- `-VerifyDefenderRemoval` 的退出码只能在 `-File` 直跑时取：用 `*>&1 | Out-File` 包一层再读 `$LASTEXITCODE` 得到的是 0，别拿它判验收

**构建与脚本**
- PowerShell 里 `Remove-Item -Recurse` 会被 safe-delete 钩子拦成 fail-closed（`SAFE_DELETE_FAIL_CLOSED ... trash-failed`），且报错后同一 `-Command` 的后续语句仍会执行，极易判错因果。构建前用 bash `rm -rf` + `mkdir` 备空目录；`Build-Release.ps1` 见同名文件就 `throw`，重跑必须换目录
- `git push | tail; echo $?` 取的是 tail 的退出码（假成功）→ 用 `> log 2>&1` 单独记

**网络**
- `github.com` 直连可能不通，`api.github.com` 通常可直连
- git 代理是 **URL 级** `http.https://github.com/.proxy`，`-c http.proxy=` 覆盖不掉，要 `-c "http.https://github.com/.proxy="`
- push 卡死 = wincred 挂起 → `git -c credential.helper= push "https://x-access-token:<token>@github.com/..."`（token 不入库）
- 本机代理常年 `127.0.0.1:7890`，偶发 `Failed to connect over proxy` 是选点抖动，重试即可

---

## 7. Defender 移除模块

详情与外部参考见 [`Docs/Defender-Removal-Reference.md`](./Docs/Defender-Removal-Reference.md)。要点：

- **代码全在一个文件**：`Scripts/Defender/Windows-Defender.ps1`（37 个函数，2026-11-21 由 `Features/Remove-WindowsDefender.ps1` + `GUI/Confirm-DefenderRemoval.ps1` + `GUI/MainWindow-Defender.ps1` 合并）。上游文件只剩调用点：`Show-MainWindow` 5 行、`MainWindow-Deployment` 1 行、`Invoke-Changes` 两个 switch case；同步上游时这几处是唯一可能冲突的地方
- 入口：主窗口「Windows Defender」页 + `-RemoveWindowsDefender`；无人值守需 `-AcceptDefenderRemovalRisk`；只读自查 `-VerifyDefenderRemoval`（**免管理员免 UAC**）
- 执行顺序：导出注册表 → 还原点 → 停服务 → 删任务 → 删服务键 → 删驱动 → 删配置/外壳/COM/WinRT 键 → 启动项 → 防火墙规则 → 目录
- **服务清单必须扫 ImagePath 指向 Defender 目录**，别只硬编码（新版有 `MpDefenderCoreService` 锁着 `MpClient.dll`）
- COM 13 个 GUID × 2 处（`HKLM\Software\Classes\CLSID` + `WOW6432Node`）；**HKCR 是镜像，别重复删**
- **TrustedInstaller 保护项只能夺权删，SYSTEM 计划任务没用**：启用 `SeTakeOwnership`/`SeRestore` → 改属主 → 授完全控制 → 删（0.1 秒）；改 ACL 的 handle 只有 ChangePermissions，枚举子键要重开
- 防火墙键属主 TrustedInstaller 且装着别人的规则 → **只能删值不能删键**，按名称 + 规则二进制内容匹配
- `whesvc` 是 Windows 健康服务，**不是** Defender，别删
- 彻底移除**不写入** `LastUsedSettings.json`（避免重放不可逆操作）
- 残留判定以**服务注册表键**为准（删键后 `Get-Service` 会留空 StartType 残影）
- CLI 务必加 `-Silent`：不加时 `Wait-ForKeyPress` 会死等按键

---

## 8. GUI 架构

- 标签顺序：0 首页 → 1 应用 → 2 优化 → 3 Defender → 4 部署。标签头 Collapsed，用户靠「上一步/下一步」翻页 → **新页必须插在部署页之前**
- 禁止硬编码 `$tabControl.SelectedIndex = 3`，用 `Select-DeploymentTab` 按 `x:Name` 选；`Update-NavigationButtons` 第 3 个点判 `-ge (totalTabs-1)`
- Defender 复选框不走 `UiControlMappings` → 全部由 `Scripts/Defender/Windows-Defender.ps1` 的 hook 处理：`Add-DefenderModuleToParams` 加参数、`Test-DefenderModuleSelected` 给 New-Overview 补行、`Reset-DefenderModuleSelection` 取消勾选；页面初始化是 `Initialize-DefenderModule`，首次翻到该页才扫状态（`Update-DefenderModuleOnPageEnter`）
- XAML 本地化值经 `ConvertTo-LocalizedXaml` 用 `SecurityElement.Escape` 转义，`&`/`<` 不用手写实体

---

## 9. 性能基线

首帧 4.7s → **3.7s**，应用列表 4.8s → **4.2s**（v0.1.5.1 实测，Build 26300）。

已处理：`Get-DefenderResidue` 延迟到首次打开该页（约 5s）、`Get-MpComputerStatus` 加存在性守卫（无 Defender 时 CIM 重试约 6s）、`Set-CurrentTweakStateInUi` 挪到首帧后（520ms）、语言资源一次建表（450ms）。

压不动的固定成本：`XamlReader.Load` ≈990ms（不是本地化，`ConvertTo-LocalizedXaml` 只占 60ms）、86 个脚本 dot-source ≈1.0s。`New-DynamicTweakControls`（403ms）**故意保留同步**——控件必须存在，大量路径 FindName。

已验证无效/负优化：窗口显示前预加载应用数据（+0.75s，已回退）、调大批次 / 减少 Dispatcher 泵送（非瓶颈）。

---

## 10. 发布流程

```
.\Scripts\Run-Tests.ps1 全绿
→ .\Scripts\Set-ReleaseVersion.ps1 -Tag v0.1.x
→ commit → 推 master
→ git tag -a v0.1.x -m "v0.1.x：<一句话>" → 推 tag
→ Scripts/Build-Release.ps1 -Version <上游日期> -OutputDirectory <全新空目录> -SourcePath <repo>
→ 建 Release → 上传 Win11Debloat.zip + SHA256SUMS + Get.ps1
→ 验证
```

- PS 5.1 下 `Build-Release.ps1` **必须显式传 `-SourcePath`**，否则 `$PSScriptRoot` 为空
- `-Version` 只接受 `yyyy.MM.dd`（填上游日期）；我们的 `v0.1.x` 只体现在 tag / Release 标题
- 资产名必须是 `Win11Debloat.zip` + `SHA256SUMS`，否则一键脚本走「无校验」分支
- **Release 标题就是 Feed 条目标题**（`releases.atom` 的 `<title>`），格式固定 `v0.1.x — <一句人话>`
- Release 必须非 draft、非 prerelease 才进 latest / atom；`Get.ps1` 读的是 `releases/latest`
- 正文中文，按「测试 / 新增 / 修复 / 文档 / 验证」分块，末尾给测试数字
- 收尾验三样：`releases/latest` 的 tag、`releases.atom` 首条标题、下载 zip 的 sha256 与 `SHA256SUMS` 一致

---

## 11. 预览图（同步上游后必做，离屏渲染而非截图）

1. 复制 `Win11Debloat.ps1` 到仓库根（`$PSScriptRoot` 必须等于根）：提权守卫改 `if ($false)`、注释掉 `Start-Transcript`、在 `$script:UndoParams = @{}` 之后截断
2. 接渲染段：`Add-Type WindowsBase,PresentationCore,PresentationFramework` → `DispatcherTimer` 500ms 等 `IsLoaded` 且 `AppSelectionPanel.Children.Count -ge 3` → 逐页 `SelectedIndex` + `UpdateLayout()` + `RenderTargetBitmap` → 缩 1.5x / dpi144 得 2100×1350
3. `powershell -NoProfile -STA -File <脚本> -Language zh-CN`（**必须 STA**）；拍完删脚本
4. Defender 页**不放 README**（本机只剩残留，易被误读成没删干净）

---

## 12. 验收与交接

验收**不在本仓库做**，由独立窗口按五层清单执行（前置检查 / 静态一致性 / 全量测试 / 免 UAC 实机 / 覆盖率与差异量化）。交付时请给验收方这四项：

```
【交付】<主题>
改动：<文件列表 + 一句话说清改了什么>
预期行为：<用户能观察到的变化>
自测：<跑过什么、结果如何>
需人工验证：<哪些必须 UAC 或肉眼确认>
```

需要 UAC 的路径（GUI、`-RunDefaults`、Defender 实际移除）验收方跑不了，会列为「未验证项」——交付时请主动说明这些项你自己做过什么验证。
