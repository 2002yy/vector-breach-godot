# 原地图光探针与雾输入恢复

基线 main `2e0187874c500004ac517bab7cfd9d625f5024eb`，分支 `feat/source-map-lighting-20261021`。本片从 main 独立开发，不依赖开放的 [PR #57](https://github.com/2002yy/vector-breach-godot/pull/57)，不等待 CI。尚未将远距对比度或新环境光接入正式对局。

## 实现与本机结果

- `build_source_lighting_bridge.py` 使用已有 .NET SDK 编译 `native/SourceLightingDump.cs`；引用本机 Source2Viewer 20.1 已解包程序集，无联网依赖、无全局配置修改，拒绝覆盖既有 DLL。桥接器将原 KV 类型转换为 JSON，保留全部探针/雾原参数，并把 BC6H HDR 体积逐层导出为原始 RGBA32F；不经 PNG、8bit、色调映射或伽马转换。
- `inspect_source_map_lighting.py` 先核对权威关卡 `sourceTrace` 的原 VPK 文件名/SHA256，提取 World、实体、辐照度与阴影图集；校验 8.2 光照版本和两图集的六倍深度关系。只向新的证据目录写入，全部成功后发布目录，不修改源包、角色/地图纹理、材质旁存或关卡 JSON。
- `source_probe_volume.py` 实现原 Source 坐标下的诊断采样：三线性 texel-center 规则、六面平方方向混合、平移/绕 Z 旋转、边界淡出、按优先级消耗剩余覆盖率、最多四探针混合。缺少 SH1 fallback 时明确返回覆盖率缺口，不补造环境光。pitch/roll、父级变换等未实现形式会明确拒绝，不能当成全兼容。

| 数据 | Mirage | Inferno |
| --- | --- | --- |
| 原探针数 | 58 | 116 |
| HDR 辐照度图集 | 164 × 152 × 384 | 160 × 208 × 840 |
| 阴影图集 | 164 × 152 × 64 | 160 × 208 × 140 |
| 雾实体 | 1 个 cubemap fog | cubemap fog + gradient fog |
| 出生点 / 六向采样 | 33 / 198 | 40 / 240 |
| 所采样位置的 LPV 覆盖率 | 全部 1.0 | 全部 1.0 |
| 采样 RGB 最大分量 | 1.50736 | 2.77635 |
| Vulkan 核对 | 84 项 | 98 项 |

覆盖率只针对这 73 个出生点加原坐标 64 单位的高度，不代表整图无缺口。RGB 大于 1 的值被保留，不能当普通 sRGB 颜色或沿用角色 VTEX Reflectivity 的平均色逻辑。

## 验证与可复现入口

证据目录：`D:/AgentGamePipeline/evidence/source-map-lighting-20261021/`。`mirage-verified/lighting.json`、`inferno-verified/lighting.json` 保存原参数、源/解码哈希、438 六向结果和 GPU 输入；`mirage-gpu-final/checks.json`、`inferno-gpu-final/checks.json` 为最终数据的 Vulkan 实测。另对前后体积/测试向量做字节哈希与内容一致性核对，避免用旧数据的通过结果覆盖新数据。

- 182 项 GPU 检查包含六轴、斜向、中心与非中心坐标及 Inferno 旋转体积；用真正的 `ImageTexture3D` 读取 HDR 原图集，与独立 CPU 三线性结果比较，最大 RGB 向量误差分别约 0.00171 / 0.00140。不是只比较 shader 字符串。
- 已查看出生点六向色板（仅展示时 Reinhard 映射，浮点数据不变），不把色板算地图/角色实际画面签核。
- 本机完整原生 206 项 / `RUN_ALL_OK`，Python 非 Blender 42 项（本片 11 项解析/边界/保护测试）、GdUnit 2/2 通过。C# 编译、Python 编译/Ruff、GDScript 格式/lint、Godot 导入和 diff 检查均需通过；最终提交/PR/当时 CI 状态见本机 `delivery.json`。四个既有 `.import` 改动保留，未纳入本片。

先用 `python tools/build_source_lighting_bridge.py --help` 编译本机桥接器，再用 `python tools/inspect_source_map_lighting.py --help` 提取。提取参数包括本机 CLI、桥接 DLL、权威关卡 JSON、匹配 VPK 及全新输出目录。工具自行生成 `probe-0-gpu-input.json`，GPU 复验入口为 `res://scenes/tests/SourceProbeVolumeGPUProbe.tscn -- --input <该文件> --evidence-dir <输出目录>`，使用 Forward+ Vulkan。依赖的原包、已解包程序集及浮点图集只在本机保存，不公开再分发。

规则参考 pinned VRF `54279ec226cc3e1c561b10f11f0f5e879b981e6e` 的 [SceneLightProbe](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Renderer/SceneEnvironment/SceneLightProbe.cs)、[SceneEnvMap](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Renderer/SceneEnvironment/SceneEnvMap.cs) 和 `common/lighting.lpv.slang`：边界下限为 0.02 源单位；不把 VRF 采样一致声称原引擎整场渲染等价。

## 剩余与下一片

1. Dust II 的权威记录指向已不存在的 `D:/3Dgame-reference/cs2-current/`。当前 `D:/AgentGamePipeline/reference-assets` 含隐藏项的原包清单未找到 `de_dust2.vpk`；只记录缺口，没有修改源哈希或拿其他版本冒充。游戏中的已导出原纹理/视觉资产仍保留。
2. 地图 Source→游戏坐标对齐、边界外 SH1 fallback、运行时 LPV 选择/混合、动态对象应用，以及原引擎同灯光参考尚待验证。
3. 已恢复雾实体原值，但未确认其到角色 `FogModificationAmount` 的映射；角色 `TextureAverageColor` 绑定仍待证实。没有把雾实体参数直接当作距离对比度的强度。
4. 真实角色/动作/烟雾/多角色、环境 BRDF、发丝环境瓣、眼球远距过滤、软法线/切线和逐图 70% 帧率验收仍保留，未更新唯一试玩包。

下一执行片：用已有两图原坐标/视觉变换建立运行时诊断适配，验证移动角色逐片元的双向原探针输入；并继续定位 Dust II 原包、SH1 与雾映射。清单见 [当前待修项](CURRENT_PENDING.md)。
