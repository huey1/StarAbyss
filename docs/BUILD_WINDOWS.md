# Windows 构建与验收

目标产物：Windows x86_64 绿色包（zip），解压后双击 `StarAbyss.exe` 即可运行。引擎 Godot **4.7.2 stable**、Forward+ / Vulkan、release 导出模板；包内不含 Godot 编辑器、Blender 或测试代码。

发布版本号取自 `godot/project.godot` 的 `application/config/version`（当前 `1.0.0`）。

## 1. 构建前提（缺一条就不要指望构建成功）

### 1.1 引擎与版本硬校验

```text
D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe   # 抓 stdout/日志，构建使用它
D:\game\apps\godot\Godot_v4.7.2-stable_win64.exe           # 图形模式手动启动用
--version → 4.7.2.stable.official.ed1daf0bf
```

`tools/build_windows.py` 把 **`4.7.2.stable.official.ed1daf0bf`** 作为硬编码前置条件：编辑器版本不等于该串，或导出模板 `--version` 不等于该串，脚本立即非零退出并打印双方版本。不允许用"接近的版本"构建发布包——模板与编辑器版本不一致时，Godot 要么拒绝导出，要么打出错位的二进制。

### 1.2 导出模板

| 项目 | 值 |
| --- | --- |
| 安装目录 | `D:\game\StarAbyss\.local\export_templates\4.7.2.stable\`（**工程内**，被 `.gitignore` 忽略） |
| 必需文件 | `windows_release_x86_64.exe` **和** `windows_debug_x86_64.exe` |
| 预设配置 | `custom_template/release="res://../.local/export_templates/4.7.2.stable/windows_release_x86_64.exe"`，`custom_template/debug` 同理 |
| 官方压缩包 | `Godot_v4.7.2-stable_export_templates.tpz`，1,281,349,702 字节 |

**为什么模板必须放在工程内，而不是标准的 `%APPDATA%\Godot\export_templates\`**：

这台机器上**引擎进程只能写 `D:\game` 工作区内的路径**（第 1.5 节有对照实验）。标准模板目录在真实的 `C:\Users\<user>\AppData\Roaming\Godot\` 下，引擎既写不进去、也不能作为可依赖的方案。因此：

- 模板解压到工程内 `.local/export_templates/4.7.2.stable/`；
- `export_presets.cfg` 用**显式** `custom_template` 指向该路径，不依赖 APPDATA 是否被重定向；
- 这也是原文件里 `res://../.local/export_templates/...` 写法的由来（上一轮会话在这台机器上踩过同一个坑），只是当时版本号写成了不存在的 `4.7.stable`。**置空 `custom_template`（走标准目录）在普通机器上成立，在本验证环境不成立。**

**为什么两个模板都要**：即使只跑 `--export-release`，Godot 4.7.2 也会同时校验该预设的 debug 与 release 模板。只装 release 会得到：

```text
ERROR: Cannot export project with preset "Windows Desktop" due to configuration errors:
<...>/windows_debug_x86_64.exe
<...>/windows_release_x86_64.exe
```

**安装命令（可复现，脚本不联网）**：

```powershell
py tools\build_windows.py --install-templates "D:\game\downloads\Godot_v4.7.2-stable_export_templates.tpz"
```

该命令先 `zipfile.testzip()` 校验整个包完整，再从 `templates/` 抽出 Windows x64 的 release/debug 两个模板到工程内，打印各自大小与 sha256，并强制校验模板 `--version == 4.7.2.stable.official.ed1daf0bf`。模板包本身由 `D:\game\download.py`（断点续传，`py` 启动器）从官方发布资产下载；`build_windows.py` 从不下载任何东西（符合 AGENTS.md：不自动下载引擎/插件/资产）。

### 1.3 Python 与 PowerShell

- 本机**没有 `python` 命令**，用 py 启动器：`C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`。
- 本机**只有 Windows PowerShell 5.1，没有 PowerShell 7**，因此 `tools/build_windows.ps1`（`#Requires -Version 7.0` + `ProcessStartInfo.ArgumentList`）**在这台机器上无法执行**。构建入口改为 `tools/build_windows.py`，与 `tools/verify.py` 同样用 `py` 运行。`.ps1` 保留作历史记录，不作为构建入口。

### 1.4 并发独占（否则会得到随机崩坏）

同一个工程的 `.godot` 导入缓存**不能被并发访问**：多个 Godot 进程同时导入/导出会以 `3221225477`（`0xC0000005` 访问冲突）崩溃，或者产出缺失/半导入资源的包。

```powershell
Get-Process Godot*,StarAbyss* -ErrorAction SilentlyContinue   # 必须先为空
```

`tools/build_windows.py` 在开始前用 `tasklist` 检查，发现其它引擎进程就**拒绝构建**并列出 PID；`--wait-for-exclusive SECONDS` 可让它轮询等待窗口。测试/性能/截图等其它引擎任务请在此期间让路。

### 1.5 环境变量：APPDATA 必须是真实的，缓存与临时目录必须重定向

这台机器上**引擎进程只能写 `D:\game`（工作区）之内**的路径；写工作区外返回 `FileAccess` error 12。对照实验见 `.local/export-diagnostics/probe_write_scope.gd` 与 `probe_read_scope.gd`：写 `D:\game\...` 成功，写 `D:\`、`C:\Users\...\AppData\...`、`%TEMP%` 全部失败；**读**工作区外正常。

于是构建必须区分处理：

| 变量 | 构建时取值 | 理由 |
| --- | --- | --- |
| `APPDATA` | `D:\game\StarAbyss\.local\appdata` | 引擎用户数据目录；模板走显式 `custom_template` 路径，所以不再依赖它 |
| `LOCALAPPDATA` | `D:\game\StarAbyss\.local\localappdata` | 编辑器文档缓存；不重定向会恒产生 3 条 `Could not create editor cache directory` 假 ERROR |
| `TEMP` / `TMP` | `D:\game\StarAbyss\.local\temp` | 见下方"静默废包"缺陷 |

四个变量由 `tools/build_windows.py` 的 `ENGINE_ENV_OVERRIDES` 强制注入每个引擎阶段，并在构建开头打印实际取值。

> **构建不变量（加粗记住）：构建过程不得需要写工作区 `D:\game` 之外的任何路径。**
> 这是本验证环境的硬约束，也是这套构建脚本能跑通的根本原因。任何"顺手往 `%APPDATA%`、`%TEMP%`、`C:\` 写点东西"的改动都会让构建在这里失败。

> **静默废包缺陷（2026-10-23 实测，务必保留 TEMP 重定向）**
> 导出器把 `project.binary` 先序列化到 `%TEMP%/tmpproject.binary` 再加进 PCK。当 TEMP 写不进去时：
> - 导出**退出码仍是 0**，PCK 照样生成（3,156,204 字节），
> - 但包内 `project.binary` 是 **0 字节**，包**无法启动**（审计会报 `Corrupted header in binary project.binary (not ECFG)`、主场景设置为空），
> - 日志里只有 6 行 `ERROR: Couldn't save project.binary at '.../Temp/tmpproject.binary'` / `Can't open file from path` / `Cannot remove non-existent file or directory`。
>
> 所以：**退出码 0 不代表包可用**。构建用两道门禁把静默失败变成构建失败（见第 3 节）：`assert_pck_is_launchable()`（解析索引，必须存在非空 `project.binary`）+ `pack_audit.gd`（75 项内容审计）。

与 `tools/verify.py` 的区别：测试运行器为了隔离同样把 `APPDATA`/`LOCALAPPDATA` 重定向进 `.local/`，但它不导出，因此不需要模板。

## 2. 构建

项目根目录（`D:\game\StarAbyss`）：

```powershell
py tools\build_windows.py                  # 完整：导出 → 包内夹具 → release 启动 → 清单 → SHA256 → ZIP
py tools\build_windows.py --clean          # 先删本流水线的旧产物（只删自己那几个文件名，不递归删目录）
py tools\build_windows.py --pack-only      # 只导出 PCK（诊断；不需要导出模板）
py tools\build_windows.py --skip-smoke     # 跳过夹具与启动检查（产物标记为未验证）
py tools\build_windows.py --no-zip         # 不打包 zip
py tools\build_windows.py --out D:\tmp\b   # 换输出根目录
py tools\build_windows.py --godot <path>   # 指定同版本引擎
```

失败即非零退出并打印 `FAIL: <阶段> ...` 摘要（含引擎输出尾部）。阶段：`editor-version` → `export` → `pack-audit` → `engine-notices` → `pck-functional-smoke` → `release-normal-start`。

### 输出

发布包名带**项目自己的版本号**（`application/config/version`，当前 `1.0.0`，脚本读取、不硬编码）：

```text
builds/windows/star_abyss_windows_x64/
  StarAbyss.exe
  StarAbyss.pck
  试玩说明.txt
  GODOT_LICENSE.txt
  THIRD_PARTY_NOTICES.json
  BUILD_INFO.json
  SHA256SUMS.txt
builds/windows/star_abyss_1.0.0_windows_x64.zip
builds/windows/star_abyss_1.0.0_windows_x64.zip.sha256
```

`BUILD_INFO.json` 记录版本号、引擎版本、模板路径与 sha256、exe/pck 的字节数与 sha256、`pack_audit_checks`，以及四个**互相独立**的验证标志：`pck_functional_smoke_verified`（来自 `EXPORT SMOKE RESULT` 夹具）、`release_normal_start_verified`（来自 release-normal-start 阶段成功且命中 `Forward+`）、`release_native_input_verified`、`human_playtest_verified`。前两者来源不同、不可互相推定；没有实际执行的检查保持 `false`。

`export_presets.cfg` 以 release 模式编译资源，`exclude_filter="tests/*,*.md,*.blend,*.blend1,*.blend2"`；PCK 独立不嵌入 EXE（`binary_format/embed_pck=false`），解压后必须保持同名 PCK 与 EXE 相邻。包未做代码签名，构建不读取证书或密码。引擎与第三方许可由本机 Godot 的 `Engine.get_license_text()` / `get_copyright_info()` 生成，不手写。

## 3. 包验收（两层门禁 + 两层运行验证）

### 3.1 构建内的两道门禁（都过才算包可用）

1. **索引门禁（快，不启动引擎）** `assert_pck_is_launchable()`：解析 PCK 自己的文件索引，要求 `project.binary` **存在且非 0 字节**。这是对第 1.5 节静默废包缺陷的直接拦截。
2. **内容门禁（冒烟引擎）** `tools/pack_audit.gd`，以 `--headless --main-pack <pck>` 运行，要求输出 `PACK AUDIT RESULT: <N> checks, 0 failures` 且退出码 0。它断言：27 个音频 cue 存在且可解码、7 个场景、7 个 GLB、4 项"开发测试未泄漏"、`application/run/main_scene` 未被破坏。

> **维护提醒**：`pack_audit.gd` 里的 `EXPECTED_AUDIO` / `EXPECTED_SCENES` / `EXPECTED_MODELS` 是**硬编码清单**，同时充当"发布资产清单"。art 增删音频或更换模型时必须同步修改该脚本，否则门禁会误红（新资产未登记）或漏检（清单没跟上）。

### 3.2 运行验证（两层，不能互相替代）

官方 4.7 release 模板以 `disable_path_overrides=yes` 编译：拒绝 `--main-pack`、不支持外部 `--script`。所以分两层：

1. **包内数据功能夹具**：用**同版本编辑器的游戏运行模式**（不加 `--editor`、不加源码 `--path`），从输出目录以 `--main-pack` 加载最终 PCK，外加外部 `godot/tests/export_smoke_test.gd`。检查包内无测试源码、真实点击开始、资源/骨骼/武器加载、移动与技能输入、Esc 暂停、重开、返回菜单，并保存图形帧。它验证的是**最终 PCK 的数据**，运行的二进制仍是编辑器构建。
   成功标志：`EXPORT SMOKE RESULT: <N> checks, 0 failures`。
2. **真实 release 二进制普通启动**：从输出目录直接启动 `StarAbyss.exe`（自动加载相邻同名 PCK），不注入外部脚本，`--quit-after 120`，检查退出码 0、日志无 SCRIPT ERROR，且启动输出含 `Vulkan ... Forward+`（脚本会把渲染器行打印出来；缺失即构建失败）。

真实 EXE 的原生键鼠输入与人工试玩**不能**从上面的脚本检查推定，需另有实际记录，见 `docs/TESTING.md`。

对已产出的 PCK 单独跑夹具（QA 用）：

```powershell
py tools\verify.py --packed "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck" --only export-smoke
```

也可以手工等价执行：

```powershell
& 'D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe' --main-pack 'builds\windows\star_abyss_windows_x64\StarAbyss.pck' --fixed-fps 60 --max-fps 0 --disable-vsync --audio-driver Dummy --script 'godot\tests\export_smoke_test.gd'
```

`tools/inspect_pck.py` 可离线核对包内容（不需要启动引擎）：

```powershell
py tools\inspect_pck.py builds\windows\star_abyss_windows_x64\StarAbyss.pck project.binary main_menu.tscn
```

它解析 PCK 自己的索引（Godot 4.7 为 `pack_version=4`、`flags=2` 相对路径、索引位于文件末尾、头部偏移 32 处是 directory offset），输出文件数、payload、指定文件是否在包内及大小。注意导出后场景是二进制：包内是 `main_menu.scn` 加 `main_menu.tscn.remap`，**没有** `main_menu.tscn` 实体文件，加载路径仍写作 `.tscn`。

## 4. 日志、错误过滤与无害行

各阶段输出落在 `.local/export-diagnostics/`：`<stage>.output.txt`（stdout+stderr）与 `<stage>.log`（引擎 `--log-file`）。任一阶段出现 `SCRIPT ERROR:` / `SHADER ERROR:` / `ERROR:` / `FAIL:` / `WARNING:` 即失败——**`WARNING:` 也计失败是刻意的**：警告通常是资源或脚本的真实问题。如果某天引擎打出确实无害的警告，处理方式是像环境噪声那样**精确加白名单并写进本文档**，而不是把 `WARNING:` 整体放过。

只有下列环境噪声被显式豁免（每条都是"引擎写不了自己的用户目录"或"读不到系统证书库"，与游戏、与导出产物无关）：

```text
Failed to read the root certificate store
Error saving editor settings to
Cannot save file '...AppData...editor_settings...'
Cannot create file '...AppData...editor_doc_cache...'
Cannot save editor help cache
Cannot create editor (data|config|cache) directory
Could not create directory: '...AppData...'
Could not open 'user://' directory
Could not create directory: 'user://...'
Failed to open log file for writing: user://...
Can't save resource to empty path
```

豁免是**窄正则**，只可能匹配编辑器用户目录噪声；不会掩盖 `export`、`savepack`、资源缺失或脚本错误。

## 5. 中间 PCK 的地位（不要说成发布证据）

`--pack-only` 产出的 PCK **仅用于提前发现打包缺陷**（缺资源、`project.binary` 为空、测试源码混入包内等），**不作为发布证据**：它不带 EXE、不含最终音频/VFX 内容，也不能证明 release 模板行为。发布必须来自第 2 节的完整构建。

## 6. 历史记录（已被本文档取代）

上一阶段（另一台机器、引擎 `4.7.stable.official.5b4e0cb0f`）曾用 `E:\share\Godot_v4.7` 与工程内 `.local/export_templates/4.7.stable/` 完成过预检导出，模板 sha256 `c42eb5d1...`，模板包 sha256 `9714459d...`。那些路径与本机无关，**版本号也不匹配当前 4.7.2 引擎**，仅作历史记录保留；当前构建一律按第 1 节执行。

## 7. 实测记录

见本文档末节"2026-10-23 实测"（构建完成后追加）。
