# Defender 移除功能 · 外部参考

> 参考对象：[ionuttbara/windows-defender-remover](https://github.com/ionuttbara/windows-defender-remover)
> 调研时间：2026-10-31。8630 stars，Batchfile，默认分支 `main`。
> **本文是「能抄什么 / 不能抄什么」的判决书，不是它的说明书。**

## 它的架构

```
script/
  Script_Run.cmd / Script_Run.ps1   ← 主流程
  PowerRun.exe (894 KB)            ← 第三方工具，以 TrustedInstaller 身份执行
  Remove_Defender/*.reg            ← 15 个注册表片段，删服务/驱动/策略/CLSID/任务
  Remove_SecurityComp/*.reg        ← 删 Windows 安全中心 App
  files_removal.bat                ← takeown + icacls + rd 删目录
  verify.bat                       ← 独立验证脚本（只读）
  RemoveSecHealthApp.ps1           ← 删 SecHealthUI Appx
```

核心手段：**PowerRun.exe 拿到 TrustedInstaller 令牌 → 导入 .reg 片段 → 批量删键**。
我们用「夺权（SeTakeOwnership）+ Administrators 完全控制」，效果等价，但不引入外部二进制。

## 一、值得补的（纯 Defender 残留，不影响系统其他能力）

### 1. 服务清单比我们全（我们漏了 8 个）

它的 `RemoveServices.reg` 删这些，**加粗的是我们没有的**：

| 服务键 | 说明 | 我们现状 |
|---|---|---|
| `WinDefend` | 杀毒主服务 | 已删 |
| `WdNisSvc` / `WdNisDrv` | 网络检查服务与驱动 | 已删 |
| `WdFilter` | 文件系统过滤驱动 | 已删 |
| `WdBoot` | 早期启动驱动 | 已删 |
| `webthreatdefsvc` / `webthreatdefusersvc` | Web 威胁防护 | 已在清单里 |
| **`MsSecCore`** | Defender 平台核心服务 | 缺 |
| **`MsSecFlt`** | 安全过滤驱动 | 缺 |
| **`MsSecWfp`** | Windows Filtering Platform 组件 | 缺 |
| **`whesvc`** | Windows 健康服务 | 缺 |
| `SecurityHealthService` | 安全中心服务 | 已删 |

我们的 `Get-DefenderServiceNames` 靠 ImagePath 扫描兜底，新名字能自动发现，
但 `MsSecCore` / `MsSecFlt` / `MsSecWfp` 的 ImagePath 指向 `System32\drivers`，路径扫描发现不了，
必须把已知名加进 `$known` 列表。

### 2. COM CLSID 注册（最大缺口）

Defender 注册了 14 个 COM 类，分布在三个位置（这是右键菜单和外壳扩展的来源）：

```
HKLM\Software\Classes\CLSID\{GUID}
HKLM\Software\Classes\WOW6432Node\CLSID\{GUID}
HKCR\CLSID\{GUID} / HKCR\WOW6432Node\CLSID\{GUID}
```

GUID 清单（见 `RemovalofWindowsDefenderAntivirus.reg`）：

```
2781761E-28E0-4109-99FE-B9D127C57AFE   2781761E-28E2-4109-99FE-B9D127C57AFE
195B4D07-3DE2-4744-BBF2-D90121AE785B   361290c0-cb1b-49ae-9f3e-ba1cbe5dab35
45F2C32F-ED16-4C94-8493-D72EF93A051B   6CED0DAA-4CDE-49C9-BA3A-AE163DC3D7AF
8a696d12-576b-422e-9712-01b9dd84b446   8C9C0DB7-2CBA-40F1-AFE0-C55740DD91A0
A2D75874-6750-4931-94C1-C99D3BC9D0C7   A7C452EF-8E9F-42EB-9F2B-245613CA0DC9
DACA056E-216A-4FD1-84A6-C306A017ECEC   E3C9166D-1D39-4D4E-A45D-BC7BE9B00578
F6976CF5-68A8-436C-975A-40BE53616D59
```

注意 HKCR 是 `HKLM\Software\Classes` 的镜像，删一处另一处通常同步消失，但它的 reg 两处都写了——保守起见照做。

### 3. Shell 关联与启动项

```
HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\windowsdefender
HKLM\SOFTWARE\Classes\AppUserModelId\Windows.Defender
HKLM\SOFTWARE\Classes\AppUserModelId\Microsoft.Windows.Defender
HKCR\WindowsDefender / HKLM\SOFTWARE\Classes\WindowsDefender
HKCR\AppX9kvz3rdv8t7twanaezbwfcdgrbg3bck0
HKCU\Software\Classes\ms-cxh
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run → "WindowsDefender" / "Windows Defender"
HKCU 同名两项 + Explorer\StartupApproved\Run
```

### 4. Web 威胁防护的配套注册

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost → "WebThreatDefense" 值
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost\WebThreatDefense 键
HKLM\SOFTWARE\Microsoft\WindowsRuntime\Server\WebThreatDefSvc
HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Microsoft.OneCore.WebThreatDefense.*（4 个）
```

删了服务却留着 svchost 组和 WinRT 类注册，属于半拉子。

### 5. 防火墙规则

```
HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Static\System
    "WindowsDefender-1" / "-2" / "-3"
    "WebThreatDefSvc_Allow_In" / "Allow_Out" / "Block_In" / "Block_Out"
HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\Configurable\System
    "{2A5FE97D-01A4-4A9C-8241-BB3755B65EE0}" 等 3 个 GUID 值
```

### 6. 其他零散项

- **WMI Autologger**：`Control\WMI\Autologger\DefenderAuditLogger`、`DefenderApiLogger`
- **Ubpm 维护任务**：`Control\Ubpm` 下的 `CriticalMaintenance_DefenderCleanup`、`CriticalMaintenance_DefenderVerification`
- **Windows Security Health 注册表**：`HKLM\SOFTWARE\Microsoft\Windows Security Health`，配套 CLSID `{BB64F8A7-BEE7-4E1A-AB8D-7D8273F7FDB6}` + `Explorer\ControlPanel\NameSpace` 同名项
- **签名更新策略**：`Policies\Microsoft\Windows Defender\Signature Updates`（删策略键后自然不存在，可忽略）
- **SpyNet / 遥测**：`Policies\...\Spynet`、`SOFTWARE\Microsoft\RemovalTools\MpGears`

## 二、可选（会波及其他安全功能，要做必须先拍板）

| 项 | 它怎么做 | 后果 |
|---|---|---|
| `wscvc`（Windows 安全中心服务） | 直接删服务键 | 安全中心彻底打不开，所有杀软的注册状态都不再被收集 |
| `SgrmBroker` / `SgrmAgent` | 删服务 | System Guard 运行时监控失效 |
| SecHealthUI Appx | `RemoveSecHealthApp.ps1` | Windows 安全中心 UWP 应用消失 |
| 设置页隐藏 | `SettingsPageVisibility=hide:windowsdefender;` | 设置里不显示「Windows 安全中心」入口 |
| SmartScreen | `Disable SmartScreen.reg` | 下载/运行的网页防护关闭 |

## 三、不要学

| 项 | 原因 |
|---|---|
| **Disable Mitigation.reg** | 关 Spectre/Meltdown 缓解、Services Mitigations。它 README 自己写「老 Intel CPU 性能 +30%」——拿安全性换性能，不属于去全家桶的范畴 |
| **关 UAC 文件虚拟化** | 让所有程序以管理员权限跑，攻击面直接放大 |
| **删 Pluton 服务**（`PlutonHsp2` / `PlutonHeci` / `Hsp`） | 那是硬件安全处理器，不是软件功能 |
| **PowerRun.exe** | 894 KB 未签名第三方二进制，供应链风险；我们的夺权方案已解决同一问题 |
| **写 `PolicyManager\default\Defender\*` 几十个值** | 那是 MDM 默认值，删键比写值干净，写了反而留痕 |
| **直接删 `TaskCache\Tasks\{GUID}`** | `Unregister-ScheduledTask` 更安全，删缓存键容易让任务计划程序状态不一致 |

## 四、它比我们强的地方（可借鉴的做法）

1. **独立的 verify 脚本** —— 只读检查，分 OK / WARN / KO 三段计数，重启后验证。我们的 `Get-DefenderResidue` 已有同样能力，并已暴露成 `-VerifyDefenderRemoval`。
2. **检查项分组**：目录缺失 / 服务键缺失 / 安全中心 App / 计划任务 / 一致性。最后那组「一致性检查」思路好——不只查「没了没」，还查「残留在的状态对不对」。
3. **覆盖面**：CLSID、防火墙规则、Svchost 组、WMI 日志器，这四类当时完全空白。

## 五、我们比它强的地方（别改坏）

- 输入 `REMOVE` 确认 + 独立确认窗口；它只是让你选 1/2/3
- 前置检查：非管理员 / 篡改保护未关 / Defender 不存在 / 第三方杀软未注册
- 有备份：注册表导出 + 系统还原点
- 支持中断后补刀（残留清理模式）
- 逐项报告哪些没删掉，而不是静默失败
- 无外部二进制依赖
- 中英双语

## 六、改这个功能时的建议顺序

1. **先补服务名**（`MsSecCore` / `MsSecFlt` / `MsSecWfp` / `whesvc`）—— 改 `$known` 数组，风险最低
2. **再补注册表键**：Shell 关联、WMI 日志器、Security Health 键、Svchost 组 —— 加进 `$configKeys`
3. **CLSID 单独一段**：14 个 GUID × 2 处位置，循环处理，注意有些 GUID 可能不存在（要跳过而不是报错）
4. **防火墙规则**：删的是**值**不是键，得用 `Remove-ItemProperty`，不能进 `$configKeys`
5. **最后考虑 verify 入口**：把 `Get-DefenderResidue` 扩成全量检查 + 独立报表
6. 每步都要跑 Pester + 真机 `-Silent` 验证，**代码文件保持纯 ASCII**（中文只能进 JSON）

**注意**：这个项目的做法是把整个 Windows 安全体系拆掉，本仓库的定位是「去全家桶」，
第一类（纯 Defender 残留）该抄，第二类（wscsvc / Sgrm / SmartScreen）**必须先获得授权**。

## 七、落地情况（v0.1.3，2026-10-31）

第一类全部实现，本机实测确认了上一版确实漏了这些东西（Defender 主服务已删但残留仍在）。

| 类别 | 实现 |
|---|---|
| 服务 | `$known` 补 `MsSecCore` / `MsSecFlt` / `MsSecWfp`。它们的 ImagePath 指向 `System32\drivers`，路径扫描发现不了 |
| 注册表（整键删） | Windows Security Health、`CLSID\{BB64F8A7-...}`（两个位宽）、ControlPanel NameSpace、WMI Autologger ×2、`Svchost\WebThreatDefense`、`WindowsRuntime\Server\WebThreatDefSvc`、AppUserModelId ×2、`Classes\WindowsDefender`、AppX 类键 |
| COM | 13 个 GUID × 2 处（`HKLM\SOFTWARE\Classes\CLSID` 与 `WOW6432Node\CLSID`）。**HKCR 是镜像视图，不重复写** |
| 动态发现 | `ActivatableClassId\*WebThreatDefense*`、`Control\Ubpm\*Defender*` —— 名字随版本变，按名匹配而不是硬编码 |
| 值级删除 | `Run` / `StartupApproved\Run` 下的 `WindowsDefender` / `Windows Defender` / `SecurityHealth`（HKLM + HKCU），`Svchost` 的 `WebThreatDefense` 值 |
| 防火墙 | 删值不删键：名称匹配 `WindowsDefender*` / `WebThreatDefSvc*`，GUID 值按规则二进制里的内容匹配。**这些键属主是 TrustedInstaller、Administrators 只有读权限**，删失败时先夺权再重试 |
| 验证入口 | `Get-DefenderRemovalReport` → `Show-DefenderRemovalReport` → `-VerifyDefenderRemoval`；分组 OK / WARN / FAIL 计数，有 FAIL 时退出码 1；GUI「残留检查」用同一数据源 |

### 明确不抄的

| 项 | 原因 |
|---|---|
| `whesvc` | 本机 ImagePath 是 `svchost.exe -k whesvc`，是 Windows 健康服务，不属于 Defender，删了影响更新健康检查 |
| `HKCU\Software\Classes\ms-cxh` | 通用 Settings 协议注册，不是 Defender 专属 |
| wscsvc / SgrmBroker / SecHealthUI Appx / SmartScreen / 关缓解 / 关 UAC 虚拟化 | 超出「去全家桶」范围，属于第二类，未获授权 |

### 本机残留实测（2026-10-31，Defender 已移除状态）

`-VerifyDefenderRemoval` 报 90 项：正常 45、残留 26、阻塞 19。阻塞项是 3 个 MsSec 服务 + 16 个注册表键，
残留是 14 个 CLSID 条目、3 个驱动文件、7 条防火墙规则、2 个启动项。**说明 v0.1.2 的覆盖确实不完整**，
v0.1.3 重跑一次就能清掉这些。

> 注：本机至今仍是「已移除但有残留」的状态，`-VerifyDefenderRemoval` 会稳定报 19 阻塞 / 26 残留，
> 这是测试机状态而非代码缺陷。
