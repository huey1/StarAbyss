# P6 美术规范

本阶段沿用 GDD v1.0 第 9 节：灰蓝古代遗迹、青色晶体、暖色敌方危险预警、色块分明的卡通渲染。模型由本项目 Blender 脚本生成，保留可编辑源文件；Godot 统一维护运行时 Toon 材质。无外部下载资源、贴图或插件依赖。

## 环境资产

`blender/environments/ruins_kit.blend` 为米制源文件，`godot/assets/models/environment/ruins_kit.glb` 为运行时资产；`godot/scenes/art/ruins_dressing.tscn` 根节点为 RuinsDressing，可在原 ArenaGeometry 原点实例化。构建脚本是 `tools/build_environment_assets.py`，应在独立后台 Blender 中执行，不能修改用户交互场景。

GLB 分为 Floor、FloorInlay、Walls、Platforms、Pillars、Crystals、GateArch 七个网格模块。每个模块已应用缩放、原点统一为场地原点；网格保留多材质面，可单独编辑与复用。Godot 导入坐标 +Y 朝上、-Z 为北，与现有场景一致。

| 材质名 | 颜色（线性 RGB） | 用途 |
| --- | --- | --- |
| RuinStone | 0.25 / 0.34 / 0.42 | 墙面与平台主体 |
| RuinStoneAlt | 0.28 / 0.37 / 0.44 | 克制的地砖与墙面变化 |
| RuinDark | 0.075 / 0.12 / 0.18 | 砖缝、凹槽与轮廓 |
| RuinEdge | 0.43 / 0.52 / 0.58 | 倒角、柱环与台面 |
| RuinInlay | 0.12 / 0.35 / 0.39 | 低亮度遗迹刻线 |
| CrystalCyan | 0.12 / 0.73 / 0.78 | 六棱晶簇与柱体晶核 |
| RuinBronze | 0.44 / 0.39 / 0.27 | 门楣徽记 |

地面仍为 40×40 米，表面 y=0.004，刻线不超过 y=0.010。地砖和中心圆环采用低对比度，避免与橙红攻击危险区争夺视觉焦点。围墙、双柱、两座低台与东北高台逐一覆盖已有几何尺寸；晶簇只设置在墙体范围及既有柱顶，未向开放行走区添加视觉障碍。门饰与 z=-16 的原出口框重合，4.2 米通行开口保持畅通。

环境 GLB 仅含视觉网格，不提供碰撞体或导航网格。接入时只隐藏原 Ground、NorthWall、SouthWall、EastWall、WestWall、LowBlock、Step、HighPlatform、WestPillar、EastPillar 的 Mesh，以及旧 Markings 和 NorthLabel。WorldEnvironment、Sun、StaticBody3D、CollisionShape3D 和现有导航资源保持原状。源文件的相机与灯仅供 Blender 预览，不导出至 GLB。

## 重建与验收边界

角色源为 `blender/characters/player.blend`、`blender/enemies/sentinel.blend` 与 `guardian.blend`，另有独立 sword/sentinel_blade/guardian_hammer 源；运行时在 `godot/assets/models/characters/` 使用同名GLB（守卫为core_guardian.glb）。内部根名分别为CHR_Player_01、ENM_Sentinel_01、BOS_CoreGuardian_01。探索者以银发、青围巾、灰蓝分叉外套与浅色肩甲辨识；敌人以暖色晶核、面罩、装甲分段辨识，Boss增加宽肩晶体与锤轮廓。

角色身高目标1.75/1.65/2.6m，各18骨、显式蒙皮权重，Root不位移；Godot -Z为前。金属甲片刚性权重、布料为简化分段，无布料/表情/IK。WeaponSocket为右手子骨，独立武器原点在握柄、长轴为Godot -Z，三武器根均单位变换；ActorPresentation根据骨rest轴自动补偿，不让资产导入轴与动画双重旋转。

动画总计48片段（玩家14、哨兵14、Boss20）；Idle/Run等共用命名，运行时Attack/Attack_Sweep/Attack_Shockwave均为包含预警/生效/恢复的整段。时长与边界见 `docs/character_asset_manifest.json`。攻击关键帧与Resource相同时间采样，武器在前方扫击；死亡仅局部骨骼倒地，代码位移不被Root Motion重复推动。

Godot Toon参数集中在 `cel_surface.gdshader`：三档直射强度0.40/0.72/1.0、阈值0.35/0.75、暗部冷色和可调发光。角色/武器另用 `cel_outline.gdshader` 的0.008m深蓝外壳细边，环境关闭该pass。GLB只提供分区底色，ToonPalette在实例上替换材质，不依赖Blender节点材质。实现按[Godot空间着色器接口](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)输出light贡献，底色由引擎最终合成。

```powershell
& 'E:\share\Blender 5.2\blender.exe' --background --factory-startup --python 'D:\AiProject\StarAbyss\tools\build_character_assets.py'
& 'E:\share\Blender 5.2\blender.exe' --background --factory-startup --python 'D:\AiProject\StarAbyss\tools\build_environment_assets.py'
```

构建会检查有限顶点坐标、非空面和应用缩放，记录 `blender/environments/ruins_manifest.json`，保存源文件、GLB 和 Blender 预览。Godot 导入、Toon 整合、实机预览和完整玩法回归由工程验收流程执行。Blender 预览仅证明源资产可渲染，不能替代 Godot 的攻击预警可读性、实体键鼠体验或性能验收。

2026-10-22 已实际在 Blender 5.2.2 LTS 重建并渲染，后台进程退出 0。最终环境为 7 个模块、9843 顶点、17606 三角形；每个模块缩放为 1。只读复查四面墙各有 1656 个顶点，南墙与东墙的外侧射线命中和法线方向正确。晶体与圆环自建面的朝向在最终导出前已校正。上述是源资产检查记录，完整 Godot 验证结果以 TESTING.md 为准。
