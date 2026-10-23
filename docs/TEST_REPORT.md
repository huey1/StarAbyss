# Star Abyss 测试报告（P7）

- **报告状态**：初版 — 仅完成 headless 全量基线（T2 / task-6）。图形全量（T8 / task-7）与补充用例**尚未执行**，第 6 节列明原因。
- **执行时间**：2026-10-23 12:44（Asia/Shanghai）
- **执行者**：qa-verifier（独立验证者；本报告所有结论均来自真实执行，未用"只读代码"代替执行）
- **结论摘要**：headless 套件 **10/12 通过，392 项断言读数，5 项断言失败，总耗时 13.4s**。两个红项（`import`、`export-smoke`）**均不是游戏玩法缺陷**，是**验证基建（`tools/verify.py`）的配置问题**；但它们在当前配置下**每次都会让全量门禁变红**，必须由 T1 负责人修复后才能作为上线证据。

---

## 1. 环境事实（本次实测）

| 项目 | 值 | 证据来源 |
| --- | --- | --- |
| 引擎（headless/抓日志） | `D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe` | 启动横幅 `Godot Engine v4.7.2.stable.official.ed1daf0bf` |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf` | 每个检查的 `.output.txt` 首行 |
| 工程路径 | `D:\game\StarAbyss\godot` | `verify.py` 打印 `Project: D:\game\StarAbyss\godot` |
| Python | `C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`（无 `python` 命令） | 本次全部命令使用 `py.exe` |
| PowerShell | 仅 Windows PowerShell 5.1，**无 pwsh 7** → `tools/verify.ps1` 不可用 | 本机事实；本次全程使用 `tools/verify.py` |
| APPDATA 重定向 | 由 `verify.py` 指向 `.local/appdata` | `verify.py` 第 165 行 |
| **LOCALAPPDATA 重定向** | **未重定向 → 导致 DEF-01（见 5.1）** | 见 5.1 复现证据 |
| 资源引用 | **171** 处 `res://` 全部可解析 | `PASS: 171 resource references resolve` |
| GPU / Vulkan | Lead 报告为 `NVIDIA GeForce RTX 3050 / Vulkan 1.4.325 / Forward+` | **我尚未独立复核**（需开窗口，见第 6 节；T8 阶段将亲自记录该行） |

> 注：`README.md` 与 `docs/TESTING.md` 中"GTX 1660 SUPER"与本机实测硬件不符（Lead 12:45 消息，RTX 3050）。此项属文档陈旧，不影响测试结论，归属 T10/T11 文档修正。

---

## 2. 执行命令（可直接复现）

```powershell
cd D:\game\StarAbyss
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py `
    --headless-only --json .local/validation/baseline_headless.json
```

- 进程退出码：**1**（因 2 个检查 FAIL）
- 实际执行检查数：**12**（`--headless-only` 过滤掉 9 项图形检查）
- 原始证据（全部已落盘，可逐条核对）：

| 文件 | 内容 |
| --- | --- |
| `.local/validation/baseline_headless.json` | 机器可读汇总（断言数/失败数/退出码/耗时/错误行） |
| `.local/validation/baseline_headless.stdout.txt` | 本次运行的完整控制台输出 |
| `.local/validation/<check>.log` | 每个检查的引擎日志（`--log-file`） |
| `.local/validation/<check>.output.txt` | 每个检查的 stdout+stderr |

---

## 3. headless 全量结果（逐项，实测）

| # | 检查 | 命令要点 | 退出码 | 断言数 | 失败数 | 耗时 | 结果 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | import | `--headless --editor --import` | 0 | – | – | 5.7s | **FAIL（DEF-01，环境）** |
| 2 | main-headless | `--headless --fixed-fps 60 --script res://tests/main_scene_smoke_test.gd` | 0 | –（冒烟，无 RESULT 行） | 0 | 0.5s | PASS |
| 3 | combat-rules | `--headless --script res://tests/combat_rules_test.gd` | 0 | 28 | 0 | 0.2s | PASS |
| 4 | enemy-rules | `--headless --fixed-fps 60 --script res://tests/enemy_rules_test.gd` | 0 | 20 | 0 | 0.3s | PASS |
| 5 | enemy-behavior | `--headless --fixed-fps 60 --script res://tests/enemy_behavior_test.gd` | 0 | 51 | 0 | 1.6s | PASS |
| 6 | blessing-rules | `--headless --script res://tests/blessing_rules_test.gd` | 0 | 24 | 0 | 0.3s | PASS |
| 7 | room-flow | `--headless --fixed-fps 60 --script res://tests/room_flow_test.gd` | 0 | 40 | 0 | 0.8s | PASS |
| 8 | guardian-behavior | `--headless --fixed-fps 60 --script res://tests/guardian_behavior_test.gd` | 0 | 44 | 0 | 1.3s | PASS |
| 9 | art-headless | `--headless --fixed-fps 60 --script res://tests/art_validation_test.gd` | 0 | 96 | 0 | 0.7s | PASS |
| 10 | audio-feedback | `--headless --fixed-fps 60 --audio-driver Dummy --script res://tests/audio_feedback_test.gd` | 0 | 54 | 0 | 0.7s | PASS |
| 11 | vfx-headless | `--headless --fixed-fps 60 --audio-driver Dummy --script res://tests/vfx_feedback_test.gd` | 0 | 21 | 0 | 0.7s | PASS |
| 12 | export-smoke | `--headless --fixed-fps 60 --script res://tests/export_smoke_test.gd` | **1** | 14 | **5** | 0.8s | **FAIL（DEF-02，基建配置）** |
| | **合计** | | | **392** | **5** | **13.4s** | **10/12 PASS** |

汇总行（原文）：
```text
FAIL: 10/12 checks, 392 assertions, 5 assertion failures, 13.4s
```

### 3.1 独立复核方法（不依赖 `verify.py` 的汇总）

我另行扫描了所有 `.output.txt` 抽取 `* RESULT: N checks, M failures` 原始行，逐项相加与上表一致：

```text
ART VALIDATION RESULT: 96 checks, 0 failures
AUDIO FEEDBACK RESULT: 54 checks, 0 failures
BLESSING RULES RESULT: 24 checks, 0 failures
COMBAT RULES RESULT: 28 checks, 0 failures
ENEMY BEHAVIOR RESULT: 51 checks, 0 failures
ENEMY RULES RESULT: 20 checks, 0 failures
EXPORT SMOKE RESULT: 14 checks, 5 failures      <-- 红项
GUARDIAN BEHAVIOR RESULT: 44 checks, 0 failures
ROOM FLOW RESULT: 40 checks, 0 failures
VFX FEEDBACK RESULT: 21 checks, 0 failures
```

与 PROJECT_PLAN 已知基线的一致性：`combat-rules 28 项全通过` ✔、`171 处 res:// 引用可解析` ✔、`主场景 headless 冒烟通过` ✔。

---

## 4. 与 README 声称"544 项断言"的差异说明（如实核对，不迁就文档）

**结论：README 的 544 不是本次 headless 运行的读数，且自 P7 起已过时。**

1. **544 的来源**：`README.md:108` 写明"原 P1–P5 的 447 项 + 新增 97 项美术检查"。我核对了算术：
   - P1–P5 唯一断言 = headless 207（combat 28 + enemy-rules 20 + enemy-behavior 51 + blessing 24 + room-flow 40 + guardian 44）+ 图形 240（input-physics 50 + combat-integration 60 + enemy-integration 26 + room-integration 40 + full-run-integration 64）= **447** ✔（与 `docs/TESTING.md` 的 P5 记录一致）
   - 美术 97 = `art-headless` 96 + 图形模式多出的 1 项真实帧检查 ✔（README 明确说明 96 项不重复计数）
   - 447 + 97 = **544** ✔ **算术自洽**
2. **但本次 headless 读数是 392，不是 544**，原因有三，均非"少了 152 项覆盖"：
   - 392 中**没有**图形独占的 240 项（`input-physics` / 各 `*-integration` / `full-run-integration`）——它们需要真实窗口，`--headless-only` 按设计跳过；
   - 392 **含** `art-headless` 96 项，而这 96 项在图形模式会被 `art-rendering` 重跑（97 项），属重复计数区间；
   - 392 **含** `export-smoke` 14 项，而这 14 项在当前登记方式下结构性不可能通过（DEF-02），不应计入有效覆盖。
3. **544 已过时**：P7 新增了两个 headless 检查 —— `audio-feedback`（54）与 `vfx-headless`（21），README 未计入。按当前套件，唯一断言数**至少**为 447 + 97 + 54 + 21 = **619**；若 `vfx-rendering` 与 `vfx-headless` 不复用同一批断言，或计入合法执行后的 `export-smoke` 14 项，最终数字**≥ 619**，确切值待 T8 图形全量实测后确定。
   → **建议（归属 T10/T11，不在我的写范围）**：README 第 108 行的 544 改为 T8 实测后的唯一断言数，并注明"headless-only 读数 ≠ 唯一断言数"。
4. **另一处 README 陈旧项**：`README.md:98-106` 的"使用 PowerShell 7 / `pwsh -File .\tools\verify.ps1`"在本机**不可执行**（无 pwsh 7）。应改为 `py tools/verify.py`，否则上线验收说明会误导持有该包的验证者。

---

## 5. 缺陷清单（红项，含复现命令与完整错误行）

### DEF-01｜`import` 检查恒失败：编辑器缓存目录无法创建（环境/基建，非游戏缺陷）

- **严重程度：一般**（不阻断游戏运行；但使"全量全绿"门禁永久为红，必须修复才能作为上线证据）
- **归属**：T1 验证基建（`tools/verify.py`，Lead）— **不是游戏代码缺陷**
- **复现命令**：
  ```powershell
  cd D:\game\StarAbyss
  & "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only import
  ```
- **完整错误行**（`PASS/FAIL` 归类取 `import.output.txt`，共 3 条真错误）：
  ```text
  ERROR: Could not create editor cache directory: C:/Users/hongxinyu/AppData/Local/Godot
     at: EditorPaths (editor/file_system/editor_paths.cpp:237)
  ERROR: Cannot create file 'C:/Users/hongxinyu/AppData/Local/Godot/editor_doc_cache-4.7.res'.
     at: save (core/io/resource_format_binary.cpp:2117)
  ERROR: Cannot save editor help cache (C:/Users/hongxinyu/AppData/Local/Godot/editor_doc_cache-4.7.res).
     at: _gen_doc_thread (editor/doc/editor_help.cpp:3071)
  ```
  （另有 2 条属已过滤的无害日志：`Can't save resource to empty path`、`Error saving editor settings to`；`Failed to read the root certificate store` 亦为已过滤项。）
- **根因**：`verify.py` 只把 `APPDATA` 重定向到 `.local/appdata`，**没有重定向 `LOCALAPPDATA`**。Godot 4.7 的编辑器文档缓存目录取自 `%LOCALAPPDATA%`（`editor_paths.cpp:237`），引擎进程在该位置无法创建目录 → 3 条 `ERROR`。检查退出码实际是 **0**（导入本身成功），失败纯粹由错误行归类触发。
- **最小验证证据（我做的对照实验）**：
  - 对照 A（复刻 `verify.py` 环境，只设 `APPDATA`）：稳定复现上述 3 条错误 → `.local/validation/probe_import_localappdata_default.log`
  - 对照 B（**同时**设 `LOCALAPPDATA=D:\game\StarAbyss\.local\localappdata`）：**3 条错误全部消失**，日志只剩已过滤的证书库行 → `.local/validation/probe_import_localappdata.log`
  - 旁证：`$env:LOCALAPPDATA\Godot` 目录原本不存在（`Test-Path` = False）；PowerShell 自身可在该路径 `mkdir` 成功（`MKDIR OK`），说明是**引擎子进程被限制在工作区内创建目录**，而非磁盘权限问题。
- **建议修复（一行环境变量，建议在 `verify.py` 的 `run_check` 中与 `APPDATA` 一并设置）**：
  ```python
  env["LOCALAPPDATA"] = str(PROJECT_ROOT / ".local" / "localappdata")
  ```
  并在 `main()` 中 `mkdir` 该目录。**不建议**把它加进 `IGNORED_ERRORS`——那会连带隐藏真正影响导入的缓存写入失败。
- **修复后预期**：`import` 变为 PASS，headless 汇总从 10/12 变为 11/12。

### DEF-02｜`export-smoke` 被登记为 headless 检查，结构性必然失败（基建配置，非游戏缺陷）

- **严重程度：严重**（门禁恒红，且每次运行额外产生一条真 `ERROR:`；但**不影响游戏本身**，也不代表打包结果有问题）
- **归属**：T1 验证基建（`verify.py:86-87` 的登记方式，Lead）+ T4 导出流水线（产物缺失）
- **复现命令**：
  ```powershell
  cd D:\game\StarAbyss
  & "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only export-smoke
  ```
- **完整错误/失败行**（`export-smoke.output.txt`）：
  ```text
  FAIL: shipped pack excludes development tests
  FAIL: packed-data game window captures input
  FAIL: packed-data runtime executes actual movement input
  FAIL: packed-data runtime executes actual skill input
  FAIL: packed-data runtime renders an actual gameplay frame
  EXPORT SMOKE RESULT: 14 checks, 5 failures
  ERROR: Parameter "t" is null.
     at: texture_2d_get (./servers/rendering/dummy/storage/texture_storage.h:110)
     GDScript backtrace (most recent call first):
         [0] _test (res://tests/export_smoke_test.gd:49)
  ```
- **根因（三条，均为执行方式与用例设计不匹配，非游戏缺陷）**：
  1. `export_smoke_test.gd` 是**外部 PCK 夹具**（脚本头注释："External PCK fixture … usage: same-version editor with `--main-pack`"），`docs/BUILD_WINDOWS.md:58` 与 `tools/build_windows.ps1:142` 都规定它必须以 `--main-pack <最终PCK>` **图形模式**运行。而 `verify.py` 把它登记成 `["--headless", ...]`（`graphical=False`），既无 PCK 也无窗口。
  2. 无 PCK → 从工程源码运行 → `res://tests/combat_rules_test.gd` 存在 → `FAIL: shipped pack excludes development tests`（**这是"未打包"的正确反映，不是包的缺陷**）。
  3. headless 无窗口 → 鼠标捕获失败；且 `run_manager.gd:59` 在 `NOTIFICATION_APPLICATION_FOCUS_OUT` 时调用 `pause()`，headless 无焦点窗口导致真局被自动暂停 → 移动/技能断言失败；dummy 渲染器无纹理 → `texture_2d_get` 报 `Parameter "t" is null.`
- **正确处理（两条，建议同时做）**：
  - `verify.py`：把 `export-smoke` 从 `CHECKS` 移除，或标为 `graphical=True` 且**仅当存在已导出的 PCK 时**才纳入，并以 `--main-pack` 传入；正常路径应保留在 `tools/build_windows.py` 的导出流水线里（`BUILD_WINDOWS.md:56-58` 已如此规定）。
  - 我（QA）在 T8 阶段对**真实 PCK + 真实 exe** 执行该夹具与独立启动验收，把结果补进本报告第 7 节。
- **补充事实**：本次核查时 `StarAbyss\builds\` 为空、全工程无任何 `.pck` 文件 → T3/T4 尚未产出包，**该夹具的正常执行时机尚未到来**。因此我不能说"打包功能已通过"，只能说"当前无从验证"。

### 非缺陷但需登记的观察

| 观察 | 说明 |
| --- | --- |
| `main-headless` 无 `RESULT` 行 | 冒烟夹具（`main_scene_smoke_test.gd`）按设计不打印断言数，仅以退出码与错误行判定；**它的 PASS 不代表任何断言数**，不要把它算进断言总数。 |
| 断言总数 392 的口径 | 见第 4 节：含 96 项美术（图形会重跑）与 14 项无效 `export-smoke`，**不等于**唯一覆盖数。 |

---

## 6. 未执行的测试（明确记录原因，未默默跳过）

| 未执行项 | 原因 | 计划 |
| --- | --- | --- |
| `main-window`、`art-rendering`、`vfx-rendering`、`input-physics`、`combat-integration`、`enemy-integration`、`room-integration`、`full-run-integration`、`performance`（9 项图形检查） | 本次为 `--headless-only` 基线，按设计跳过；且图形套件需独占窗口与鼠标，已在 T8 排期。**不是"环境无桌面"**——Lead 已实测本机图形模式可用（Vulkan/Forward+ 启动退出码 0）。 | T8（task-7）执行，运行前向 Lead/dev 报备窗口占用 |
| 完整三房通关闭环（菜单→2哨兵→祝福→3哨兵→祝福→Boss→胜利/失败→重开/返回菜单） | 在 `full-run-integration` 图形检查内，同上 | T8 |
| `export-smoke` 的**有效**执行（`--main-pack` + 真实 exe + 图形） | 尚无导出 PCK（T3/T4 未完成） | T4 产出包后立即执行，并补入本报告 |
| `verify.py` 图形阶段对 GPU/Vulkan 行的独立取证（RTX 3050 / Vulkan 1.4.325） | 需开窗口 | T8 亲自记录 |
| 补充用例（启动/核心玩法/胜负闭环/UI/异常/性能） | 待 T8 编写为可执行脚本 | T8 |
| 人工试玩（手感、美术风格认可、音效听感） | 需真人操作，无法自动断言 | 留给 Lead 人工验收清单，本报告不代替 |

---

## 7. 下一步（T8 计划，简要）

1. 图形全量：`py tools\verify.py --json .local\validation\full_graphical.json`（先报备窗口占用）。
2. 重点取证 `full-run-integration` 的完整闭环与失败路径。
3. 新增补充用例脚本（`godot/tests/`，`extends SceneTree`，输出 `... RESULT: N checks, M failures`）。
4. 待 T4 产出 PCK/exe 后，对真实包执行 `export-smoke` + 干净目录启动。
5. 更新本报告：用例清单、通过/失败/未执行数量、失败复现步骤、遗留缺陷与严重程度。

---

## 附录 A：本次产生的证据文件

```text
.local/validation/baseline_headless.json          # 机器可读汇总
.local/validation/baseline_headless.stdout.txt    # 完整控制台输出
.local/validation/*.log                           # 12 个检查的引擎日志
.local/validation/*.output.txt                    # 12 个检查的 stdout/stderr
.local/validation/probe_import_localappdata.log          # DEF-01 对照 B（已修复环境，0 条缓存错误）
.local/validation/probe_import_localappdata_default.log  # DEF-01 对照 A（复刻 verify.py，3 条错误）
```
