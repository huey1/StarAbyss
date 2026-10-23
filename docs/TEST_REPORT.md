# Star Abyss 测试报告（P7）

- **版本**：第 2 版（完整版）
- **执行时间**：2026-10-23 12:44 – 13:00（Asia/Shanghai）
- **执行者**：qa-verifier（独立验证者；**本报告的每个结论都来自真实执行**，未用"只读代码"代替执行）
- **分层口径**：与 `docs/TESTING.md` 完全一致 —— **L1 headless / L2 图形 / L3 打包数据 / L4 发布 exe 原生输入**（Lead 的 FINAL_REPORT 可直接引用这四个名字）
- **当前判定**：L1 全绿；L2 全绿（含三房 + Boss 完整闭环，连续三局）；L3 中间包结构合法且包内数据可玩（15/15 + 75/75）；**L4 待发布 exe 产出后执行**。**无已知未解决的阻断/严重游戏缺陷**；有 3 项环境/基建缺陷已修复、1 项并发编辑中间态待复验、2 项已知限制需随发布说明披露。

---

## 1. 环境事实（本次实测，非文档抄录）

| 项目 | 实测值 | 证据 |
| --- | --- | --- |
| 引擎 | `D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe`（日志/headless）、`..._win64.exe`（图形） | 每个检查的 `.output.txt` 首行 |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf` | `Godot Engine v4.7.2.stable.official.ed1daf0bf` |
| 工程 | `D:\game\StarAbyss\godot` | `verify.py` 打印 `Project:` |
| Python | `C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe`（**无 `python` 命令**） | 全部命令 |
| PowerShell | 仅 5.1，**无 pwsh 7** → `tools/verify.ps1` 不可用 | `TESTING.md` 已更正 |
| GPU / 渲染 | `NVIDIA GeForce RTX 3050` / Vulkan / Forward+ | Lead 实测启动行（RTX 3050，**不是** README 写的 GTX 1660 SUPER） |
| 用户目录重定向 | `APPDATA`、`LOCALAPPDATA` → `.local/`（`verify.py` 内置）；打包相关另需 `TEMP`/`TMP` → `.local/tmp` | 见 DEF-01 |
| 资源引用 | **186** 处 `res://` 全部可解析（P7 起始 171，art 新增音频/资源后增长） | `PASS: 186 resource references resolve` |

---

## 2. 四层证据链（每层能证明什么、不能证明什么）

| 层 | 本次结果 | 能证明 | **不能**证明 |
| --- | --- | --- | --- |
| L1 headless | **12/12 检查通过，501 断言，0 失败** | 规则/数值/状态机/AI/流程/音频/VFX 资源 | 窗口、渲染、真实鼠标、完整局 |
| L2 图形 | **21/21 检查通过，872 断言读数，0 断言失败**（含 3 局完整闭环） | 真实窗口 + Forward+ + 注入键鼠 + 真实物理的完整游玩 | 发布包本身（跑的是工程源码） |
| L3 打包数据 | **pack_audit 75/75 + export-smoke 15/15**（中间包） | 最终 PCK 内数据完整、可真实点击游玩、无测试泄漏 | 真实 exe 的原生输入 |
| L4 原生输入 | **待执行**（见 §6） | OS 级注入下真实 exe 有画面响应（佐证） | 完整闭环（闭环由 L2+L3 覆盖） |

> **口径警告**：`872` 是套件**读数**（headless 与图形各跑一遍 art/vfx，存在 117 项重复）。**去重后的唯一断言数为 755**，详见 §7。

---

## 3. L1 headless 结果（`--headless-only`，逐项实测）

命令：
```powershell
cd D:\game\StarAbyss
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --headless-only --json .local\validation\baseline_headless.json
```

| # | 检查 | 退出码 | 断言 | 失败 | 耗时 | 结果 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | import | 0 | – | – | 2.9s | PASS |
| 2 | main-headless | 0 | –（冒烟，无 RESULT） | 0 | 0.5s | PASS |
| 3 | combat-rules | 0 | 28 | 0 | 0.3s | PASS |
| 4 | enemy-rules | 0 | 20 | 0 | 0.3s | PASS |
| 5 | enemy-behavior | 0 | 51 | 0 | 1.7s | PASS |
| 6 | blessing-rules | 0 | 24 | 0 | 0.4s | PASS |
| 7 | room-flow | 0 | 40 | 0 | 0.8s | PASS |
| 8 | guardian-behavior | 0 | 44 | 0 | 1.4s | PASS |
| 9 | art-headless | 0 | 96 | 0 | 0.7s | PASS |
| 10 | audio-feedback | 0 | **138** | 0 | 0.8s | PASS |
| 11 | vfx-headless | 0 | 21 | 0 | 0.7s | PASS |
| 12 | robustness（QA 新增） | 0 | **39** | 0 | 0.8s | PASS |
| | **合计** | | **501** | **0** | | **12/12** |

基线核对（与 Lead 的已知基线一致）：`combat-rules 28/28` ✔、资源引用全解析 ✔、主场景 headless 冒烟 ✔。

### 3.1 QA 新增用例 `godot/tests/robustness_test.gd`（39 项）

既有 12 套件未覆盖的空白，逐条都有真实断言：

| 覆盖点 | 断言示例 |
| --- | --- |
| 窗口失焦（此前**无任何用例覆盖**） | 失焦→暂停；**重复失焦不损坏状态**；恢复回到 COMBAT 而非卡 PAUSED；**失焦不会取消/重roll 祝福卡** |
| 连续重开（此前只测过单次） | 从 COMBAT / PAUSED / FAILED 各发起一次；每次都复位 HP/祝福/敌人数；**只留 1 个 RoomController 实例**；**子节点数不增长（6→6）** |
| 重复选卡 | 同一张卡连点 3 次只生效 1 次；过期 reward id 无法二次生效；提交后 modal 隐藏 |
| UI 契约 | 菜单「开始本局/退出游戏/静音」；暂停弹窗三按钮可见性规则；祝福阶段三按钮按设计隐藏；房间计数「01 / 03」；「存活哨兵 2 / 2」；Boss 面板首房隐藏 |
| 帧处理时间代理 | 120 帧平均/最差 process time（**显式标注不是 fps 结论**） |

---

## 4. L2 图形结果（真实窗口 + Forward+ + 注入键鼠 + 真实物理）

命令：
```powershell
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --json .local\validation\full_graphical_final.json
```

**最终结果行（原文，2026-10-23 13:00）：**
```text
PASS: 21/21 checks, 872 assertions, 0 assertion failures, 54.2s
```
进程退出码 **0**，无任何未过滤的 `SCRIPT ERROR:` / `ERROR:` 行。汇总：`.local/validation/full_graphical_final.json`。

| # | 检查 | 退出码 | 断言 | 失败 | 耗时 | 结果 |
| --- | --- | --- | --- | --- | --- | --- |
| 1–12 | 同 L1 全部 headless 项（含 import/robustness） | 0 | 501 | 0 | 24s | PASS |
| 13 | main-window（真实窗口启动） | 0 | – | – | 1.2s | PASS |
| 14 | art-rendering（Forward+ 真实帧 + 截图） | 0 | 97 | 0 | 1.7s | PASS |
| 15 | vfx-rendering | 0 | 22 | 0 | 1.6s | PASS |
| 16 | input-physics（WASD/跳跃/闪避/镜头 + 真实鼠标事件） | 0 | 50 | 0 | 2.1s | PASS |
| 17 | combat-integration | 0 | 60 | 0 | 4.8s | PASS |
| 18 | enemy-integration | 0 | 26 | 0 | 3.8s | PASS |
| 19 | room-integration（实际 Esc / 鼠标点卡 / 走门） | 0 | 40 | 0 | 4.9s | PASS |
| 20 | **full-run-integration（完整闭环）** | 0 | **64** | 0 | **16.9s** | PASS |
| 21 | performance | 0 | 12 | 0 | 8.1s | PASS（修复后，见 DEF-03） |
| | **合计** | | **872** | **0** | **56.3s** | **21/21** |

### 4.1 完整闭环证据（验收标准第 3 条）

`full-run-integration` 全程真实执行并 64 项全过，覆盖：**主菜单真实点击「开始本局」→ 遗迹前庭 2 哨兵真实战斗 → 清场 → 真实鼠标点击祝福卡 → 实际 WASD 穿过实体门 → 星辉回廊 3 哨兵 → 第二次祝福 → 晶核封印 350 HP Boss（横扫 + 圆形冲击两招、真实预警规避）→ 胜利结算 → 重开 → 再次胜利 → 返回菜单**；另含**失败路径**（普通敌人真实打死玩家 → 失败结算 → 重开）与 1280×720 / 1920×1080 两档分辨率截图。连续三局均完成 3 房 6 击杀 2 祝福、无残留状态。

> 边界（如实）：脚本控制瞄准方向，**不能替代实体键鼠手感**；该套件不修改 HP/伤害/速度/冷却/无敌参数，也不直接扣敌人 HP。

---

## 5. L3 打包数据（中间包）

### 5.1 包的身份（**验证过两份不同的中间包，结论不同，务必区分**）

| 项目 | 中间包 v1（通过） | 中间包 v2（**坏包，已定位**） |
| --- | --- | --- |
| 路径 | 同下（已被覆盖） | `D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck` |
| 大小 | `3,161,884` 字节 | `3,162,764` 字节 |
| sha256 | `e1cfef108f8a0b4ec355d2b0a3cc362be8600d6666563f8e5730951d8dc4de4b` | `c69c89545e4e921542b07d808720e522b50b44ee9bbf3d04f912e8dfadce1ce0` |
| 生成时间 | 2026-10-23 12:53:53 | 2026-10-23 12:57:03 |
| 结论 | **pack_audit 75/75 + export-smoke 15/15 通过** | **export-smoke 失败**（包内 `actor_presentation.gd` 为 art 半保存版本，Parse Error），详见 §5.4 |
| 性质 | **中间包**：都是 `--export-pack` 产物，无 exe（导出模板尚在下载），后续 art/code 仍会变更 | 同左 |

> **只凭"导出成功 + 体积正常 + pack_audit 通过"会误判包可用**：v2 的审计同样 75/75 全绿。区分两者的唯一手段是真跑 `export-smoke`。

### 5.2 结果（中间包 v1，3,161,884 字节）

| 检查 | 层 | 结果 | 证据 |
| --- | --- | --- | --- |
| `tools/pack_audit.gd` | 包清单完整性 | **75 checks, 0 failures** | 27 个音频 cue 可解码、7 场景、7 GLB、4 项"开发测试未泄漏"、主场景设置正确 |
| `tools/pack_diagnose.gd` | 包结构 | `project.binary` **5418 字节，magic `ECFG` 有效**；`MAIN SCENE SETTING: 'res://scenes/ui/main_menu.tscn'`；228 文件 | 见 §5.3 |
| `export-smoke`（外部 PCK 夹具） | 包内数据可玩 | **15 checks, 0 failures，exit 0（1.8s）** | 见下 |

`export-smoke` 15 项断言（真实执行，非描述）：
```text
PASS: designated same-version game runtime loads packed data for external fixture
PASS: shipped pack excludes development tests
PASS: pack loads actual main menu and start button
PASS: actual menu click loads first room from PCK
PASS: pack starts with correct enemies and player health
PASS: pack loads imported skeleton and independent weapon
PASS: packed-data game window captures input
PASS: packed-data runtime executes actual movement input
PASS: packed-data runtime executes actual skill input
PASS: packed-data runtime renders an actual gameplay frame
PASS: package gameplay screenshot saved
PASS: packed-data Esc pauses the real run
PASS: paused package does not advance run clock
PASS: package restart clears run data
PASS: package can return to clean main menu
```

命令：
```powershell
& py tools\verify.py --packed "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck" --only export-smoke
```

### 5.3 中间包的坏包事件（重要记录，**不是游戏缺陷**）

第一版中间包（`3,156,204` 字节，已被覆盖删除）存在结构缺陷：

```text
ERROR: Corrupted header in binary project.binary (not ECFG).
MAIN SCENE SETTING: ''
```
- **根因**：构建环境**禁止写真实 `C:\Users\...\AppData\Local`**，Godot 写临时 `project.binary` 失败后把 **0 字节文件**打进了包；`--export-pack` 退出码仍为 0、PCK 体积也正常，**极具欺骗性**。
- **修复（release 负责）**：构建脚本把 `TEMP`/`TMP`（连同 `APPDATA`/`LOCALAPPDATA`）重定向到工程内，并加 `assert_pck_is_launchable()` 校验 `project.binary` 非空。
- **复验（本次）**：`pack_diagnose` 显示 `len=5418 / ECFG 有效 / 主场景正确`，`pack_audit` 75/75、`export-smoke` 15/15。
- **结论**：**构建环境缺陷，已修复并复验；不计为游戏缺陷。**
- **仍然注意**：坏包体积（3,156,204）与好包（3,161,884）接近，**只凭"导出成功 + 文件大小合理"会误判**。凡遇包级问题，先跑 `pack_diagnose.gd` 看 `project.binary` 的 magic 与长度。

### 5.4 中间包 v2（3,162,764 字节）：**打包了半保存脚本，审计查不出，只有 export-smoke 能抓**

`pack_diagnose` 与 `pack_audit` 对 v2 **全部通过**（`project.binary` 5418 字节、`ECFG` 有效、主场景正确、`PACK AUDIT RESULT: 75 checks, 0 failures`），但 `export-smoke` 立即暴露：

```text
SCRIPT ERROR: Parse Error: Function "_cache_threat_meshes()" not found in base self.
   at: GDScript::reload (res://scripts/art/actor_presentation.gd:64)
SCRIPT ERROR: Parse Error: Function "_update_threat()" not found in base self.
   at: GDScript::reload (res://scripts/art/actor_presentation.gd:112)
ERROR: Failed to load script "res://scripts/art/actor_presentation.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
PASS: pack loads actual main menu and start button
PASS: actual menu click loads first room from PCK
SCRIPT ERROR: Invalid access to property or key 'skeleton' on a base object of type 'Nil'.
   at: _test (D:/game/StarAbyss/godot/tests/export_smoke_test.gd:36)
```

- **根因**：v2 于 12:57:03 生成，而 art 在 12:56:44–12:58:01 正处于 `actor_presentation.gd` 的"调用点已写、函数体未写"中间态，**构建把该版本编译进了包**。
- **影响**：包内玩家/敌人表现层脚本不可加载，`ActorPresentation` 为 `nil` → 骨骼动画、武器挂点、受击表现全部失效。**若这样的包上线即阻断。**
- **修复（流程，非代码）**：**构建前必须确认全部 `scripts/**/*.gd` 通过 `--check-only`，且构建期间禁止任何人保存源码**；构建后 `pack_audit` **与** `export-smoke` 都要跑（前者不解析 GDScript，**替代不了后者**）。
- **附带发现并已修复的用例缺陷**：原夹具在 `presentation` 为 `nil` 时访问 `.skeleton` 会抛错中断协程、**永远走不到 `quit()`**，整轮挂到 300 s 超时（实测挂住 >2.5 min）。已在 `export_smoke_test.gd` 加 fail-fast 守卫（`get_node_or_null` + 失败即 `quit(1)`），坏包现在**立刻红并退出**。
- **定性**：这是**构建时序缺陷 + 用例健壮性缺陷**，**不是**游戏代码缺陷（art 最终版本已 `--check-only` 通过）；v2 未上线、已作废。

---

## 6. L4 发布 exe 原生输入（待执行）

**状态：未执行。原因：发布 exe 尚不存在**（导出模板仍在下载，`builds/` 下无 exe）。

- 已验证条件：本机图形模式可用（Vulkan / Forward+，真实窗口能打开并渲染），因此该层**可执行**，只是缺产物。
- 已准备好脚本：`.local/validation/native_input_check.ps1`（PS 5.1 + `Add-Type` 调 `user32` 的 `SetCursorPos`/`mouse_event`/`keybd_event`，`System.Drawing` 的 `CopyFromScreen` 截图，C# `LockBits` 做像素差异统计，输出 `native_input_result.json`）。
- 判据（产出后填）：菜单→战斗 画面变化比例、按住 W 后 画面继续变化比例，两者均需 ≥ 2%。
- **措辞边界**：本层只能写成"**真实 exe 的原生输入已由 OS 级注入 + 画面差异佐证**"，**不得**写成"完整闭环已在发布 exe 上验证"——闭环由 L2（源码）+ L3（包内数据）相加覆盖。

---

## 7. 断言总数核算：与 README「544 项断言」的独立核对

**结论：README 的 544 算术自洽，但已过时（P7 起）；当前去重唯一断言数为 755（+L3 的 90 = 845）。**

1. **544 的来源拆解（我逐项验证过，能对上）**
   - P1–P5 唯一断言 **447** = headless 207（combat 28 + enemy-rules 20 + enemy-behavior 51 + blessing 24 + room-flow 40 + guardian 44）+ 图形 240（input-physics 50 + combat 60 + enemy 26 + room 40 + full-run 64）
   - 美术 **97** = `art-headless` 96 + 图形模式多出的 1 项真实帧
   - 447 + 97 = **544** ✔
2. **现状（L1+L2 实测）**
   - 套件**读数 872** = headless 501 + 图形独占 371（97+22+50+60+26+40+64+12）
   - **唯一断言 755** = 872 − 117 重复（art 96 + vfx 21 在两层各跑一次）
   - 差额构成：audio-feedback 54→**138**（P7 音频 27 cue 全覆盖）、robustness **+39**（QA 新增）、vfx 21→22、P7 新增 vfx/audio 两个套件
3. **L3 追加**：`pack_audit` 75 + `export-smoke` 15 = **90**（不重复计入 L1/L2）→ 证据链合计 **845** 项唯一断言。
4. **建议（归属 T10/T11，不在我的写范围）**：README 第 108 行的 544 改为"**755（源码层）+ 90（包层）**"，并注明"套件读数 872 含跨层重复，不等于唯一断言数"；同时把 `README.md:98-106` 的 `pwsh -File tools/verify.ps1` 改为 `py tools\verify.py`（本机无 pwsh 7，照文档执行会失败）。

---

## 8. 缺陷清单（含复现命令、完整错误行、严重程度、归属）

### 已修复

| ID | 缺陷 | 严重程度 | 归属 | 状态与证据 |
| --- | --- | --- | --- | --- |
| **DEF-01** | `import` 恒失败：`verify.py` 只重定向 `APPDATA`，未重定向 `LOCALAPPDATA`，编辑器文档缓存建目录失败打 3 条 ERROR | 一般（门禁恒红，非游戏缺陷） | T1（Lead） | **已修复**。对照实验：只设 APPDATA 稳定复现 → 同时设 LOCALAPPDATA 后 3 条错误消失。修复后 `import` PASS |
| **DEF-02** | `export-smoke` 被登记为 headless 检查，结构性必失败（需 `--main-pack` + 窗口），并额外产生 `ERROR: Parameter "t" is null.` | 严重（门禁恒红，非游戏缺陷） | T1（Lead） | **已修复**：移出默认套件，改为 `--packed <pck>` 显式启用。复验 15/15 |
| **DEF-03** | `performance` 检查退出时报 `ERROR: N resources still in use at exit`（N=3~5 抖动） | 一般（无断言失败，但错误行使检查判红） | QA（本文件的 `godot/tests/performance_benchmark.gd`） | **已修复**。根因见下 |
| **DEF-04** | 中间包 `project.binary` 为 0 字节 → 包内主场景为空，装起来必崩 | **阻断**（若上线） | Release（构建环境） | **已修复并复验**（pack_diagnose + pack_audit 75/75 + export-smoke 15/15） |

**DEF-03 根因（值得记档）**：该夹具用 `await create_timer(0.25).timeout` 等音频异步回收，而 `SceneTreeTimer` 走的是**模拟时间**；在 `--fixed-fps 60 --max-fps 0` 下 0.25 模拟秒可能只对应几毫秒真实时间，音频服务来不及释放 → 退出时报资源仍在使用。verbose 证据：
```text
Leaked instance: AudioStreamWAV ... / AudioStreamPlaybackWAV ...
Resource still in use: res://assets/audio/swing_03.wav / skill.wav / dodge.wav / guardian_slam.wav / victory.wav
ERROR: N resources still in use at exit.
```
其余 13 个夹具都用墙钟 `Time.get_ticks_msec()` 等待，**只有 performance 用了 timer**。修复：改为墙钟等待 250 ms + `await process_frame`。复验：连跑两次均 `PERFORMANCE RESULT: 12 checks, 0 failures`、无泄漏行、退出码 0。

### 观察中（并发编辑中间态，非交付缺陷）

| ID | 现象 | 严重程度 | 状态 |
| --- | --- | --- | --- |
| **OBS-01** | 图形全量运行期间 `res://scripts/art/actor_presentation.gd` 正在被 art 编辑，导致 `SCRIPT ERROR: Parse Error: Function "_cache_threat_meshes()" not found in base self.` / `"_update_threat()" not found` / `Failed to load script ... Parse error`，使该次 `performance` 阶段判红 | 若留存至构建则**阻断**；本次为编辑中间态 | **已关闭**。已即时通报 art 与 Lead；art 于 12:58:01 补齐 `_cache_threat_meshes()`（第 147 行）与 `_update_threat()`（第 157 行），`--check-only` 退出码 0；随后重跑图形全量 **21/21 通过、退出码 0**（`.local/validation/full_graphical_final.json`）。**该次污染运行已作废，不计入结论** |

> 说明：该次污染发生在运行中途（同一轮里前 20 项通过、最后一项读到半保存文件），**不是**渲染或性能问题，也**不能**据此判断 art 的最终代码有缺陷。

---

## 9. 已知限制与遗留风险（随发布说明披露，非缺陷）

1. **冷启动首次进入 3D 场景单帧 3548 ms**（Vulkan pipeline/shader cache 首次编译；暖缓存下 165–200 ms）。属首发体验风险，Lead 已决定本期不修（加预加载/加载界面属行为变更），要求 T10 在**真实导出包**上复测并写入已知限制。**数据来源：Dev 的 T7 实测**（`docs/PERFORMANCE.md`）。
2. **帧时间判读口径**（与 `docs/PERFORMANCE.md` 一致，防误读）：`run/max_fps=60` + 关闭 vsync 时，帧时间 p50 ≈ 16.66–16.69 ms、**mean FPS = 60.0**；"`>16.7 ms` 帧占比约 50%"是**帧限速器的睡眠粒度抖动，不是掉帧**。有意义的指标是 p95 ≈ 17.1–18.0 ms、p99 ≈ 17.5–19.5 ms、偶发单帧 max 27–38 ms。
3. **自动化不能替代人工**：手感、动作过渡观感、美术风格认可、音效听感、真实键鼠连续三局仍需人工验收；脚本连续三局不证明 GDD 的 5–8 分钟局时。
4. **单机单 GPU**：仅在 RTX 3050 / Vulkan / Forward+ / Windows 实测，未验证其他 GPU、音频设备或操作系统。
5. **引擎已知边界**：强制在音效播放中途立即退出仍可能触发 Godot 异步音频回收警告（引擎 issue #76745）；正常验证均先释放并等待回收（DEF-03 即该边界的正确用法）。
6. **判定范围**：近战仍是扇形/高度/视线判定（非连续剑刃扫掠），地面扇形显示实际有效距离。

---

## 10. 未执行项（逐条写明原因，未默默跳过）

| 未执行项 | 原因 | 解锁条件 |
| --- | --- | --- |
| **L4 发布 exe 原生输入** | 发布 exe 尚不存在（模板下载中） | T10 产出 exe 后立即执行（脚本已就绪） |
| **最终包的 L3 复验** | 本次仅为中间 PCK；art 仍在改 VFX/音频，dev 可能修缺陷 | T10 最终构建后用同一命令重跑 `pack_audit` + `export-smoke` |
| **art 编辑完成后的图形全量复跑** | ~~`actor_presentation.gd` 正在编辑（OBS-01）~~ | ✅ **已完成**：art 修复后重跑 21/21 通过、退出码 0 |
| **性能详细数据** | 归 Dev 的 `docs/PERFORMANCE.md`（本报告只记 L2 结果 12/12） | 已交叉引用，避免两份数字打架 |
| **人工试玩 / 美术认可 / 音效听感** | 需真人，无法自动断言 | 交 Lead 的人工验收清单 |

---

## 11. 复现命令速查

```powershell
$PY = "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe"
$G  = "D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe"
$PCK = "D:\game\StarAbyss\builds\windows\star_abyss_windows_x64\StarAbyss.pck"
cd D:\game\StarAbyss

# L1
& $PY tools\verify.py --headless-only --json .local\validation\baseline_headless.json
# L2（独占窗口，勿动鼠标）
& $PY tools\verify.py --json .local\validation\full_graphical_final.json
# L3
& $G --headless --main-pack $PCK --script D:\game\StarAbyss\tools\pack_audit.gd --audio-driver Dummy
& $G --headless --main-pack $PCK --script D:\game\StarAbyss\tools\pack_diagnose.gd --audio-driver Dummy
& $PY tools\verify.py --packed $PCK --only export-smoke
# L4（exe 产出后）
powershell -NoProfile -ExecutionPolicy Bypass -File .local\validation\native_input_check.ps1 `
    -Exe '<release exe 路径>' -OutDir 'D:\game\StarAbyss\.local\validation'
# 快速单脚本（务必重定向两个用户目录，否则编辑器缓存会报假 ERROR）
$env:APPDATA='D:\game\StarAbyss\.local\appdata'; $env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'
& $G --path godot --headless --fixed-fps 60 --audio-driver Dummy --script res://tests/robustness_test.gd
```

**环境约束（踩过的坑）**：①无 pwsh 7；②`APPDATA`+`LOCALAPPDATA` 都要重定向；③**引擎导入/导出/编辑必须独占工程**，多进程并发写 `.godot` 会导致 `0xC0000005` 访问冲突崩溃；④图形检查独占窗口，运行中动鼠标或切焦点会污染注入事件（失焦还会触发游戏自动暂停）；⑤`TEMP`/`TMP` 在打包相关运行时也要指到 `.local/tmp`。

---

## 附录 A：本次产生的证据文件

```text
.local/validation/baseline_headless.json            # L1 机器可读汇总
.local/validation/baseline_headless.stdout.txt      # L1 完整控制台输出
.local/validation/full_graphical.stdout.txt         # L2 第一次全量（clean，20/21，仅 performance 泄漏）
.local/validation/full_graphical_final.json         # L2 最终干净全量：21/21、872 断言、0 失败、exit 0
.local/validation/full_graphical_final.stdout.txt    # L2 最终全量完整输出
.local/validation/<check>.log / *.output.txt        # 每个检查的引擎日志与 stdout/stderr
.local/validation/probe_import_localappdata*.log    # DEF-01 对照实验
.local/validation/native_input_check.ps1            # L4 原生输入验证脚本（待 exe）
docs/TESTING.md                                     # P7 分层方法与命令（QA 维护）
```
