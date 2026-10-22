# 当前技术架构 / P6 美术替换

P6 在现有三房闭环上接入本项目 Blender 低多边形资产、骨骼动画与 Toon 材质。玩法、状态切换、碰撞和导航沿用 P2–P5；无新增插件、Autoload、下载或 Blender/MCP 运行依赖。以下 P6 内容为当前行为，后面的 P5–P1 内容保留作玩法架构与历史记录。

## P6 资产与运行时外观

`tools/build_character_assets.py` 与 `tools/build_environment_assets.py` 使用本机 Blender 5.2.2 独立后台进程，从新场景重建七份 `.blend` 与七份 GLB，不修改用户交互 Blender。源分别放 `blender/characters`、`blender/enemies`、`blender/environments`，运行时放 `godot/assets/models/characters` 与 `environment`。源资产以米为单位，应用缩放，角色 Blender +Y 对应 Godot -Z。静态武器根变换为单位变换，原点位于握点；导入元数据与 `.gd.uid` 保留，`.godot/` 仍忽略。

探索者目标1.75m、哨兵1.65m、守卫2.6m，三者复用18骨命名约定，采用显式蒙皮权重。金属甲片使用刚性分段权重，避免橡胶式金属变形；不包含面部表情、IK或布料模拟。三角色合计48个动画片段（14/14/20），共用 Idle、Run、Jump、Fall、Dodge、Attack_01/02/03、Skill_01、Hurt、Death；敌人另含整段Attack，Boss另含整段Attack_Sweep/Attack_Shockwave。独立Telegraph/Recover片段用于资产预览，运行时连续采样完整动作。所有Root平移静止，代码继续独占角色位移。

ActorPresentation为Visual下的普通Node3D，只读取已有FSM/Combat/Brain和Health，不决定动作、伤害或移动。其_ready先实例化模型与独立武器，再让父角色后续Feedback._ready扫描到蒙皮网格，因此原闪白仍生效。WeaponSocket通过BoneAttachment3D绑定；武器基变换取骨全局rest basis的逆，抵消导入器轴向差异，再乘导出的可调艺术旋转偏移。三角色旧Body/Head等节点和WeaponPivot保留路径但隐藏，CombatVisual只继续绘制判定扇形，不二次驱动正式武器。

AnimationPlayer使用MANUAL回调。玩家攻击/技能按combat.elapsed、闪避按dodge_elapsed，敌人/Boss整段攻击按brain.action_elapsed直接seek，不按动画结束信号触发玩法。外观物理优先级10，晚于默认motor；即使命中回调在本帧开启Hit Stop，也先采样本帧已推进的权威时间，后续冻结帧重复同一姿势。Idle/Run等本地循环才消费delta。存活外观在SceneTree暂停时完全冻结；died信号同步切到Death零时刻，只有死亡外观通过Always模式在结算面板后继续倒地，不能推进AI、战斗、冷却或本局用时。旧FSM/motor的整Visual旋转倾倒仅在无外观组件时保留，防止骨骼倒地叠加旋转。

## P6 Toon与环境

ToonPalette为静态材质转换工具，不是Autoload；按GLB源材质名/颜色/发光/描边选项缓存ShaderMaterial，不把运行态写回导入材质。cel_surface以三档直射明暗、冷色暗部、无镜面和克制发光分色；cel_outline以反向外壳绘制角色/武器细边，默认宽0.008m。环境不加外壳描边，依赖几何倒角、砖缝与材质分区。自定义light只输出光照贡献，底色由Godot最终合成，避免重复乘底色。[着色器接口参考](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。色值/重建与资产参数见ART_STYLE.md和两个manifest。

ruins_arena.tscn继承原arena_geometry.tscn，仅隐藏旧Mesh/Markings/NorthLabel，加入ruins_dressing；combat_room改引用此视觉变体。40×40地面、四墙、双柱、低台/台阶/高台的StaticBody和CollisionShape完全保留，两份导航无需重烘焙。环境GLB的七网格模块不含碰撞或NavigationRegion；地砖表面高出原地面4mm，平台顶面仍1m/2m。原门的屏障、门槛、字幕与逻辑保留，只隐藏与GLB共面的旧门柱/横梁。P2/P3训练场继续使用灰盒环境；P4 room_run独立阶段夹具保留，角色与正式房间可共享新外观。

## P6 验证边界

art_validation_test检查实际蒙皮绑定、所有动画根骨/骨变换、必需片段、七招完整时长和生效期五点武器轨迹，以及时钟/Hit Stop/暂停/死亡、旧碰撞保留和Forward+真实帧。三段/技能/哨兵/横扫的刀尖或锤头穿过前方扇形，边缘允许5°测量容差；冲击生效锤头约0.26m高。视觉动作不是连续刀刃碰撞：普通剑尖物理半径约1.1–1.5m，小于2.2m普攻扇形，哨兵/守卫也有美术半径与Gameplay范围差；距离真值仍由地面Arc和Hitbox的Resource显示/执行，不宣称刀尖覆盖整个伤害区。技能5m与冲击4.2m本就为能量范围。

原447项与新增97项不同断言均验收，连续三局真实输入闭环和两种分辨率截图重新运行。自动采样/截图不能替代人工美术认可、动作过渡手感或性能。完整命令、日志、人工步骤见TESTING.md；P7音效/VFX、性能与导出仍等待授权。

# P5 Boss 与闭环（保留架构）

玩法基线：[Star_Abyss_GDD_v1.0.md](Star_Abyss_GDD_v1.0.md)。当前完成 P5 两招 Boss、主菜单、三房胜负、重开和返回菜单，保留 P0–P4 独立场景与回归。正式美术仍属 P6。运行时使用 Godot 4.7 stable、GDScript、Forward+ / Vulkan、GodotPhysics3D，60 Hz 物理更新。无插件、Autoload 或运行时 Blender 依赖。

## P5 场景闭环

默认入口 main_menu.tscn（MainMenu）。点击开始使用 change_scene_to_file 进入 game_run.tscn；该场景继承 P4 room_run.tscn，只将第三份 RoomDefinition 替换成 room_boss.tres。原 room_run 保留 boss_staging 阶段终点供 P4 回归，F5 正式流程使用 boss_room，不停在旧阶段摘要。

MainMenu 仅负责标题、操作提示和场景切换，_starting 防止重复开始；没有保存运行数据。RunManager 在 Boss 房仍进入 Combat，Boss 死亡进入新增 Won，计 3 房/6 击杀，不触发第三次祝福或生命共鸣普通击杀回血。Failed/Won 不允许 resume；暂停、失败、胜利均可重载当前场景或返回菜单。返回菜单先解除 Tree 暂停，再切换场景；新开局重新创建玩家、房间、计数、RNG 和祝福组件。无 GameSession Autoload 或跨场景可变单例。

RoomController 持有普通 enemies 与独立 boss 引用。Boss 通过单独 boss_defeated 信号结算；普通敌人 death 路径保持不变。Boss 血条、招式提示由 Health/Brain → Room/RunManager 信号 → RunUI 更新，UI 不修改生命与战斗状态。

## P5 守卫状态与数据

GuardianBrain 继承 EnemyBrain，复用追击、可达性、绕障、归巢、攻击/恢复/死亡和目标死亡清理；每个守卫仍持有独立 FSM 运行态。仅覆盖招式选择、当前攻击定义和间隔策略。EnemyBrain 新增两个小查询入口 get_attack_definition/get_attack_cooldown，普通哨兵仍返回原 Resource，不复制导航或伤害实现。运动继续由现有 SentinelController 执行，因此 Boss 没有额外运动逻辑层。

GuardianSettings 继承 SentinelSettings，HP350、速度2.6、检测/归巢30、触发2.5、等待3.6。Boss 的 stagger_duration=0：普通命中仍扣血、闪白和局部 Hit Stop，但不会无限受击打断。死亡始终最高优先级，并清空 Hitbox、扇形、名额和实体/受击碰撞。未实现 GDD 可选的 70% HP 提速。

| 动作 | 伤害 | 预警 | 生效 | 恢复 | 形状 |
| --- | --- | --- | --- | --- | --- |
| 重锤横扫 | 20 | 0.8 s | 0.22 s | 0.65 s | 2.8 m / 130°，锁方向 |
| 晶能冲击 | 25 | 1.2 s | 0.2 s | 0.8 s | 守卫为圆心，半径4.2 m / 360° |

HP、速度、伤害、预警和招式间隔采用 GDD；范围、生效/恢复、普通命中无硬直及轮换策略为首轮实现补充，集中于 resources/boss。首招由本局种子决定，随后两招轮换；间隔由同一局部 RNG 均匀采样1.6–2.4秒。完整间隔在恢复实际结束后起算，避免 Hit Stop 延长动作但基础冷却继续计时而挤掉间隔；追近所需时间额外计入，不保证两个预警起点只相隔1.6–2.4秒。

圆形沿用同一 AttackDefinition 的360°扇形：Hitbox 精确过滤全圆距离、垂直差和 World 视线，WeaponVisual 根据该定义绘制24段圆盘，橙色为预警、红色为生效，不另设第二份危险区。AttackDefinition 的 Inspector 角度范围扩大至360°。每动作新 DamageInfo ID，单目标只结算一次。圆心和朝向在预警发起时固定，走出危险区可免伤。几何锤和圆盘仍是灰盒表现，不是 P6 正式动画。

Boss 场景继承哨兵组件，单独设置0.65 m半径/2.6 m高实体及Hurtbox、4.5 m候选球，身体/锤子单独缩放，不缩放 Hitbox 或危险圆盘父节点。Boss 房加载 guardian_arena_navmesh.tres，离线烘焙半径0.75、高2.75（匹配0.25体素单位），62多边形，Agent.path_height_offset仍为0.5。原哨兵网格不变。`tools/bake_navigation.gd -- --guardian` 生成 Boss 网格；共享几何变动时两份都需重烘焙。

## P5 同步结算保护

Boss 的致死命中同步触发 Won 并 interrupt 玩家动作。PlayerCombat.advance_action 在 Hitbox.sample 返回后重新检查 current_attack，防止致胜回调清空动作后继续访问时长。Hitbox 与敌人 FSM 原有同步回调保护保留。胜负只结算一次；玩家已失败时，迟到的 Boss 死亡不会覆盖为胜利。完整三局图形验收覆盖真实致胜一击，而非只用直接扣血模拟结算。

以下 P4 架构为保留夹具的历史细节；正式入口与第三房行为以上述 P5 为准。

## P4 场景与职责

默认主场景为 room_run.tscn。RunManager、BlessingManager 和 RunUI 都是该场景的普通节点，不是全局单例。原 P2/P3 训练场及测试入口保留。

| 组件 | 职责 |
| --- | --- |
| RunManager | 固定顺序、当前房间、清场/击杀/用时、种子、暂停/选择/失败/阶段结算状态与场景重载 |
| RoomController | 按 RoomDefinition 生成哨兵，订阅单次死亡、敌人计数、清场和开门；不应用祝福 |
| RoomGate | 橙色实体屏障、青色门框、玩家 Area3D 门槛；每房发出一次通行信号 |
| BlessingManager | 本局 RNG、去重候选、持有集合、统一效果应用/撤销、获得与击杀回血 |
| BlessingDefinition / RoomDefinition | 只读元数据和参数，不保存获得状态、HP 或运行计时 |
| RunUI | 通过 Signal 更新 HUD、祝福卡、暂停和结算；按钮仅请求 Manager 操作 |

```text
RoomRun (RunManager / Always)
  Player (Pausable)             跨房间复用同一玩家及 HP/冷却
  BlessingManager
  RunUI (CanvasLayer / Always)  暂停中仍能操作
  CombatRoom (Pausable)         每次进房替换
    NavigationRegion3D / Geometry
    AttackCoordinator / Enemies
    ExitGate (RoomGate)
```

三个 RoomDefinition 依次为遗迹前庭（2 名哨兵）、星辉回廊（3 名）、晶核封印（Boss staging，无敌人）。均复用已有 arena_geometry.tscn 和其静态导航，当前差别为标题与出生点；尚未制作三个独立美术布局。出口为房内北侧 z=-16 的能量门，门槛通行后切换房间，并非无缝地图。门不改变旧训练场几何，无需重新烘焙旧导航。动态屏障只用于清场出口，战斗出生点与追击范围位于门前。

RoomController 在实例进入树前接收 definition/player，给 EnemyBrain 设置玩家和场景内协调器的绝对 NodePath，再添加哨兵。单次死亡从存活集合删除后才发出击杀与清场信号；只有 DamageInfo.source 为玩家的死亡计作玩家击杀/生命共鸣回血。旧房间先移出树、释放名额和导航区域再延迟销毁，随后加载新房，避免重叠导航区域。

## P4 状态、暂停与输入

Combat → Choosing → Exploring → Transition → 下一房 Combat；第三房进入 StageComplete。存活战斗/探索可进 Paused，再回原状态；玩家死亡进入 Failed。Choosing 不能用 Esc 退出，Failed/StageComplete 只能重新开始。门通行同时验证 Exploring、当前清场和有效后继房间，即使绕过实体屏障也不能跳过战斗或选择。Boss staging 不触发普通房清场奖励，不增加 rooms_cleared，不计作 Boss 胜利。

RunManager/RunUI 使用 Always，Player/CombatRoom 显式 Pausable，避免继承根节点 Always 而在弹窗中继续战斗。暂停、失焦、祝福与结算设置 SceneTree.paused，冻结角色、HP 保护计时、AI、冷却、协调器和本局用时；用时只在 Combat/Exploring 累积。Esc 在 Manager._input 消费，早于摄像机的 _unhandled_input。恢复时调用 PlayerController.suppress_action_input，屏蔽弹窗关闭时仍按住的动作；相机原有鼠标首位移保护保留。未将玩家状态判断移入 Controller。

跨房间终止当前动作、清空速度并重置出生位置/面向；HP、祝福、保护和现有冷却保留。重开通过 reload_current_scene 创建所有新组件，清空 HP、祝福、冷却、名额、清场数和击杀计数；默认新种子。Inspector 的 run_seed=-1 使用时间/单调时钟生成种子；非负值让候选顺序可复现，HUD 与结算展示 active_seed。局内 RNG 仅由 BlessingManager 持有，不调用全局 shuffle。

## P4 祝福效果

- 三个 BlessingDefinition Resource 存 id、localization_key、中文名称/描述、文字图标、配色与效果参数。候选按未获得 ID 去重，以本局 RNG 做 Fisher–Yates 排序，最多三项；第二次只剩两项。提交后清空 pending，拒绝未提供 ID、重复选择与死亡后选择。
- 烈焰：PlayerCombat.normal_attack_multiplier 运行值 ×1.20；普通 DamageInfo 将其乘入统一伤害公式，技能不乘该值。正常三段为 14/19/29，技能仍为 35，基础 attack_multiplier 继续共用。
- 疾风：FSM.dodge_cooldown_multiplier 改变下一次发起闪避的冷却为 0.9；不改运动 Resource、距离、时长或无敌窗口，不追溯重写现有计时。
- 生命：获得时 Health.heal(20)，之后玩家击杀普通敌人时 heal(5)；依赖共享组件封顶和禁止复活。获得前的击杀不补发回血。
- clear 根据初始化时快照恢复倍率并撤销未来击杀回血；已恢复的生命不会倒扣。正常重开创建全新玩家/Manager，避免共享 Resource 污染。

P4 复验还修复了 CombatFeedback 先创建 AudioStreamPlayer3D 再延迟挂接的生命周期问题：现在在延迟回调中分配并挂接，退出树时停止/释放音频流，避免同帧销毁遗留无父节点。Godot 音频服务异步删除播放实例，验收退出前另外保留 200 ms 实际时间进行回收；这不属于游戏计时或性能数据。相关引擎行为见 [Godot #76745](https://github.com/godotengine/godot/issues/76745)。

以下为沿用的 P1–P3 组件细节。旧训练场的 Esc 与 UI 行为仅适用于其独立场景；正式 P4 入口使用上述流程。

## 组件与数据流

| 组件 | 职责 |
| --- | --- |
| PlayerController | 输入采样、运动和转向、一次 move_and_slide、发出 HUD 观测信号；不计算伤害 |
| CameraController | yaw/pitch、鼠标捕获、首位移保护、SpringArm 球形避障 |
| PlayerStateMachine | Idle/Move/Jump/Fall/Attack/Dodge/Skill/Hurt/Dead 的合法切换和动作优先级 |
| PlayerCombat | 攻击/技能时序、连击缓冲、冷却、动作 Resource、Hitbox 启停 |
| AttackDefinition / PlayerCombatSettings | 伤害、动作长、命中与取消窗口、范围、扇形、缓冲和冷却 |
| DamageInfo | 每次挥击/施法/测试脉冲的数据；在自身静态工厂分配单调递增 attack_id |
| Hitbox | Area3D 候选查询、水平距离/扇形/高度过滤、World 视线检查、每次攻击命中目标去重 |
| Hurtbox | 受击 Area，绑定阵营和 HealthComponent；可多个 Hurtbox 共用一份 Health |
| CombatResolver | 统一阵营过滤和伤害公式，委托 Health 扣血；不持有场景或全局运行态 |
| HealthComponent | HP、按攻击实例去重、受击保护、独立无敌原因、硬直计时、单次死亡信号 |
| CombatFeedback / WeaponVisual | 局部停顿、闪白、伤害数字、占位音效，以及与命中计时同步的几何剑挥动/扇形 |
| DebugHUD | 被动订阅生命、动作和鼠标信号，显示状态、HP、冷却；提供训练场重载按钮 |
| PracticeTarget / PracticeHazard | P2 静止靶与带预警的伤害测试设施；不包含敌人行为或导航 |

伤害流：FSM 允许动作 → PlayerCombat 创建 DamageInfo → Hitbox 在命中窗口查询 Hurtbox → CombatResolver 计算伤害 → HealthComponent 扣血并发信号 → FSM/反馈/HUD 响应。组件不通过 UI 获取玩法真值。

DamageInfo 不依赖 Resolver，避免基础伤害数据与结算器互相调用。FSM 保留现有场景组件对 PlayerController 的类型化引用，使用全局脚本类解析，不相互 preload 或实例化。无需通用状态工厂或事件总线。

## 玩家节点结构

```text
Player (CharacterBody3D / PlayerController)
  CollisionShape3D
  Visual                       只旋转表现，默认前向 -Z
    Body / Head / Visor
    Hitbox (Area3D)             固定 5.2 m 候选球；动作中再精确过滤
    CombatVisual (WeaponVisual)
      WeaponPivot / Blade / Hilt
      Arc                      地面扇形显示；不影响结算
  CameraRig (CameraController)  高 1.4 m，距离 4.5 m，默认 -12°
    SpringArm3D                0.22 m 球形扫掠，俯仰 -55°～+35°
      Camera3D
  StateMachine
  Health / Hurtbox
  Combat / Feedback
```

胶囊半径 0.35 m、高 1.8 m，脚底为根原点。仅旋转 Visual，避免运动朝向影响镜头。相机水平基向量决定移动方向，镜头俯仰不影响垂直速度。模型平滑转向参数为 12；攻击中转向采用最大 1.5 rad/s 的限速调整。

| 物理层 | 用途 |
| --- | --- |
| 1 World | 地面、墙、障碍；镜头和攻击视线检测 |
| 2 Player | 玩家实体；玩家移动检测 World 和训练靶 |
| 3 Hurtbox（位值 4） | 所有受击 Area；Hitbox / 测试区检测 |
| 4 Practice target（位值 8） | 静止靶实体，只与玩家碰撞 |

Hurtbox 不主动监测，Hitbox 候选球保持监测，避免临时开启 Area 后等待碰撞列表更新错过短命中窗口。实际生效依赖 action 时间、半径、半角、垂直差 ≤ 1.4 m 以及 World 视线无遮挡。目标按 Hurtbox 中心判定；正式动画/复杂目标在后续阶段迭代，不是连续剑刃网格扫掠。

## 每帧与状态优先级

1. Health 以物理优先级 -30 更新保护/硬直，Feedback 以 -20 更新局部停顿。
2. Controller 采样输入并更新技能、闪避冷却和缓冲；确认命中后的局部 Hit Stop 暂停该角色运动与攻击计时，不修改 Engine.time_scale。冷却和保护继续计时。
3. FSM 优先处理 Dead，然后 Hurt（Skill 不被非致命硬直中断），再处理当前动作和合法输入。
4. FSM 调用 motor，统一应用项目重力，再执行一次 move_and_slide。之后利用新地面信息更新 Jump/Fall/Idle/Move。
5. 发出 telemetry_updated；HUD 读取只读观测信息。生命通过 health_changed 更新。

| 状态 | 输入与退出规则 |
| --- | --- |
| Idle / Move | 地面动作优先级 Dodge → Skill → Attack → Jump；普通移动沿用原组件 |
| Jump / Fall | 保留空中控制和重力；不能新起跳、普攻、技能或闪避；落地回 Idle / Move |
| Attack | 允许有限朝向调整，减速停步；只能在取消窗口闪避；受伤可打断；有效缓冲在动作结束衔接下一段 |
| Dodge | 固定水平方向，保留重力/碰撞；仅指定区间无敌；结束、受伤或死亡时清理 dodge 无敌原因 |
| Skill | 单次施法，普通攻击和闪避不能中断；照常受伤但不进入 Hurt；死亡立即中断 |
| Hurt | Health 独立硬直计时，禁用动作；硬直结束恢复 locomotion |
| Dead | 最高优先级、不可退出；停止所有命中窗口与输入，释放鼠标；训练场重载创建全新组件 |

独立 P2/P3 训练场的 Esc 仅释放鼠标与输入，当前动作及世界仍继续运行；P4 主场景改用前述真正暂停。左键从释放状态恢复捕获时，该次按下直到松开不会触发攻击。训练场窗口失焦同样仅释放鼠标。

## 采用 GDD 的参数与补充决策

| 项目 | 本阶段值 |
| --- | --- |
| 移速 / 加速 / 减速 | 6 / 22 / 28 |
| 跳跃 / 项目重力 | 6.5 m/s / 18 m/s²；Resource 仅配置重力倍率 |
| 闪避 | 恒定 8.888889 m/s × 0.45 s ≈ 4 m；结束清除水平残余冲量 |
| 闪避冷却 | 1.2 s，发起时开始计时，期间连按不会重置 |
| 闪避无敌 | [0.10, 0.30) s；起点包含、终点排除；离开状态立即撤销 |
| HP / 受击保护 / 硬直 | 100 / 0.5 s / 0.25 s；后两项由 Health 配置 |
| 三段普攻 | 12/16/24；动作 0.48/0.56/0.72 s；命中窗口严格采用 GDD |
| 普攻范围 | 2.2 m、110°，GDD 未指定的首轮灰盒测试值 |
| 连击窗口 | 第 1/2/3 段：0.30–0.48 / 0.36–0.56 / 0.50–0.72 s |
| 闪避取消窗口 | 第 1/2/3 段：0.30–0.44 / 0.36–0.52 / 0.50–0.68 s |
| 缓冲与连击重置 | 0.18 s；动作结束时消费仍有效的输入，不提前截断规定总时长；闲置 0.9 s 清零 |
| 星刃斩 | 35、5 m、70°、总长 0.7 s、冷却 8 s，从施法开始计时 |
| 技能命中窗口 | 0.25–0.40 s，GDD 未指定的首轮灰盒测试值 |

攻击计时与显示使用同一时钟，物理步与命中区间取交集，避免较慢帧跳过整个命中窗口。Hit Stop 为额外局部停顿，动作的配置时长不含该停顿。连击使用新 attack_id；Hitbox 每挥击按 Health 实例去重，Health 再保存最近 256 个已结算 ID，包括无敌挡下的接触。死亡只从存活 HP 降至 0 时发出一次。

伤害公式为 `max(1, round(base_damage * attack_multiplier * damage_taken_multiplier))`。配置与运行态分离：Resource 不写冷却、HP 或连击索引，重载不会污染共享参数。无敌按原因维护，撤销 dodge 不会清除受击保护或其他原因。

## 表现与后续边界

几何剑前摇、挥击、收招与地面浅蓝扇形由同一 AttackDefinition 驱动。受击实体闪白，飘字显示实际扣血，目标播放本地生成的 PCM 占位打击音；音量与 Hit Stop 可配置。尚无正式骨骼、根运动或最终 Toon 材质。Blender MCP 在本阶段复查已连通，但仅做只读查询，未修改已有场景或生成资产。

训练场重置仅重载当前场景，恢复 HP、冷却和靶子，不实现 RunManager、正式胜负统计、祝福或存档。P3 已复用当前 Health/Hitbox/Hurtbox/Resolver，并加入独立 EnemyBrain 与预警导航。

接口参考：[Area3D](https://docs.godotengine.org/en/stable/classes/class_area3d.html)、[AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html)、[RenderingServer.force_draw](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw)。实现以本地 Godot 4.7 实际解析、碰撞与渲染验证为准。

## P3 哨兵组件和场景

P3 阶段主场景为 sentinel_arena.tscn，现作为独立训练场保留，包含玩家、两名哨兵、NavigationRegion3D、AttackCoordinator 和训练状态文字。P2 test_arena.tscn 也保留，两者共用 arena_geometry.tscn，避免复制碰撞体。SentinelArena 脚本仅订阅死亡/名额信号显示数量和训练完成/失败，不管理房间、祝福或一局进度。

| 组件 | 职责 |
| --- | --- |
| EnemyBrain | 独立 FSM、感知、路径与动作决策，输出运动指令 |
| SentinelController | 加速度、朝向、项目重力、move_and_slide；报告实际位移和清理尸体 |
| SentinelSettings / sentinel_slash.tres | 数值、攻击时序和可配置导航恢复策略 |
| AttackCoordinator | 场景内 FIFO 攻击名额、交接和失效引用回收，无 Autoload |

```text
Sentinel (CharacterBody3D / SentinelController)
  Collision
  Visual / Body / Head / Eye / Foot
    Hitbox                     复用 P2 判定
    CombatVisual               复用 WeaponVisual，橙色预警/红色生效
  Health / Hurtbox / Feedback   复用 P2，阵营 Enemy
  NavigationAgent3D
  EnemyBrain
  Status                       HP 和 FSM 调试文字
```

Brain 输出 desired_direction、look_direction、movement_locked，Motor 执行运动后把真实位移交回 Brain。Brain 只引用原生 CharacterBody3D 和共享组件，不依赖 PlayerController。角色进入树时在 Health._ready 之前按 Resource 设置 HP、硬直和保护参数；运行状态不写共享 Resource。

实体物理层 5（位值 16）新增为 Enemy；哨兵检测 World、Player、训练靶和其他哨兵，玩家增加对 Enemy 的碰撞。Hurtbox 仍统一使用第 3 层，阵营在 Hurtbox 中区分。镜头/攻击视线只检测 World，不把角色身体当墙。

## P3 导航与受阻恢复

离线 tools/bake_navigation.gd 仅解析共享几何的 World 静态碰撞体，输出 sentinel_arena_navmesh.tres；当前为 62 个多边形，agent_radius 0.5、agent_height 1.75、cell_size/cell_height 0.25。哨兵碰撞半径 0.4，保留静态障碍间隙。运行时不烘焙、不需要插件。

地图迭代号非零且存在有效区域数据后才查询，避免异步地图尚为空时误判路径。烘焙路径比物理脚底高 0.5 m，因此 NavigationAgent.path_height_offset 为 0.5。原始地图查询验证三维目标连通性；移动路径终点按水平距离检查，避免把经过高度偏移的终点误判为不可达。每物理步至多调用一次 get_next_path_position，目标约每 0.2 s 更新；不在导航信号里递归查询。

玩家离开导航面、处于不连通高台、超出感知或 14 m 归巢范围时，哨兵释放名额并返回可行走的出生位置。尝试移动而持续实际位移很小时，0.8 s 后重新寻路；连续两次受阻转 Return。返回仍受阻则停在当前可用位置，延迟 1 s 重试，不瞬移、不永久顶墙。当前未启用 RVO，依赖导航、外围等待、实体碰撞和受阻恢复；更狭窄场地及更多敌人需后续测试。

## P3 状态和攻击调度

| 状态 | 行为与切换 |
| --- | --- |
| Idle | 未感知/归位时待机；10 m 内有存活目标时 Chase |
| Chase | 导航追击；获得名额且距离 ≤1.8 m 时 Telegraph；不可达/失去目标时 Return |
| Telegraph | 停止位移并锁定朝向，橙色预警 0.55 s，无伤害 |
| Attack | 红色生效 0.18 s，10 伤害，每实例仅命中玩家一次 |
| Recover | 0.55 s 恢复，关闭判定，保留名额至动作结束再回 Chase |
| Hurt | 复用 Health 的 0.2 s 独立硬直，立即取消预警、判定和名额；结束后重评估 |
| Return | 归巢与重试，释放名额；归位后 Idle |
| Dead | 最高优先级，不恢复；取消动作/名额，禁用实体和受击碰撞，2 s 后清理尸体 |

GDD 数值全部保留：HP 45、移速 3.2、感知 10、触发 1.8、伤害 10、预警 0.55、生效 0.18、后摇 0.55、冷却 1.3。补充实现决策：冷却从预警发起计时，攻击为 1.8 m / 100° 扇形；未指定的等待距离 2.8、重试 1 s 和归巢范围 14 均可调。预警与生效共用 AttackDefinition 和锁定方向，逃离预警区可以避开攻击，不追踪转身，也不强制转动玩家镜头。

AttackCoordinator 默认并发名额 1，覆盖最后接近、预警、命中和恢复；结束后 0.25 s 交接间隔。FIFO 让已排队哨兵优先于刚完成攻击者。缺少名额/正在冷却且有攻击视线时，哨兵在外围等待；无视线时继续沿路径绕障，避免在墙边错误站定。受击、死亡、失去目标、路径失效或退出树时取消请求；失效引用也会被回收。

玩家死亡会同步终止所有未完成哨兵攻击。Hitbox 每次迭代接触前检查是否已被取消，防止死亡回调清空 DamageInfo 后继续使用失效数据。哨兵复用共享无敌/受击/命中去重，不复制另一份伤害规则。

P3 训练完成文字不等于正式一局结算；P4 的房间、门、祝福和相应界面见本文开头，Boss 仍按 P5 推进。

导航接口参考：[NavigationAgent3D](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html)、[NavigationMesh](https://docs.godotengine.org/en/stable/classes/class_navigationmesh.html)、[NavigationServer3D](https://docs.godotengine.org/en/stable/classes/class_navigationserver3d.html)。以本机 Godot 4.7 的真实路径/碰撞/行为测试为准。
