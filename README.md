# Win11Debloat 中文版

[Win11Debloat](https://github.com/Raphire/Win11Debloat) 的**完整中文汉化版**。一个轻量、易用的 PowerShell 脚本，无需安装即可清理 Windows 预装应用、关闭遥测、移除烦人的界面元素。本仓库在上游基础上补全了整套中文语言包，让图形界面、命令行和启动提示**全部显示中文**。

<img src="/Assets/Images/home.png" alt="Win11Debloat 首页" width="100%">

## 界面预览

#### 应用移除
<img src="/Assets/Images/apps.png" alt="Win11Debloat 应用移除" width="100%">

141 个预装应用（含 HP / Dell / Lenovo 等 OEM 应用）全部配好中文说明，按「推荐 / 可选 / 不推荐」三档标注移除风险，支持搜索、排序与快速预设。

#### 系统优化
<img src="/Assets/Images/tweaks.png" alt="Win11Debloat 系统优化" width="100%">

103 项优化分 12 个分类展示，每个功能的名称、说明、悬停提示均中文化，鼠标悬停即看详细解释。

#### 部署设置
<img src="/Assets/Images/deploy.png" alt="Win11Debloat 部署设置" width="100%">

指定更改应用到哪个用户，可选创建注册表备份与系统还原点，应用前可先预览全部变更。

## 汉化范围

| 部分 | 内容 | 数量 |
|---|---|---|
| 图形界面 | 主窗口、应用选择、各类弹窗、气泡提示、导入导出等 9 个窗体 | 322 条界面文案 |
| 功能项 | 每个功能的名称 / 说明 / 执行中 / 撤销 / 撤销中文案，外加 UI 分组 | 103 项 + 10 分组 |
| 应用列表 | 预装应用的移除建议说明（含 HP / Dell / Lenovo 等 OEM 应用） | 141 条 |
| 应用分类 | 应用选择窗口左侧的分类标签 | 12 条 |
| 命令行模式 | 菜单、选项、确认提示、错误提示 | 263 条 |
| 启动器 | `Run.bat` 与一键下载脚本按系统语言自动切换 | — |

合计约 **850 条**文案，全部中文化。

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

脚本会自动下载最新版到临时目录并启动，接受 UAC 提示即可。

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
| `-Silent` | 静默执行，全程无交互 |
| `-RemoveApps` | 移除预装应用 |
| `-CreateRestorePoint` | 更改前先创建系统还原点 |
| `-Language zh-CN` | 强制指定语言，不跟随系统 |
| `-Sysprep` | 把更改写入 Windows 默认配置文件，新用户自动生效（进阶） |

## 语言设置

- **默认自动跟随系统**：系统显示语言为中文（`zh-*`）时自动加载中文，其他语言回退英文。
- **强制指定语言**：加 `-Language` 参数，例如 `.\Win11Debloat.ps1 -Language zh-CN`。
- `Run.bat` 按注册表中的系统区域设置判断，与 PowerShell 内部逻辑一致。
- 语言文件位于 `Config/Languages/<语言代码>/`，想改措辞直接编辑对应 JSON 即可，无需动脚本。

## 与上游的差异

除新增语言包外，仅做了少量必要的适配，功能逻辑未改动：

| 改动 | 说明 |
|---|---|
| 新增 `Config/Languages/zh-CN/` | 五个中文语言文件（Chrome / Features / Categories / Apps / Console） |
| 新增 `Config/Languages/en-US/Console.json` | 控制台文案的英文基线，供其他语言回退 |
| `Get-ConsoleText` 本地化函数 | 按「英文原文 → 中文」映射控制台与日志输出，缺译时回退英文原文 |
| 一键脚本默认源指向本仓库 | `Scripts/Get.ps1` 默认下载本仓库（带语言包）；**`-Dev` 改为拉取上游英文开发版** |
| `Run.bat` 中英文分流 | 按 `LocaleName` 判断，中文系统显示中文提示 |
| 非管理员自动提权 | 不再询问 `y/n`，直接请求 UAC（上游需手动确认） |
| `Run-Tests.ps1` 固定测试语言 | Pester 断言依赖英文原文，测试时固定 en-US，不影响正常运行 |
| 反馈入口指向本仓库 | `Run.bat` 的 issue 提示、主窗口「反馈问题」菜单、应用失败时的上报按钮，均指向本仓库 issues（上游 Wiki 链接保留，因为说明文档仍在上游） |

## 同步上游更新

```PowerShell
git remote add upstream https://github.com/Raphire/Win11Debloat.git
git fetch upstream
git merge upstream/master
```

合并后若有新增文案，往 `Config/Languages/zh-CN/` 对应 JSON 里补翻译即可；缺失的键会自动回退英文，不会报错。

> 合并时若提示 `Assets/Images/menu.png` 冲突（删除 / 修改冲突），保留本仓库的中文示意图即可，直接 `git checkout --ours Assets/Images/menu.png` 后删除该文件并 `git add`。

## 常见问题

**双击 `Win11Debloat.ps1` 打开的是记事本？**<br>
Windows 默认把 `.ps1` 关联到编辑器。请双击 `Run.bat`，或用方法三从 PowerShell 运行。

**界面或控制台出现乱码吗？**<br>
语言文件必须是无 BOM 的 UTF-8。用记事本改过 JSON 后如果出现乱码，请改用 VS Code 等编辑器以「UTF-8（无 BOM）」重新保存。

**想还原脚本做的修改？**<br>
几乎所有改动都可还原，预装应用也能从 Microsoft Store 重装。参考[上游 Wiki 的还原说明](https://github.com/Raphire/Win11Debloat/wiki/Reverting-Changes)。

**脚本能用在 PowerShell 7 吗？**<br>
不能。脚本会检测并提示退出，请用系统自带的 Windows PowerShell 5.1。

## 致谢与许可

- 上游项目：[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) —— 全部核心功能归上游作者所有，中文语言包与少量适配由本仓库完成。
- 本项目遵循 [MIT 许可证](./LICENSE)，与上游一致。喜欢这个脚本的话，欢迎给[上游仓库](https://github.com/Raphire/Win11Debloat)点个 Star。
