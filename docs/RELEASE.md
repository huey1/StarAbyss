# Star Abyss（星渊遗迹）Windows 试玩版发布说明

> 状态：**草稿，发布前必须复核**。文中标 `待 RC1` 的数字在源码冻结、构建 RC1 之后填入。
> 构建方法见 [BUILD_WINDOWS.md](BUILD_WINDOWS.md)；测试证据见 [TEST_REPORT.md](TEST_REPORT.md)。

## 1. 版本与系统要求

| 项目 | 值 |
| --- | --- |
| 版本 | `1.0.0`（来自 `godot/project.godot` 的 `application/config/version`） |
| 构建阶段 | P7 打磨发布 |
| 引擎 | Godot `4.7.2.stable.official.ed1daf0bf`（官方稳定版） |
| 渲染后端 | Forward+（Vulkan），**必需**；不支持 Compatibility/OpenGL 回退 |
| 目标平台 | Windows 10/11 x86_64 |
| 被测显卡 | NVIDIA GeForce RTX 3050（`Vulkan 1.4.325 - Forward+`） |

## 2. 安装与启动（**请先读完这节**）

1. 解压 `StarAbyss_1.0.0_windows_x64.zip` 到任意目录（解压，**不要**在压缩包里直接双击运行）。
2. 进入解压出的 `star_abyss_windows_x64/` 目录，双击 **`StarAbyss.exe`**。

### ⚠️ `StarAbyss.exe` 与 `StarAbyss.pck` 必须放在同一目录

游戏数据全部在 `StarAbyss.pck` 里，程序启动时从**可执行文件所在目录**读取同名 pck。本机实测：

| 情况 | 现象 |
| --- | --- |
| exe 与 pck 同目录，从该目录启动 | 正常进入游戏 |
| 只有 exe、没有 pck（或缺 pck 的副本） | 弹出 **`ALERT!` 错误对话框**，游戏无法启动 |
| 把 exe 移到别处、pck 留在原地 | 同上，无法启动 |

所以：**请勿只复制 exe，也请勿把两者分开放**。若看到 `ALERT!`，先检查 pck 是否与 exe 在同一目录。

### 其他提示

- 本版本**未做代码签名**，首次运行可能触发 Windows SmartScreen 提示（"更多信息" → "仍要运行"）。我们不会要求你关闭杀毒软件或修改系统安全设置。
- 启动后到出现画面需要一点时间（冷启动含 Vulkan 初始化与着色器加载），期间窗口可能是黑的，属正常现象。
- 存档与配置写入 `%APPDATA%\Godot\app_userdata\`（引擎标准位置），卸载游戏不会自动删除它们。

## 3. 发布包内容

```text
star_abyss_windows_x64/
  StarAbyss.exe            游戏主程序（= 官方 release 模板，见下方说明）
  StarAbyss.pck            全部游戏内容
  试玩说明.txt              试玩范围与操作说明
  GODOT_LICENSE.txt        引擎许可（由引擎自身生成）
  THIRD_PARTY_NOTICES.json 引擎第三方组件通知（由引擎自身生成）
  BUILD_INFO.json          构建事实与验证标志
  SHA256SUMS.txt           以上文件的 sha256
```

### 为什么 `StarAbyss.exe` 的哈希和官方模板一样

预设里 `binary_format/embed_pck=false`，Godot 不会把游戏数据塞进 exe：导出的 `StarAbyss.exe` 就是官方
release 模板可执行文件的**逐字节复制**。因此

- `StarAbyss.exe` 的 sha256 **等于** `windows_release_x86_64.exe` 模板的 sha256，这**不是**打包错误；
- exe 的完整性等价于"官方 4.7.2 模板"的完整性，**游戏内容的变化只体现在 `StarAbyss.pck` 的 sha256 上**；
- 校验发布包时请以 **pck 的哈希**为准，比对 exe 哈希永远会得到"相同"这个无信息量的结论。

## 4. 校验（可选，但建议）

```powershell
cd star_abyss_windows_x64
Get-FileHash StarAbyss.pck -Algorithm SHA256     # 与 BUILD_INFO.json 的 pck_sha256 对照
```

`BUILD_INFO.json` 的 `pck_sha256` 是权威值，`SHA256SUMS.txt` 覆盖目录内全部文件。

## 5. 已知限制与未验证事项（如实告知）

| 项目 | 状态 |
| --- | --- |
| 自动验证（headless + 图形脚本） | 见 `docs/TEST_REPORT.md`，以该文档为准 |
| 包内容审计 | `pack_audit`：75 项断言，0 失败（RC0 实测） |
| 导出包功能夹具 | `export-smoke`：15 项断言，0 失败（RC0 实测） |
| release 二进制启动 | 已验证：退出码 0、`Vulkan … Forward+`、无脚本错误 |
| **原生键鼠输入（真人操作路径）** | 待 RC1 上由 QA 的 L4 脚本验证 |
| **人工试玩记录** | 尚无；`BUILD_INFO.json` 中 `human_playtest_verified` 保持 `false` |
| 冷启动到首帧耗时 | 待 RC1 实测填写（RC0 观察到约 5 秒量级，非正式数据） |
| 代码签名 / 安装包 | 无。绿色免安装 zip |
| 其他 GPU / 无 Vulkan 设备 | 未测试，不承诺可运行 |
| 分辨率与显示缩放 | 待 RC1 实测定稿 |

## 6. 反馈问题时请附上

- `BUILD_INFO.json`（尤其是 `version`、`engine_version`、`pck_sha256`）；
- 显卡型号与驱动版本；
- 出问题时的引擎日志：`%APPDATA%\Godot\app_userdata\` 下的 `logs/`，或启动时加 `--log-file <路径>` 指定。
