# Win11Debloat 中文版

[Win11Debloat](https://github.com/Raphire/Win11Debloat) 的**完整中文汉化版**。一个轻量、易用的 PowerShell 脚本，无需安装即可清理 Windows 预装应用、关闭遥测、移除烦人的界面元素。本仓库在上游基础上把图形界面、**命令行输出与日志**、启动提示全部译成中文，并额外提供**彻底移除 Microsoft Defender** 的能力。

> 本版基于上游 **2026.10.30** 版本整合。上游自 2026.10 起已自带简体中文界面语言包，本仓库在此之上补齐了命令行与日志的中文化，并保留了 Defender 模块。

<img src="/Assets/Images/home.png" alt="Win11Debloat 首页" width="100%">

## 界面预览

#### 应用移除
<img src="/Assets/Images/apps.png" alt="Win11Debloat 应用移除" width="100%">

162 个预装应用（含 HP / Dell / Lenovo 等 OEM 应用）全部配好中文名称与说明，按「推荐 / 可选 / 不推荐」三档标注移除风险，支持搜索、排序与快速预设。

#### 系统优化
<img src="/Assets/Images/tweaks.png" alt="Win11Debloat 系统优化" width="100%">

12 个分类共 96 项优化，名称、说明、悬停提示全部中文化，鼠标悬停即看详细解释。另有 9 项功能不归入任何分类、不在这个列表里展示（强制卸载 Edge、替换开始菜单布局、彻底移除 Defender 等）。

#### 部署设置
<img src="/Assets/Images/deploy.png" alt="Win11Debloat 部署设置" width="100%">

指定更改应用到哪个用户，可选创建注册表备份与系统还原点，应用前可先预览全部变更。

## 汉化范围

| 部分 | 内容 | 数量 |
|---|---|---|
| 图形界面 | 主窗口（含 Windows Defender 模块页）、应用选择、应用进度、导入导出、还原备份、消息框、关于、气泡提示、Defender 移除确认、设置共 10 个窗体 | 385 条界面文案 |
| 功能项 | 每个功能的名称 / 说明 / 执行中 / 撤销 / 撤销中文案，外加 UI 分组 | 105 项 + 10 分组 |
| 应用列表 | 预装应用的显示名称与移除说明（含 HP / Dell / Lenovo 等 OEM 应用） | 162 条 |
| 优化项分类 | 系统优化页 12 个分类的标题 | 12 条 |
| 命令行与日志 | 菜单、选项、确认提示、错误提示、Defender 残留检查 | 351 条 |
| 启动器 | `Run.bat` 与一键下载脚本按系统语言自动切换 | — |

合计约 **1000 条**文案，全部中文化。

## 系统要求

- Windows 10 / 11
- **Windows PowerShell 5.1**（系统自带）。不支持 PowerShell 7（pwsh）——应用移除与还原点依赖的模块在 pwsh 下不可用，脚本会直接提示退出。
- 需要**管理员权限**。脚本会自动弹 UAC 请求提权，无需手动操作（UAC 弹窗是系统安全机制，无法跳过）。

## 使用方法

### 方法一：一键运行（推荐）

打开 PowerShell 或终端，粘贴以下命令：

```PowerShell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/Swipa5fox/Win11Debloat-zh/master/Scripts/Get.ps1")))
```

脚本会自动下载到临时目录并启动，接受 UAC 提示即可。

> 此方式拉取的是本仓库最新 Release 的 `Win11Debloat.zip`，并用同批发布的 `SHA256SUMS` 校验；想拿开发中的代码，改用方法二下载后 `git pull`。
>
> 若 `raw.githubusercontent.com` 无法访问（国内网络常见），改用方法二。

### 方法二：手动下载

1. 到 [Releases](https://github.com/Swipa5fox/Win11Debloat-zh/releases/latest) 下载最新版的 `Win11Debloat-zh-v*.zip`，解压到任意目录。
2. 进入解压后的文件夹。
3. 双击 **`Run.bat`** 启动，接受 UAC 提示。
4. 按屏幕提示操作。

### 方法三：命令行直接运行（进阶）

1. 同上，从 [Releases](https://github.com/Swipa5fox/Win11Debloat-zh/releases/latest) 下载 ZIP 包并解压。
2. 以管理员身份打开 PowerShell，临时放行脚本执行：

   ```PowerShell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```

3. 切换到解压目录并运行：

   ```PowerShell
   .\Win11Debloat.ps1
   ```

支持命令行参数自定义行为。常用参数：

| 参数 | 作用 |
|---|---|
| `-RunDefaults` | 不显示菜单，直接套用推荐设置 |
| `-RunDefaultsLite` | 同上，但跳过较难还原的更改 |
| `-RunSavedSettings` | 按上次会话保存的设置重新执行 |
| `-CLI` | 进入命令行模式，不启动图形界面 |
| `-Silent` | 静默执行，全程无交互（需配合具体功能参数） |
| `-RemoveApps` | 移除预装应用；不指定 `-Apps` 时使用默认列表 |
| `-Apps <列表>` | 自定义要移除的应用 ID，逗号分隔 |
| `-CreateRestorePoint` | 更改前先创建系统还原点 |
| `-Language zh-CN` | 强制指定语言，不跟随系统 |
| `-Sysprep` | 把更改写入 Windows 默认配置文件，新用户自动生效（进阶） |
| `-RemoveWindowsDefender` | **彻底移除** Microsoft Defender（不可撤销，见下节） |
| `-AcceptDefenderRemovalRisk` | 无人值守（`-Silent`）时确认移除 Defender 的风险 |
| `-VerifyDefenderRemoval` | 只读检查 Defender 是否还有残留，不改动任何东西 |

每一项优化都有对应的开关（如 `-DisableChromeAI`、`-DisableDriverUpdates`），完整列表用 `.\Win11Debloat.ps1 -?` 查看，或直接看 `Config/Features.json` 的 `Features` 段。

完整的 100 多个开关（每项优化都有对应参数）见 `Win11Debloat.ps1` 顶部的 `param` 块，一般用不到手动指定——界面里勾选即可。

## 彻底移除 Microsoft Defender（危险操作）

图形界面里有一个独立的「Windows Defender」页，命令行是 `-RemoveWindowsDefender`。**它删组件，不是关开关**：服务注册（`WinDefend`、`WdNisSvc`、`Sense`、`SecurityHealthService`，以及新版才有的 `MsSecCore` / `MsSecFlt` / `MsSecWfp` 平台驱动）、文件系统过滤与早期启动驱动（`WdFilter`、`WdNisDrv`、`WdBoot`）、策略与配置键、Shell/COM/WinRT 注册、`WebThreatDefense` 主机组、开机启动项、防火墙规则、计划任务、程序目录一并删除。

### 界面里的 Defender 模块

主窗口从「系统优化」往后翻一页就是，分三块：

| 区块 | 作用 |
|---|---|
| **当前状态** | 显示「已安装 / 仅剩残留 / 未安装」，以及篡改保护是否开启、有没有第三方杀毒软件。残留会给出具体条目数 |
| **彻底移除** | 勾选后随「应用更改」一起执行；执行前仍会弹出确认窗口，要求输入 `REMOVE` |
| **残留检查** | 只读检查，按服务、注册表、启动项、COM、驱动、目录、计划任务、防火墙、一致性分组列出还没清掉的东西，红色是阻塞项、黄色是残留项 |

没有任何 Defender 组件时，「彻底移除」会自动置灰，避免点了也跑不动。

### 执行前必须知道

| 项 | 说明 |
|---|---|
| **不可撤销** | 本工具没有反向操作。恢复只能靠就地升级（保留文件和程序的 Windows 安装）或全新安装 |
| **功能更新会装回来** | Windows 大版本更新会重新安装 Defender，届时需要再执行一次 |
| **篡改保护必须先关** | 微软会拦截对 Defender 的注册表/服务改动。请在「Windows 安全中心 → 病毒和威胁防护 → 管理设置」里关掉篡改保护，脚本无法代劳 |
| **没装第三方杀软等于裸奔** | 脚本会检测 Windows 安全中心注册的杀毒产品；一个都没有时会强警告，并仍要求输入确认词 |
| **需要重启** | 删除驱动和目录的收尾工作要重启后才干净 |

### 确认机制

- 图形界面：弹出专门窗口列清后果，**必须手动输入 `REMOVE`** 才能继续，点错会把输入框标红
- 命令行：同样要求输入 `REMOVE`，直接回车即跳过
- 静默模式（`-Silent`）：不会弹任何提示，**必须同时传 `-AcceptDefenderRemovalRisk`**，否则这个功能会被跳过而不是悄悄执行

### 脚本会先做的保护措施

1. 把 `WinDefend` / `WdFilter` / `WdNisDrv` / `WdBoot` 服务键与 Defender 配置/策略键导出到 `Backups\DefenderRemoval-<时间戳>\*.reg`
2. 尝试创建系统还原点（不保证成功，失败只警告不中止）
3. 按「停服务 → 删计划任务 → 删服务注册 → 删驱动文件 → 删配置与外壳注册 → 删开机启动项 → 删防火墙规则 → 删目录」的顺序执行，避免留下指向已删文件的开机驱动
4. 逐项报告没删掉的条目。Defender 的配置键和 `SecurityHealthService` 服务键的属主是 TrustedInstaller，**SYSTEM 权限也删不掉**，脚本会先把属主改成 Administrators、授予完全控制再删；这之后仍失败的才走 SYSTEM 权限的一次性计划任务重试

### 移除后自查

重启后可以跑一次只读检查，它不会改动任何东西：

```PowerShell
.\Win11Debloat.ps1 -VerifyDefenderRemoval
```

输出按「服务与驱动注册 / 注册表项 / 开机启动项 / COM 组件注册 / 驱动文件 / 程序目录 / 计划任务 / 防火墙规则 / 一致性检查」分组，末尾给出「正常 / 警告 / 失败」计数；有阻塞项时退出码为 1，方便写进自动化脚本。图形界面里的「残留检查」块是同一个数据源。

### 删到一半中断了怎么办

再跑一次就行。脚本会判断「主服务是否还在」和「还有没有残留」两件事：

- 主服务已不在但仍有残留：进入**残留清理模式**，只处理剩下的条目，不会因为「Defender 不存在」而拒绝
- 已经完全干净：明确报告「系统中不存在 Microsoft Defender 杀毒组件」并跳过，不会空转

服务管理器可能在重启前一直显示一个 `StartType` 为空的 `SecurityHealthService` 残影，那是内存缓存，不是没删干净。

### 命令行示例

```PowerShell
.\Win11Debloat.ps1 -RemoveWindowsDefender
# 无人值守（机器重装脚本里用），跳过交互：
.\Win11Debloat.ps1 -RemoveWindowsDefender -Silent -AcceptDefenderRemovalRisk
```

想先看它到底会删什么、不实际执行：

```PowerShell
.\Win11Debloat.ps1 -RemoveWindowsDefender -WhatIf
```

> 命令行模式下脚本跑完会停在「按任意键退出」，这是一层防窗口闪退的保护。写进自动化脚本时记得加 `-Silent`，否则会一直等你按键。

> 这一项是上游没有的，属于本仓库新增功能。上游只做「优化项」，不碰 Defender 的卸载；微软也不支持客户端系统卸载 Defender，所以出问题别指望官方支持。

## 语言与主题

- **默认自动跟随系统**：系统界面语言为中文（`zh-*`）时自动加载中文，其他语言回退英文。
- **主窗口可随时切换**：右上角「设置」里改主题（自动 / 浅色 / 深色）与语言，改完立即生效，选择会记在 `%LOCALAPPDATA%\Win11Debloat\Preferences.json`。
- **强制指定语言**：加 `-Language` 参数，例如 `.\Win11Debloat.ps1 -Language zh-CN`，优先级高于已保存的偏好。
- 界面支持上游提供的 13 套语言包（德 / 英 / 西 / 法 / 意 / 日 / 韩 / 荷 / 葡 / 俄 / 土 / 繁中 / 简中）。
- **命令行与日志的中文化只有中文和英文两套**：其余语言下控制台会回退英文原文，界面仍是当地语言。
- `Run.bat` 读注册表的 `LocaleName` 判断中文区域，PowerShell 内部用的是系统界面语言（`CurrentUICulture`）。绝大多数机器两者一致；若你把界面语言和区域格式设成不同（如英文界面 + 中文区域），两处提示可能语言不同，属正常现象。
- 语言文件位于 `Config/Languages/<语言代码>/`，想改措辞直接编辑对应 JSON 即可，无需动脚本。新增语言时缺键会自动回退英文，不会报错。

## 与上游的差异

上游自 2026.10 起已自带简体中文界面语言包，本仓库的增量集中在「界面之外」和「上游不做的功能」：

| 改动 | 说明 |
|---|---|
| 命令行与日志中文包 | 上游的 `Console.json` 机制没有任何数据文件，控制台与日志全是英文。本仓库补了 `zh-CN/Console.json`（351 条）与 `en-US/Console.json` 基线，按「英文原文 → 译文」映射，缺译回退原文 |
| 界面措辞校订 | 在上游中文语言包基础上补了 Defender 与设置窗口相关键，并按中文表达习惯重写了约 160 条直译文案；界面文案合计 385 条 |
| 新增「彻底移除 Microsoft Defender」 | 上游没有的功能：删除 Defender 的服务注册（含 MsSec* 平台驱动）、过滤与早期启动驱动、策略与配置键、Shell/COM/WinRT 注册、WebThreatDefense 主机组、开机启动项、防火墙规则、任务与目录，不可撤销。入口是主窗口独立的「Windows Defender」页与 `-RemoveWindowsDefender`，带 `REMOVE` 输入确认；另有只读的 `-VerifyDefenderRemoval` 自查入口 |
| 非管理员自动提权 | 不再询问 `y/n`，直接请求 UAC（上游需手动确认） |
| 一键脚本下载本仓库发布版 | `Scripts/Get.ps1` 默认取本仓库最新 Release 的 `Win11Debloat.zip`，并用同批发布的 `SHA256SUMS` 校验；`-Dev` 仍指向上游开发分支 |
| `Run.bat` 中英文分流 | 按 `LocaleName` 判断，中文系统显示中文提示 |
| 反馈入口指向本仓库 | `Run.bat` 的 issue 提示、主窗口「反馈问题」菜单、应用失败时的上报按钮，均指向本仓库 issues（上游 Wiki 链接保留，因为说明文档仍在上游） |
| 彻底移除不写入预设 | `LastUsedSettings.json` 会排除 Defender 移除，「使用上次设置」不会重放这个不可逆操作 |

## 同步上游更新

上游与本仓库没有共同祖先（历史已重写），所以不要 `git merge`，按「以上游为新基线、重放本地增量」的方式同步：

```PowerShell
git remote add upstream https://github.com/Raphire/Win11Debloat.git
git fetch upstream --no-tags
git checkout -b sync/upstream-<日期> upstream/master
```

`--no-tags` 是必要的：本仓库只保留自己的版本标签（`v0.1.x`），加上它上游那几十个日期标签才不会被顺手拉进来。

分支建好后按三类处理：

1. **本仓库独有的文件**直接取回：`git checkout master -- Scripts/Features/Remove-WindowsDefender.ps1` 等 Defender 相关文件、`Config/Languages/*/Console.json`、`Assets/Images/*.png`
2. **两边都改过的文件**逐个重放：`git diff <旧基线> master -- <文件> | git apply -3`，冲突处手工合
3. **语言包**以上游为准，只把 `Console.json` 与 Defender 相关键补回去；补完跑一次覆盖检查，确认没有漏译的键

改完跑 `.\Scripts\Run-Tests.ps1`，全绿再提交。

## 常见问题

**双击 `Win11Debloat.ps1` 打开的是记事本？**<br>
Windows 默认把 `.ps1` 关联到编辑器。请双击 `Run.bat`，或用方法三从 PowerShell 运行。

**界面或控制台出现乱码吗？**<br>
语言文件必须是无 BOM 的 UTF-8。用记事本改过 JSON 后如果出现乱码，请改用 VS Code 等编辑器以「UTF-8（无 BOM）」重新保存。

**想还原脚本做的修改？**<br>
几乎所有改动都可还原，预装应用也能从 Microsoft Store 重装。参考[上游 Wiki 的还原说明](https://github.com/Raphire/Win11Debloat/wiki/Reverting-Changes)。

**脚本能用在 PowerShell 7 吗？**<br>
不能。脚本会检测并提示退出，请用系统自带的 Windows PowerShell 5.1。

## 致敬上游

全部功能代码来自 [@Raphire](https://github.com/Raphire) 的 [Win11Debloat](https://github.com/Raphire/Win11Debloat)，以及该项目[所有贡献者](https://github.com/Raphire/Win11Debloat/graphs/contributors)多年累积的成果。这个仓库只做了一件事：把界面、命令行和提示文字翻成中文，让不习惯英文的人也能用得顺手。没有上游那几百个提交打底，这里一个字也写不出来。

如果这个脚本帮你省了事，请把 Star 给[上游仓库](https://github.com/Raphire/Win11Debloat) —— 真正干活的是他们。

本项目中文化与少量适配遵循 [MIT 许可证](./LICENSE)，与上游一致。
