# P3 交付文件清单

用户提供的 docs/Star_Abyss_GDD_v1.0.md 仅阅读，未改写。工作目录仍不是 Git 仓库，未初始化或提交。

## 本阶段新增

- godot/scripts/ai/{sentinel_settings,attack_coordinator,enemy_brain,sentinel_controller}.gd：配置、攻击协调、独立 AI 与移动组件。
- godot/scripts/systems/sentinel_arena.gd：P3 训练状态展示。
- godot/resources/enemies/{default_sentinel,sentinel_slash}.tres：GDD 数值与攻击时序。
- godot/resources/navigation/sentinel_arena_navmesh.tres：62 多边形导航网格。
- godot/scenes/enemies/sentinel.tscn：哨兵实体、共享生命/判定/反馈和占位武器。
- godot/scenes/levels/{arena_geometry,sentinel_arena}.tscn：共享场地与 1v2 默认场景。
- godot/tests/{enemy_rules_test,enemy_behavior_test,enemy_integration_test}.gd：97 项新增检查。
- tools/bake_navigation.gd：离线重烘焙工具。
- docs/{sentinel_preview,sentinel_complete}.png：预警与 1v2 完成实机预览。
- 新 GDScript 的 .gd.uid：Godot 生成，随源文件保留。

## 本阶段修改

- godot/project.godot：主场景与 Enemy 碰撞层。
- godot/scenes/player/player.tscn：玩家增加对敌人的实体碰撞。
- godot/scenes/levels/test_arena.tscn：抽取共享几何，P2 原场景保留。
- godot/scripts/combat/hitbox.gd：同步取消判定后的迭代保护。
- godot/scripts/combat/weapon_visual.gd：可配置预警/生效颜色，供敌我复用。
- godot/scripts/systems/debug_hud.gd：场景可配置阶段和操作提示。
- tools/verify.ps1：加入三套 P3 检查。
- tools/smoke_test.gd、godot/tests/combat_integration_test.gd：隔离自动测试中的外部鼠标位移，专门鼠标事件测试仍启用。
- AGENTS.md、README.md、docs/{GDD,TASKS,ARCHITECTURE,ENVIRONMENT,TESTING,FILES}.md：阶段、技术决策、记录及说明。
- docs/preview.png、docs/combat_preview.png：P2 回归重新生成。
- 移除已填充的 scripts/ai 与 scenes/enemies 中 .gitkeep。

## 当前完整源文件与文档

```text
.gitignore
AGENTS.md
blender\characters\.gitkeep
blender\environments\.gitkeep
blender\exports\.gitkeep
docs\ARCHITECTURE.md
docs\combat_preview.png
docs\ENVIRONMENT.md
docs\FILES.md
docs\GDD.md
docs\preview.png
docs\sentinel_complete.png
docs\sentinel_preview.png
docs\Star_Abyss_GDD_v1.0.md
docs\TASKS.md
docs\TESTING.md
godot\assets\animations\.gitkeep
godot\assets\materials\.gitkeep
godot\assets\models\.gitkeep
godot\project.godot
godot\resources\combat\attack_01.tres
godot\resources\combat\attack_02.tres
godot\resources\combat\attack_03.tres
godot\resources\combat\default_player_combat.tres
godot\resources\combat\star_blade.tres
godot\resources\default_player_movement.tres
godot\resources\enemies\default_sentinel.tres
godot\resources\enemies\sentinel_slash.tres
godot\resources\navigation\sentinel_arena_navmesh.tres
godot\scenes\combat\practice_hazard.tscn
godot\scenes\combat\practice_target.tscn
godot\scenes\enemies\sentinel.tscn
godot\scenes\levels\arena_geometry.tscn
godot\scenes\levels\sentinel_arena.tscn
godot\scenes\levels\test_arena.tscn
godot\scenes\player\player.tscn
godot\scenes\ui\debug_hud.tscn
godot\scripts\ai\attack_coordinator.gd
godot\scripts\ai\attack_coordinator.gd.uid
godot\scripts\ai\enemy_brain.gd
godot\scripts\ai\enemy_brain.gd.uid
godot\scripts\ai\sentinel_controller.gd
godot\scripts\ai\sentinel_controller.gd.uid
godot\scripts\ai\sentinel_settings.gd
godot\scripts\ai\sentinel_settings.gd.uid
godot\scripts\combat\attack_definition.gd
godot\scripts\combat\attack_definition.gd.uid
godot\scripts\combat\combat_feedback.gd
godot\scripts\combat\combat_feedback.gd.uid
godot\scripts\combat\combat_resolver.gd
godot\scripts\combat\combat_resolver.gd.uid
godot\scripts\combat\damage_info.gd
godot\scripts\combat\damage_info.gd.uid
godot\scripts\combat\health_component.gd
godot\scripts\combat\health_component.gd.uid
godot\scripts\combat\hitbox.gd
godot\scripts\combat\hitbox.gd.uid
godot\scripts\combat\hurtbox.gd
godot\scripts\combat\hurtbox.gd.uid
godot\scripts\combat\player_combat_settings.gd
godot\scripts\combat\player_combat_settings.gd.uid
godot\scripts\combat\player_combat.gd
godot\scripts\combat\player_combat.gd.uid
godot\scripts\combat\practice_hazard.gd
godot\scripts\combat\practice_hazard.gd.uid
godot\scripts\combat\practice_target.gd
godot\scripts\combat\practice_target.gd.uid
godot\scripts\combat\weapon_visual.gd
godot\scripts\combat\weapon_visual.gd.uid
godot\scripts\player\camera_controller.gd
godot\scripts\player\camera_controller.gd.uid
godot\scripts\player\player_controller.gd
godot\scripts\player\player_controller.gd.uid
godot\scripts\player\player_movement_settings.gd
godot\scripts\player\player_movement_settings.gd.uid
godot\scripts\player\player_state_machine.gd
godot\scripts\player\player_state_machine.gd.uid
godot\scripts\systems\debug_hud.gd
godot\scripts\systems\debug_hud.gd.uid
godot\scripts\systems\sentinel_arena.gd
godot\scripts\systems\sentinel_arena.gd.uid
godot\tests\combat_integration_test.gd
godot\tests\combat_integration_test.gd.uid
godot\tests\combat_rules_test.gd
godot\tests\combat_rules_test.gd.uid
godot\tests\enemy_behavior_test.gd
godot\tests\enemy_behavior_test.gd.uid
godot\tests\enemy_integration_test.gd
godot\tests\enemy_integration_test.gd.uid
godot\tests\enemy_rules_test.gd
godot\tests\enemy_rules_test.gd.uid
README.md
tools\bake_navigation.gd
tools\smoke_test.gd
tools\verify.ps1
```

godot/.godot/ 导入缓存与 .local/ 测试设置/日志均可再生成且已忽略。没有新增依赖、Blender 资产、存档或 Windows 导出包。
