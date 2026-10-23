# Star Abyss 性能实测（P7 / T7）

日期：2026-10-23（Asia/Shanghai）。本文件只记录**本机真实图形模式实测**数据，不含估算、外推或目标值。
采集工具：`godot/tests/performance_benchmark.gd`（既有套件）+ `tools/performance_probe.gd`（本次新增的只读探针，
位于 `res://` 之外，不被任何场景/资源/Autoload 引用，不会进发布包）。

## 1. 结论

**在 1920×1080 与 1280×720 两个目标分辨率下均实测达标：引擎 `run/max_fps=60` 时平均帧率 59.5–60.0 FPS，
帧时间 p95 ≤ 18.0 ms、p99 ≤ 20.0 ms，GPU 帧时间 p95 ≤ 2.8 ms，无持续掉帧、无内存增长。
因此本阶段不做任何优化改动，不改渲染/阴影/后处理/材质/导入参数，不改代码。**

判定依据与判据说明见第 4 节，逐相位数据见第 5–7 节，异常长帧分析见第 8 节。
需要人工复核的两点已明确记录：进入游戏时的一次性首次编译停顿（第 8.2 节）与 720p 下引擎报告的根渲染目标尺寸（第 9 节）。

| 分辨率（窗口） | 帧率上限 | 平均 FPS（房1 / 房2 / Boss） | 帧时间 p50 / p95 / p99（战斗相位区间） | GPU 帧时间 p95 | draw calls p95 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| 1920×1080 | 60（发布设置） | 59.6 / 59.9 / 60.0 | 16.66–16.69 / 17.38–17.95 / 17.96–19.96 ms | 2.52–2.53 ms | 530 | 达标 |
| 1280×720 | 60（发布设置） | 59.5 / 59.9 / 60.0 | 16.64–16.67 / 17.48–17.66 / 18.18–19.47 ms | 1.51–1.61 ms | 530 | 达标 |
| 1920×1080 | 不限帧（余量） | 509 / 532 / 555 | 1.64–1.66 / 2.65–2.87 / 3.26–3.74 ms | 1.87–1.91 ms | 530 | 余量约 8.5 倍 |
| 1280×720 | 不限帧（余量） | 863 / 878 / 904 | 0.98–1.00 / 1.72–1.84 / 2.50–2.61 ms | 1.28–1.32 ms | 530 | 余量约 14 倍 |

“不限帧”一行是人为取消引擎帧率上限后的吞吐量与帧成本，用来证明**余量**；玩家实际体验对应“60（发布设置）”两行。
两组的 `max` 分别是 12.9–68.8 ms（1080p）与 12.2–33.7 ms（720p），都是每次相位/进房后的首帧一次性成本，
不是稳态值，第 8 节单独说明；判据只看 p95/p99 与平均 FPS。

## 2. 环境事实（实测，非声称值）

| 项目 | 实测值 |
| --- | --- |
| GPU | **NVIDIA GeForce RTX 3050**（不是 README 里旧的 GTX 1660 SUPER 描述） |
| 图形 API | Vulkan 1.4.325，Forward+（`forward_plus`），`RenderingServer.get_rendering_device().get_device_name()` 读取 |
| CPU / 内存 | 12th Gen Intel(R) Core(TM) i7-12700F |
| 系统 / 桌面 | Windows；屏幕 1920×1080，`screen_scale = 1.0`，`screen_dpi = 96` |
| 引擎 | Godot 4.7.2.stable.official（hash `ed1daf0bf001b61586d9930840f2f1394092c079`），`debug_build = true`，`editor_feature = true` |
| 工程设置 | `run/max_fps=60`；`window/size/viewport=1920×1080`；`window_width_override=1280`、`window_height_override=720`；`stretch/mode="canvas_items"`；`physics_ticks_per_second=60` |
| 采集时引擎运行方式 | 从源码工程（`--path godot`）以编辑器二进制运行，**不是导出包**。编辑器构建带有调试检查与完整资源热加载路径，因此数据是保守下界 |

**重要限定：**以下所有数字都是“编辑器二进制 + 脚本 bot 输入”的实测，不能等同于导出包表现，也不能替代人工手感；
导出包上的复测属于 T10 的验证范围（见第 11 节）。

## 3. 采集命令（可复现）

工作目录 `D:\game\StarAbyss`，引擎 `G = D:\game\apps\godot\Godot_v4.7.2-stable_win64_console.exe`（控制台版用于抓 stdout）：

```powershell
$env:APPDATA='D:\game\StarAbyss\.local\appdata'
$env:LOCALAPPDATA='D:\game\StarAbyss\.local\localappdata'

# A. 既有套件基准：1920×1080，真实图形模式，不限帧，完整三房 + Boss 真实输入战斗
& $G --path D:\game\StarAbyss\godot --resolution 1920x1080 --disable-vsync `
    --log-file D:\game\StarAbyss\.local\validation\performance_1080p_run1.log `
    --script res://tests/performance_benchmark.gd -- --label=1080p-run1 --rounds=1

# B. 探针：1920×1080，帧率上限 60（= 玩家实际体验）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=1080p-capped60 --resolution=1920x1080 --fps=60 --rounds=1

# C. 探针：1280×720，帧率上限 60
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=720p-capped60 --resolution=1280x720 --fps=60 --rounds=1

# D. 探针：1280×720，不限帧（余量）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --label=720p-uncapped --resolution=1280x720 --fps=0 --rounds=1

# E. 渲染目标尺寸事实核查（不开游戏流程，只打印窗口/视口/纹理尺寸）
& $G --path D:\game\StarAbyss\godot --disable-vsync `
    --script ../tools/performance_probe.gd -- --mode=info --resolution=1280x720
```

`tools/benchmark.ps1` 已同步改为可由 Windows PowerShell 5.1 运行，并可一次产出上述 A–D 的任意组合（见其 `-help`）。

### 采样方式

- **真实窗口 + 持续渲染**：不使用 `--fixed-fps`、不使用 `--disable-render-loop`、不使用 `Dummy` 音频驱动；
  窗口真实打开并独占前台，采集期间不触碰窗口与鼠标（外部鼠标位移会污染注入的输入与采样）。
- **帧时间**：`Time.get_ticks_usec()` 逐帧墙钟差值（wall_ms），即玩家真实体验的帧间隔。
- **GPU / CPU 渲染时间**：`RenderingServer.viewport_get_measured_render_time_gpu/cpu` +
  `RenderingServer.get_frame_setup_time_cpu()`（需先用 `viewport_set_measure_render_time(true)` 开启）。
- **引擎监视器**：`Performance.get_monitor()` 的 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`、
  `RENDER_TOTAL_PRIMITIVES_IN_FRAME`、`OBJECT_NODE_COUNT`、`OBJECT_RESOURCE_COUNT`、`OBJECT_COUNT`、
  `MEMORY_STATIC`、`RENDER_VIDEO_MEM_USED`、`TIME_PROCESS`、`TIME_PHYSICS_PROCESS`。
- **样本剔除**：每个相位的前 30 帧不计入（着色器/首绘一次性成本）；暂停中的模态相位（祝福选择）不计入。
- **样本量**：探针每个战斗相位 146–2086 帧（60 FPS 下 2.4 s–35 s 不等）；不限帧运行每相位 1491–27055 帧。
- **逐相位**：`menu`（主菜单）、`initial_transition`（点击开始到进入首房）、`room_1_combat`（2 哨兵）、
  `room_1_traversal`（走门）、`room_2_combat`（3 哨兵）、`room_2_traversal`、`boss_combat`（晶核守卫）。

## 4. 指标判读规则（为什么不能只看 FPS）

1. 项目设置 `run/max_fps=60`，所以“平均 FPS 60.0”只能证明**没有掉到 60 以下**，不能证明余量；因此每组条件同时采
   “帧率上限 60”和“不限帧”两种，后者衡量余量。
2. 帧率上限开启时会出现一个反直觉现象：**`> 16.67 ms 的帧占比约 50%`**。原因是帧限速器按睡眠对齐，帧间隔在
   16.66–16.70 ms 之间抖动，一半样本恰好越过 16.67 ms。因此本文件**不使用该比例作为掉帧判据**，而使用
   “平均 FPS + p95/p99 + max 孤立长帧”三项。
3. 掉帧判据（本次采用）：平均 FPS ≥ 59.5，p95 ≤ 20 ms（≈1.2 帧预算），p99 ≤ 25 ms，且长帧必须是**孤立单帧**
   （可通过 max 与 p99 的巨大差值识别），不存在连续多帧超预算。
4. `Performance` 的部分监视器（process/physics/object/VRAM）在 Godot 里最多延迟约 1 秒刷新，其“最大值”只作
   参考，不当逐帧分位数使用；逐帧结论只用帧时间与 `viewport_get_measured_render_time_*`。

## 5. 1920×1080 实测数据

### 5.1 帧率上限 60（`--fps=60`，= 发布设置下的玩家体验）

命令 B。`wall_ms` 单位毫秒；`gpu_p95` / `cpu_render_p95` 为渲染线程测量值；`draws_p95` 为每帧 draw call。

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 121 | 60.0 | 16.67 | 16.74 | 16.80 | 16.97 | 0.08 | 0.23 | 40 |
| initial_transition | 26 | 44.0 | 16.61 | 17.18 | 199.36 | 199.36 | 2.77 | 1.23 | 417 |
| room_1_combat（2 哨兵） | 147 | 59.6 | 16.69 | 17.95 | 19.96 | 34.11 | 2.53 | 0.85 | 411 |
| room_1_traversal | 239 | 60.0 | 16.66 | 17.31 | 17.84 | 30.60 | 2.37 | 0.58 | 314 |
| room_2_combat（3 哨兵） | 363 | 59.9 | 16.66 | 17.46 | 18.46 | 37.29 | 2.38 | 0.83 | 530 |
| room_2_traversal | 220 | 60.0 | 16.67 | 17.07 | 17.54 | 33.44 | 2.39 | 0.57 | 328 |
| boss_combat（350 HP 守卫） | 1719 | 60.0 | 16.67 | 17.38 | 17.96 | 30.21 | 2.52 | 0.73 | 434 |

`initial_transition` 的 199 ms 与各相位 max 列的 30–38 ms 是场景切换/首帧成本，见第 8 节。

### 5.2 不限帧（余量测量）

命令 A（既有套件，含 12 项功能断言，本轮 12 checks / 0 failures）。

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 6045 | 3021.8 | 0.29 | 0.59 | 0.81 | 2.74 | 0.07 | 0.04 | 40 |
| initial_transition | 245 | 62.1 | 1.74 | 3.31 | 6.88 | 3548.06 | 2.64 | 0.86 | 417 |
| room_1_combat（2 哨兵） | 1491 | 509.2 | 1.66 | 2.75 | 3.74 | 68.81 | 1.87 | 0.63 | 449 |
| room_1_traversal | 2548 | 575.4 | 1.59 | 2.52 | 3.04 | 13.41 | 1.88 | 0.48 | 373 |
| room_2_combat（3 哨兵） | 3469 | 531.9 | 1.66 | 2.87 | 3.72 | 17.10 | 1.90 | 0.71 | 530 |
| room_2_traversal | 2266 | 551.3 | 1.61 | 2.78 | 3.59 | 18.48 | 1.86 | 0.68 | 347 |
| boss_combat（350 HP 守卫） | 16512 | 555.4 | 1.64 | 2.65 | 3.26 | 12.88 | 1.91 | 0.58 | 434 |

同一相位内功能断言全部通过：真实主菜单点击开始、真实输入 bot 打完 2+3 哨兵与 350 HP Boss、
3 房 / 6 击杀 / 3 房清场统计正确（本轮 1 局）。**即：这些帧率是在真实战斗、真实物理、真实命中判定下产生的，
不是空场景待机数据。**

## 6. 1280×720 实测数据

### 6.1 帧率上限 60（命令 C）

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 121 | 60.0 | 16.67 | 16.72 | 16.75 | 16.76 | 0.04 | 0.15 | 40 |
| initial_transition | 28 | 47.4 | 16.71 | 17.24 | 164.86 | 164.86 | 2.06 | 0.82 | 417 |
| room_1_combat（2 哨兵） | 146 | 59.5 | 16.67 | 17.48 | 19.47 | 38.35 | 1.52 | 0.76 | 401 |
| room_1_traversal | 239 | 60.0 | 16.67 | 17.33 | 17.61 | 28.34 | 1.48 | 0.68 | 314 |
| room_2_combat（3 哨兵） | 363 | 59.9 | 16.64 | 17.63 | 19.46 | 34.31 | 1.51 | 0.94 | 530 |
| room_2_traversal | 220 | 60.0 | 16.66 | 17.40 | 17.92 | 37.15 | 1.50 | 0.77 | 328 |
| boss_combat（350 HP 守卫） | 2086 | 60.0 | 16.66 | 17.66 | 18.18 | 27.03 | 1.61 | 0.89 | 434 |

### 6.2 不限帧（命令 D）

| 相位 | 样本 | 平均 FPS | p50 | p95 | p99 | max | gpu_p95 | cpu_render_p95 | draws_p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 10269 | 5134.2 | 0.16 | 0.36 | 0.58 | 1.54 | 0.03 | 0.04 | 40 |
| initial_transition | 509 | 895.5 | 0.94 | 1.58 | 2.05 | 161.41 | 1.29 | 0.33 | 417 |
| room_1_combat（2 哨兵） | 2539 | 863.0 | 0.99 | 1.84 | 2.61 | 33.72 | 1.30 | 0.44 | 449 |
| room_1_traversal | 4303 | 967.1 | 0.94 | 1.56 | 2.26 | 13.93 | 1.21 | 0.36 | 373 |
| room_2_combat（3 哨兵） | 5735 | 878.0 | 1.00 | 1.84 | 2.50 | 18.22 | 1.32 | 0.44 | 530 |
| room_2_traversal | 3987 | 964.6 | 0.95 | 1.56 | 2.22 | 16.05 | 1.18 | 0.36 | 347 |
| boss_combat（350 HP 守卫） | 27055 | 904.5 | 0.98 | 1.72 | 2.51 | 12.24 | 1.28 | 0.44 | 434 |

## 7. 渲染负载与内存（逐相位）

draw call 与 primitive 数在两种分辨率下**完全一致**（同一批场景/材质/网格），说明这两个指标由场景内容决定，
与分辨率无关。内存取自 `Performance.get_monitor()`，单位为 MB；`MEMORY_STATIC` 是静态分配量，
`RENDER_VIDEO_MEM_USED` 含纹理/渲染目标/管线。

| 相位 | primitives max / p95 | draw calls max / mean / p95 | 节点 max | 资源 max | 对象 max | MEMORY_STATIC max (MB) | 显存 max (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| menu | 1,662 / 1,662 | 40 / 40 / 40 | 18 | 214 | 1,809 | 81.4 | 66.5 |
| room_1_combat（2 哨兵） | 140,010 / 132,593 | 455 / 365 / 411 | 269 | 275 | 2,386 | 105.2 | 193.4 |
| room_1_traversal | 145,458 / 114,840 | 471 / 278 / 314 | 298 | 275 | 2,410 | 105.6 | 195.0 |
| room_2_combat（3 哨兵） | 161,655 / 156,456 | 583 / 386 / 530 | 309 | 275 | 2,438 | 105.9 | 195.0 |
| room_2_traversal | 119,468 / 115,430 | 351 / 259 / 328 | 262 | 276 | 2,359 | 106.5 | 195.2 |
| boss_combat（守卫） | 138,340 / 132,406 | 462 / 381 / 434 | 222 | 276 | 2,310 | 106.3 | 195.2 |

上表为 1920×1080 运行（上限 60）。1280×720 的对应数值：节点 max 306、对象 max 2,455、`MEMORY_STATIC` max 110.1 MB、
显存 max 167.6 MB、draw call/primitives 与上表一致（583 / 161,655 峰值同样出现在 3 哨兵房）。

不增长性：进程内节点数在每次开局为 238（`nodes_at_run_start=[238]`），整局峰值 308–309，Boss 房反而回落到 222
（哨兵尸体已被清理）；`OBJECT_COUNT` 峰值 2,438–2,455，未出现随战斗时长单调上升的趋势；显存在进场后稳定在
193–195 MB（1080p）/ 166–168 MB（720p），没有逐帧增长。**未观察到内存泄漏式增长。**

## 8. 长帧与抖动分析

### 8.1 稳态抖动：没有掉帧，只有孤立单帧

- 上限 60 时 p95 = 17.1–18.0 ms、p99 = 17.5–20.0 ms，即 99% 的帧都在 1.2 帧预算内。
- max 出现在 27–38 ms，但 p99 只有 18–20 ms，说明这些是**孤立单帧**（约 2 帧长度），不是连续卡顿；
  全部落在相位切换后的前几秒，与 `physics_monitor_ms_max_observed`（12–49 ms）同源，
  是引擎物理回调 + 新一轮场景/材质首次使用的一次性成本。整局只出现个位数次。
- CPU 渲染线程 p95 仅 0.57–1.23 ms，物理与脚本没有进入帧预算紧张区间。

### 8.2 一次性首次编译停顿（真实存在，需要人工复核）

第一次点击“开始”进入游戏时，**首帧墙钟 3548 ms**（`initial_transition.wall_ms_max`，`process_monitor` 同时报 3533 ms，
物理只有 5.9 ms，说明停顿发生在主线程场景加载/首绘）。同一天后续运行（引擎着色器与 Vulkan 管线缓存已生成）同一位置为
**165–200 ms**：

| 运行 | 冷/暖 | initial_transition max |
| --- | --- | --- |
| 12:46 首次图形运行（当日第一次启动） | 冷（`%APPDATA%\Godot\app_userdata\...\shader_cache` 与 `vulkan\pipelines.forward_plus.nvidia_geforce_rtx_3050.cache` 为首次生成） | 3548 ms |
| 12:50 / 12:51 后续运行 | 暖 | 199 ms / 165 ms |

结论与边界：这是 Godot 首次使用的着色器/管线编译 + 场景资源加载，**每个进程生命周期只发生一次**（不是每局、不是每房）；
暖缓存下约 0.2 s，可接受。冷缓存 3.5 s 属于“首启动可见停顿”，本次未优化（改动涉及预加载/预热策略，属于行为变更，
不在“实测达标就不动代码”的范围内）。**建议 T10 在真实导出包上复测一次**：导出包若包含着色器/管线缓存，该停顿会显著缩短；
若仍为秒级，则应作为 T9 缺陷候选另行处理（冷启动无反馈的秒级卡顿影响首发体验）。

### 8.3 有没有分配尖峰

`OBJECT_COUNT` 与 `OBJECT_RESOURCE_COUNT` 在整局中为平台型（1,809 → 2,310–2,455，随后回落），
未见锯齿式反复增长；`MEMORY_STATIC` 峰谷差 < 25 MB 且由房间切换导致（旧房间释放、新房间加载）。
战斗中的逐帧分配未观察到导致帧时间抖动的证据（p99 与 p95 只差 0.5–2 ms）。

## 9. 分辨率事实核查：窗口尺寸 vs 渲染目标

这一节是为了避免“我测的到底是窗口还是渲染分辨率”含糊不清。用 `--mode=info` 直接读取引擎 API（命令 E）：

| 项目 | 1920×1080 运行 | 1280×720 运行 | 1280×720 + 关闭 stretch（对照） |
| --- | --- | --- | --- |
| `DisplayServer.window_get_size()`（真实窗口） | 1920×1080 | 1280×720 | 1280×720 |
| `Window.size` | 1920×1080 | 1280×720 | 1280×720 |
| `Window.get_texture().get_size()`（引擎报告的根纹理） | 1920×1080 | **854×480** | 1280×720 |
| `get_visible_rect().size`（2D 逻辑坐标） | 1920×1080 | 1920×1080 | 1280×720 |
| `content_scale_mode` / `content_scale_size` | 1 (canvas_items) / 1920×1080 | 1 / 1920×1080 | 0 (disabled) / 1280×720 |

事实：发布设置下 1280×720 窗口使用 `canvas_items` 拉伸（设计分辨率 1920×1080），引擎报告的根纹理尺寸是窗口的
1/1.5（854×480）；把 stretch 关掉后立刻变回 1280×720。**因此“1280×720 窗口”的 3D 光栅化分辨率无法仅凭
`get_texture()` 断言**（该值显然是按 canvas 缩放折算后的结果，与 `visible_rect` 不自洽）。

对性能结论的影响：可以忽略。同一相位在 854×480 报告值与 1920×1080 之间，GPU 帧时间 p95 只从 1.90 ms 降到 1.32 ms
（约 1.44 倍），而像素量差 5.06 倍——**说明本作的帧成本由 draw call（270–583）与几何提交（10.5 万–16.2 万 primitive）
主导，不是像素填充率主导**。即使真实光栅分辨率是窗口的 1280×720，按上述比例也与结论方向一致：
两种配置都远在 60 FPS 预算之内。

对画质的影响：留待人工判定。已在团队内提示 art/QA 在 720p 截图取证时对比地砖纹理与描边锐度，
若确认为画质缺陷，按 T9 流程处理（不属于性能任务，也不在本次改动范围内）。

## 10. 为什么不做优化（逐项排除）

本次测量没有发现需要优化的瓶颈，因此**没有改动任何渲染/阴影/后处理/材质/导入参数，也没有改代码**。逐项依据：

| 候选瓶颈 | 实测证据 | 判定 |
| --- | --- | --- |
| GPU 像素填充 | GPU 帧时间 p95 1.90 ms（1080p）/ 1.32 ms（720p），相对 16.67 ms 预算余量 8–12 倍 | 未饱和，无需降低分辨率/关阴影 |
| GPU 几何/draw call | 峰值 583 draw calls、16.2 万 primitives；同期 GPU p95 仍 1.9 ms | 未饱和，不需要合批/实例化改造 |
| CPU 渲染线程 | `viewport_get_measured_render_time_cpu` + frame setup p95 = 0.57–1.23 ms | 未饱和 |
| 脚本/物理 | `TIME_PROCESS` 观测最大 4.0–7.2 ms（含 1 秒延迟刷新误差），`TIME_PHYSICS_PROCESS` 稳态 12–20 ms 且为相位切换瞬时值；物理 60 Hz 下未见持续超预算 | 未见需要削减的每帧开销 |
| 内存/资源 | `MEMORY_STATIC` ≤ 110 MB，显存 ≤ 195 MB，节点/对象平台型不增长 | 无需减少资源常驻 |
| 帧时间抖动 | p99 ≤ 20 ms，长帧为孤立单帧且集中在切换后 | 无持续掉帧可修 |

唯一值得记录的异常是第 8.2 节的一次性冷编译停顿，它属于加载路径而非帧开销，且修复手段（预热/预加载/加载界面）
会改变启动行为与 UI，超出“最小、可回滚的渲染优化”范围，因此**留作已知限制 + 建议在导出包上复测**，
不在本任务中改代码。

## 11. 测量边界与未验证事项

1. **编辑器二进制，不是导出包**。`debug_build = true`、`editor_feature = true`；导出包通常更快，但也可能因缺少
   `shader_cache` 而在首启动变慢。**导出包性能未测**（T4/T10 范围）。
2. **脚本 bot 输入**。bot 使用真实 `Input` 动作、真实 FSM/Hitbox/物理，但瞄准与走位由脚本决定，
   因此不等于人工操作下的帧分布，也不构成手感结论。
3. **音频集成时点**：本轮采集（2026-10-23 12:46–12:51）与 art 的音频接线（`scripts/audio/actor_audio.gd` 12:48:21、
   `audio_cues.gd` 12:49:41、`run_audio.gd` 12:51:58 → 12:52:08，`assets/audio` 的 27 个 wav 导入 12:50:56）
   **在时间上交错**，因此这里的数字不代表音频全部接入后的最终状态。证据：`performance_probe_720p-capped60.log`
   在 12:51 出现 `SCRIPT ERROR: Parse Error: Function "_set_ambience_cue()" not found in base self.`
   （`res://scripts/audio/run_audio.gd:160`）——那是 art 正在改文件的中间态，该次运行等于**完全没有音频**；
   其余三次运行的日志无该错误，但它们发生在新 wav 导入之前，同样不是最终内容。
   **结论：音频接入后必须复测一次**（同一组命令，约 2.5 分钟）。这一点在文档里如实声明，不用这轮的 CPU/内存数字
   去声称“包含 27 路音频并发”。
4. **单局 1 轮**：性能运行每条件 1 局（约 52–58 s 墙钟，含 3 房 + Boss）。连续多局长时运行（soak）未做，
   长时间稳定性属于 QA/发布验证范围。
5. **单一硬件**：仅本机 RTX 3050 / i7-12700F / 1920×1080 屏幕 / Windows。无其他 GPU、无 4K、无 144 Hz、
   无 macOS/Linux 数据。
6. **播放器/暂停相位未单独采样**：祝福选择为暂停模态，本任务未把它计入性能相位。
7. 第 9 节的“真实 3D 光栅分辨率”未由引擎 API 证明，仅给出可复核的原始读数；画质影响待人工判定。

## 12. 原始产物清单

均在 `StarAbyss/.local/validation/`（不提交版本库）：

| 文件 | 内容 |
| --- | --- |
| `performance_1080p-run1.json` / `.output.txt` / `performance_1080p_run1.log` | 命令 A：既有套件基准，1080p 不限帧，12 checks / 0 failures |
| `performance_probe_1080p-capped60.json` / `.log` / `.stdout.txt` | 命令 B：1080p 上限 60 |
| `performance_probe_720p-capped60.json` / `.log` / `.stdout.txt` | 命令 C：720p 上限 60 |
| `performance_probe_720p-uncapped.json` / `.log` | 命令 D：720p 不限帧 |
| `probe_info_1280x720.txt` / `probe_info_1920x1080.txt` | 命令 E：窗口/视口/纹理尺寸原始读数 |

复现建议：以上命令必须**独占桌面窗口**，采集期间不要移动鼠标或点击窗口（注入的鼠标事件会被原生位移污染）；
同时不要与其它引擎进程并行运行（共用 `.godot` 缓存会导致引擎崩溃）。
