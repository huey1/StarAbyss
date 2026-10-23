# Star Abyss 缺陷修复记录（P7 / T9）

范围：本文件记录 **P7 阶段（功能冻结前后）缺陷的复现、根因、修复与回归证据**。
严格区分两类，不允许混写：

- **游戏代码缺陷**：`godot/scripts/`、`godot/scenes/`、`godot/resources/`、`godot/assets/` 中的真实运行时问题；
- **验证/夹具代码缺陷**：`tools/verify.py`、`tools/*.gd`、`godot/tests/*.gd`、构建脚本等，**不影响玩家**，但会让门禁为红或让证据不可信。

格式约定（后续每条缺陷按此追加，不允许只写结论）：

```text
### FIX-<编号>｜<一句话现象>
- 类别 / 严重度 / 归属
- 复现命令（可直接粘贴执行）
- 实际错误行（原文，不得改写）
- 根因
- 修复（改了哪个文件哪段，为什么这是最小改动）
- 回归证据（命令 + 结果 + 证据文件路径）
- 影响面与遗留
```

---

## 1. 本轮结论（2026-10-23，T9 首轮）

**游戏代码缺陷：0 项。本轮 Dev（game-dev）没有修改任何游戏代码、场景或资源。**

依据：

- QA 图形全量一轮：**20/21 通过、872 项断言、0 项断言失败**，唯一红项在 `performance_benchmark.gd`（测试夹具的模拟时间等待），QA 修复后连跑两次 `12 checks, 0 failures`。
- headless 全量：`import` 与 `export-smoke` 两处红项均为验证基建登记问题，属性见第 2 节，**均不是游戏缺陷**（导出 PCK 后 `pack-audit` + `export-smoke` 已 15 项全绿）。
- 我在 T7 性能实测中额外做的排查（真实图形模式、完整三房+Boss）也没有发现玩法/UI/资源缺陷，唯一异常是**冷启动首次编译停顿**，属构建/加载路径，见第 4 节 OPEN-01。

因此 T9 首轮的实际产出是：**把三个“看起来像缺陷”的红项逐个定性到位**（下节），避免它们被误当成游戏 bug 去改玩法代码。

## 2. 缺陷台账（已验证并已由对应 owner 关闭）

| ID | 类别 | 严重度 | 现象 | 根因 | 归属与处理 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| DEF-01 | 验证基建 | 一般 | `import` 检查恒 FAIL，`import.output.txt` 有 3 条 `Cannot create/save editor cache` `ERROR:` | `tools/verify.py` 只重定向 `APPDATA`，未重定向 `LOCALAPPDATA`；Godot 4.7 的编辑器文档缓存目录取自 `%LOCALAPPDATA%`，沙箱内无法创建 | Lead（T1）修复：`verify.py` 增加 `LOCALAPPDATA_PATH` 并在 `run_check` 的 env 与 `main()` 的 mkdir 中一并设置 | 已修复（`verify.py` 12:56 版本，`LOCALAPPDATA_PATH` 见第 43/184/260 行） |
| DEF-02 | 验证基建 | 严重 | `export-smoke` 每次运行 5 项断言失败 + 1 条 `ERROR: Parameter "t" is null.` | 该夹具是**外部 PCK 夹具**（需 `--main-pack` + 真实窗口 + 断言包内不含 tests），却被登记成 headless 普通检查；无包 → 从源码跑 → 断言必然反向 | Lead（T1）修复：从默认套件移除，仅当 `--packed <path>` 时注册为图形检查，并新增更便宜的 `pack-audit` 内容审计 | 已修复；`--packed` 路径实测 `pack-audit` + `export-smoke` 15 项全绿 |
| DEF-03 | 测试夹具 | 一般 | 图形全量里 `performance` 红：退出时 5 个资源未释放 | `performance_benchmark.gd` 用 `create_timer()`（**SceneTreeTimer 走模拟时间**）等待音频异步回收，而该夹具在退出前并不推进模拟时间 | QA（T8）修复：改为**墙钟**等待（`Time.get_ticks_msec()` 循环） | 已修复（`performance_benchmark.gd` 12:54）；连跑两次 `PERFORMANCE RESULT: 12 checks, 0 failures` |

**为什么这三项不由我修**：`tools/verify.py` 属 T1（Lead）写范围，`godot/tests/*.gd` 属 T8（QA）写范围，均不在 T9 的 Dev 写范围内。越权修改会破坏“谁写谁负责”的可核查性，也会与并行改动冲突。

## 3. 我在 T9 首轮的排查（不产生改动，但记录方法与结论）

| 排查项 | 方法 | 结论 |
| --- | --- | --- |
| 帧率是否达标 | 真实 Forward+ 窗口 + 完整三房/Boss 真实输入战斗，两种分辨率 × (不限帧 / 上限 60) | 达标，余量 8–14 倍，详见 `docs/PERFORMANCE.md` |
| 是否存在每帧内存/节点增长 | `Performance.get_monitor()` 逐帧采集 `OBJECT_COUNT`/`OBJECT_RESOURCE_COUNT`/`MEMORY_STATIC`/`RENDER_VIDEO_MEM_USED` | 平台型不增长（峰值落在 3 哨兵房，Boss 房回落） |
| 是否存在持续长帧 | 逐帧墙钟 p50/p95/p99/max | 长帧为孤立单帧、集中在相位切换后；无连续超预算帧 |
| 音频生命周期是否泄漏 | 阅读 `scripts/audio/run_audio.gd` 的 tween/voice/ambience 释放路径与 `_exit_tree` | 未发现泄漏：voice 复用 + `finished` 回收、ambience 由 `_sync_ambience` 独占、`_exit_tree` 调 `stop_all()` |
| 我的实测是否被并行改动污染 | 逐份扫 `--log-file` 引擎日志 | 发现一次真实污染：12:51 的 720p 运行撞上 art 正在编辑 `run_audio.gd` 的中间态（`Parse Error: Function "_set_ambience_cue()" not found`），该次运行**等于无音频**。已在 `docs/PERFORMANCE.md` 第 11 节如实标注并安排音频定稿后复测 |

## 4. 未定级观察项（需要后续证据才能定性，不是“已知缺陷”）

### OPEN-01｜冷启动首次进入游戏出现单帧 3548 ms 停顿

- **现象**：当日首次图形启动，在“点击开始 → 进入首房”处出现单帧 3548 ms（`initial_transition.wall_ms_max`，`process_monitor` 同步 3533 ms；物理仅 5.9 ms）。同一进程后续运行、以及同日后续启动均为 165–200 ms。
- **初步定性**：冷 `shader_cache` + Vulkan `pipelines.forward_plus.nvidia_geforce_rtx_3050.cache` 首次生成 + 场景资源加载，每进程一次。
- **关键判断依据**：`godot/export_presets.cfg` 中 `shader_baker/enabled=true`，而**Shader Baker 只对导出构建生效**；本次实测用的是**编辑器二进制**，因此这 3.5 s **很可能不出现**在发布 exe 上。
- **解锁条件 / 下一步（T10 负责执行）**：对导出后的真实 exe，清空用户的 `shader_cache` 与 `vulkan/pipelines.*.cache` 后启动，记录“启动→主菜单”与“点击开始→进入首房”的实际耗时。
  - 若导出包仍是秒级且无任何加载反馈 → 升级为游戏体验缺陷（严重度：一般），届时由 Lead 决定是否加“编译着色器…/加载中”提示（属行为变更，不在“达标不动代码”的范围内）。
  - 若导出包 < 0.5 s → 关闭该项，只在发布说明里保留“首启动需编译着色器”一句。

### OPEN-02｜1280×720 窗口下引擎报告的根纹理尺寸是 854×480

- **现象（原始读数，非推断）**：`display_server_window_size=[1280,720]`、`root_size=[1280,720]`，但 `root.get_texture().get_size()=[854,480]`、`root.get_visible_rect()=[1920,1080]`；把 `content_scale_mode` 设为 disabled 后两者都变回 `[1280,720]`。
- **已排除 DPI**：同一次采集读到 `screen_scale=1.0`、`screen_dpi=96`、`screen_size=[1920,1080]`，本机是 100% 缩放。854/1280 = 480/720 = 0.667 = 1280/1920（窗口/设计分辨率），因此这是 `stretch=canvas_items` 下的换算口径问题，不是 DPI 缩放。
- **对性能结论无影响**：同相位 GPU p95 从 1.90 ms（1920×1080）到 1.32 ms（报告 854×480），像素量差 5.06 倍而 GPU 时间只差 1.44 倍 → 本作帧成本由 draw call（270–583）与几何提交（10.5 万–16.2 万 primitive）主导，不是填充率主导。
- **解锁条件 / 下一步**：`tools/performance_probe.gd --mode=info` 已加入**决定性取证** —— 直接保存 `root.get_texture().get_image()` 的 PNG 并报出 `presented_image_size`：
  - PNG = 854×480 → 呈现分辨率确实低于窗口，720p 窗口上画面偏糊 → 记为**已知限制/画质问题**，由 Lead 决定是否在 T10 前调整 `stretch`/`allow_hidpi`（我不会擅自改工程设置）；
  - PNG = 1280×720 → 说明 854×480 只是 `get_texture()` 在 stretch 下的口径，真实帧缓冲就是窗口大小，**该项从缺陷表划掉**。

## 5. 修复时必须遵守的既有约束（避免把“修缺陷”变成“新缺陷”）

1. **GDD 玩法数值不可动**：伤害 12/16/24、技能 35、HP 100、闪避 0.45 s / 冷却 1.2 s / 无敌 [0.10,0.30) s、Boss 350 HP 与两招 20/25、哨兵 45 HP。这些是 872+ 项断言的验收基线。
2. **架构边界**：`PlayerController` 只管运动执行、`PlayerStateMachine` 管状态、`CameraController` 管镜头、UI 只经 Signal 订阅；调参走 Resource/导出属性；不加全局单例。
3. **改动 `run_manager.gd` 的 `_notification`/`pause()` 必须回归** `py tools/verify.py --only robustness`（覆盖失焦暂停、连续 3 次重开含 PAUSED/FAILED 状态重开、子节点不增长）。
4. **不要破坏 RunAudio 的信号分离契约**（Art 已实现、QA 有断言依赖）：
   - `cue_played` **只发 4 个跑局事件**：`room_clear` / `blessing` / `victory` / `defeat`；
   - `pause` / `resume` / `room_transition` 走独立信号 `state_cue_played`；
   - 环境床切换走 `ambience_changed`（含切换到 `&""`）。
5. **写范围**：`godot/scripts/`（不含 `scripts/art/`、`scripts/audio/`）、`godot/scenes/`、`godot/resources/`、`docs/FIXES.md`。
   `godot/tests/`（QA）、`tools/verify.py`（Lead）、`scripts/art/`、`scripts/audio/`、`assets/materials/`、`assets/audio/`（Art）、
   `scripts/systems/main_menu.gd`、`scripts/combat/weapon_visual.gd`（Art，冻结前专用）—— **均不可改**，需要动先报 Lead。

## 6. 回归命令速查（本机实测可用）

工作目录 `D:\game\StarAbyss`；无 `python` 命令，用 `py` 启动器；无 pwsh 7，不要用 `tools/verify.ps1`。

```powershell
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --headless-only
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only combat-rules,robustness,room-flow
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --only performance,art-headless,vfx-headless,combat-rules
# 图形套件需独占窗口，跑前向 qa-verifier / lead 报备；不要与他人并行跑引擎（共用 .godot 会 0xC0000005 崩溃）
& "C:\Users\hongxinyu\AppData\Local\Programs\Python\Launcher\py.exe" tools\verify.py --json .local\validation\full_graphical.json
```

性能复测（需独占窗口，~2.5 分钟）：

```powershell
powershell -NoProfile -File tools\benchmark.ps1 -Resolution 1920x1080 -FrameCap 60 -Label 1080p-capped60
powershell -NoProfile -File tools\benchmark.ps1 -Resolution 1280x720  -FrameCap 60 -Label 720p-capped60
```
