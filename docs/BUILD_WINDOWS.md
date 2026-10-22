# Windows 构建与验收

P7 目标为 Windows x86_64、Godot 4.7 stable、Forward+ / Vulkan。构建使用真正的 Windows release 导出模板；编辑器负责导入/打包及独立数据包的功能脚本验证。交付目录不包含 Godot 编辑器、Blender 或测试代码。

## 本机模板

最初检查 `E:/share/Godot_v4.7`、项目隔离 APPDATA、用户 Godot/export_templates 和引擎 portable/editor_data 目录，均没有已安装的模板。用户于2026-10-22明确授权从 Godot 官方下载匹配模板，缓存位置为：

```text
.local/export_templates/cache/Godot_v4.7-stable_export_templates.tpz
.local/export_templates/4.7.stable/windows_release_x86_64.exe
```

官方标准模板包约1.19GB，仅提取本项目需要的 Windows release x64 可执行模板。完整压缩包的期望 SHA256 为：

```text
9714459dc071907c0f3d5f17d608faf69e7cda21331fc5d39c4503ffa4e99eec
```

来源：[Godot 4.7 stable 官方下载页](https://godotengine.org/download/archive/4.7-stable/)与[官方发布资产校验信息](https://github.com/godotengine/godot-builds/releases/expanded_assets/4.7-stable)。不从第三方镜像下载、不改动用户的全局编辑器配置。`build_windows.ps1`不会自动下载模板；缺失时明确失败。解压前必须校验完整压缩包，再校验模板 `--version` 与编辑器版本一致。

2026-10-22实际下载1,279,207,690字节，完整SHA256匹配；只提取上述Windows文件。模板SHA256为`c42eb5d17f683eb8bcd52c19a9f36ebf811b1788623878d5276a7d9ffc09f95c`，版本实测`4.7.stable.official.5b4e0cb0f`，与现有编辑器完全一致。独立微型工程已通过custom_template项目相对路径和shader_baker开启的headless release导出；这是导出能力预检，不代替正式游戏包验收。

## 构建

项目根目录中使用 PowerShell 7：

```powershell
pwsh -NoProfile -File .\tools\verify.ps1
pwsh -NoProfile -File .\tools\build_windows.ps1
```

可通过 `-GodotPath` 指定本机同版 Godot console 编辑器。preset固定使用项目内模板的 `res://../.local/export_templates/4.7.stable/windows_release_x86_64.exe`，避免依赖其他机器的绝对路径。脚本检查编辑器与模板版本、导出输出、实际运行、许可文件与SHA256，再生成ZIP。

正式输出：

```text
builds/windows/star_abyss_windows_x64/
  StarAbyss.exe
  StarAbyss.pck
  试玩说明.txt
  GODOT_LICENSE.txt
  THIRD_PARTY_NOTICES.json
  BUILD_INFO.json
  SHA256SUMS.txt
builds/windows/star_abyss_windows_x64.zip
builds/windows/star_abyss_windows_x64.zip.sha256
```

`export_presets.cfg`以release模式编译资源，排除`tests/*`和Blender/文档源；`.blend`源本来位于Godot工程外。开启Godot的shader_baker导出选项以请求Forward+预编译，但须检查实际产物和具体机器首帧表现，不能仅凭开关或导出成功宣称已消除编译卡顿。PCK保持独立，不嵌入EXE。模板与资源包同时保留在ZIP中，解压后双击EXE即可运行，须保持同名PCK相邻。此包未代码签名；构建不需要也不会读取证书或密码。引擎和第三方许可通知通过本机Godot的Engine接口生成。

`-PackOnly`只生成PCK，用于数据打包诊断；独立极小工程已确认`--export-pack`不需要模板，不能据此宣称有正式Windows EXE。`-SkipSmoke`可跳过图形检查，但会在BUILD_INFO.json中分别标记PCK功能与release常规启动未经验证，这种输出仍待验证。

## 包验收

官方4.7 release模板实测以`disable_path_overrides=yes`编译：拒绝`--main-pack`、不支持外部`--script`。因此默认构建明确分两层验证，不能把它们等同：

1. 用同版本编辑器的游戏运行模式（不加`--editor`、不加源码`--path`），从输出目录以`--main-pack`加载最终PCK，加外部`godot/tests/export_smoke_test.gd`。检查包内无测试源码、实际点击开始、资源/骨骼/武器加载、移动与技能输入、Esc暂停、重开及返回菜单，并保存图形帧。该检查验证最终包内数据，运行二进制仍为编辑器构建。
2. 从输出目录直接启动真正release EXE，让其自动加载相邻同名PCK，不注入外部脚本，运行普通主菜单120帧并检查退出/日志。这验证真实release的常规启动，不能单独证明其全部输入与闭环。真实EXE的原生输入或人工试玩须另有实际记录，不能从PCK脚本检查推定。

测试脚本不放入PCK。BUILD_INFO.json分别记录`pck_functional_smoke_verified`、`release_normal_start_verified`、`release_native_input_verified`和`human_playtest_verified`，不将尚未执行的检查标为完成。

每个过程均检查退出码、stdout/stderr和错误/警告行；60秒超时只终止本次测试进程。日志与截图在`.local/export-diagnostics/`。自动脚本检查不能替代人工试玩；实体键鼠三局、音效听感、主观美术和不同机器兼容性分别保留验收状态，见TESTING.md。性能测量另见主阶段报告，不以固定FPS脚本或打包成功充当性能达标证据。

构建阶段只创建/覆盖本项目固定输出文件，不递归删除目录。若输出目录出现预期之外的文件，脚本会停止供检查，避免把用户文件误装进ZIP。

2026-10-22正式游戏构建已执行：编辑器与release模板版本匹配，PCK功能脚本15项通过，真正release普通启动120帧退出0，相关导出/功能/启动日志无错误或警告。最终ZIP和每项文件SHA256均由脚本产生；原生release输入与人工试玩状态仍以BUILD_INFO.json及TESTING.md中的实际记录为准。
