# Star Abyss 开发规范

- 当前授权阶段为 P7 打磨发布（用户于 2026-10-22 明确授权 P7，并允许从 Godot 官方下载匹配的导出模板）。开始任务前阅读 docs/GDD.md（指向原版 GDD）、docs/TASKS.md 与架构文档。
- P7 包括音效/VFX 打磨、实测性能及针对性优化、Windows 导出与可运行包验收；复用既有三房玩法和 P6 资产。保留 P4 独立阶段回归夹具，不扩大 MVP 玩法。自动验证、图形脚本游玩、人工试玩与未验证事项须分别记录；本次仅已授权的官方匹配导出模板可下载，其他工具/插件/资产不自动下载。
- 使用 Godot 4.x 稳定版与有明确类型的 GDScript；优先现有 Godot 4.7。不得引入未经确认兼容的插件。
- 修改前检查目录、Git 状态与相关文档；不得覆盖无关文件或用户改动。
- PlayerController 负责运动执行，PlayerStateMachine 负责状态与切换，CameraController 负责镜头；UI 通过 Signal 订阅数据。
- 调参使用 Resource / 导出属性。不得把状态判断搬回角色主脚本，不添加无必要的全局单例和抽象层。
- 游戏资源引用使用 `res://`，文件名 snake_case，类型 PascalCase。提交 `.gd.uid`，忽略 `.godot/` 缓存。
- Blender 源文件放在 `blender/`，导出 glTF/GLB 至 `godot/assets/models/`；运行时不依赖 Blender 或 MCP。修改现有 Blender 场景前先检查其内容。
- 每个主要模块完成后导入检查；涉及物理/输入时运行 `tools/verify.ps1`，检查输出中解析、资源和运行错误。渲染相关修改还需图形环境检查。
- 更新 README、docs/ARCHITECTURE.md 和 docs/TESTING.md，准确区分自动验证、人工验证及未验证事项。
- 不使用伪代码、空方法或 TODO 代替核心功能。不自动下载引擎、插件、资产或执行来源不明脚本。
