# 角色原反射 SH、BRDF 与发丝环境第二瓣

分支 `feat/character-reflection-normalization-20261022`。先从 main `a00f819` 独立提取输入，不等 #66 CI；随后 #66 精确头 `cee5323b205995b9dd3043cdddda2206b1d1bd8d` 的 Tests `39644309614`、Windows export/smoke `39644309674` 全绿，合并到 main **`5ea8c034a48f097dff54aaf4be2a789279680ed5`**，本片快进到该基线继续角色绑定。该 main 的 push Tests `39645959880` 首次查询运行中，没有等待。

## 实现

- 新桥接器保留三图原 VTEX、radiance SH 头与 float32 原系数。43/58/116 个原反射，共 **217 组、5859 个系数**；每组 27 个，RGB 平面 L2。按固定查看器源码将常数/线性四项折为亮度 L1，线性通道按 Source 的 y/z/x 顺序重排。
- 原 `textures/dev/brdf_lut.vtex_c` 所在 core 包段本机缺失，匿名下载当前 manifest 的一个认证块，压缩下载 **432432 字节**，再按原目录资源 CRC **f200701b** 验证。保留资源 SHA256 **2b234525df00b01659f9bbbefc4a8a2fb47f315f0508a5852fe3f8e426f707ee**。缓存目录明确标记 PARTIAL，不冒充完整 depot；无需 Steam 登录。
- 原表为 **64×64×3、RGBA16F、单 mip**，保存原半精度数据，并精确展开 float32 上传；不做 sRGB 或图像重采样。与固定 VRF 内置表的编译文件头不同，解码后 float32 SHA256 均为 **5a0e672ceb7de9606f12a20bbbcb4d8fc9d6cae8f1a1ca7e6f4231cb3958f0c1**。
- BRDF 第 1 层使用 `(roughness,sqrt(1-NoV))*63/64+1/128`；移植 split sum、平均 Fresnel 与多次散射项。SH 归一化保留暗化与粗糙度上限；当前上限参数 **(2,1)** 取固定查看器的显式默认，不声称已捕获原引擎每帧常量。
- 编译角色 PS 显示环境辐射与 SH 都除以含初始 0.01 的总权重；新增角色采样入口保留该规则，不改变 #66 原辐射诊断入口的输出。发丝使用球面投影切线、不同的扭曲轴/偏移轴、第二瓣粗糙度与 mip、原透射权重和反照率色调。
- `SourceCharacterEnvironment.gd` 仅在显式诊断调用时复制已有角色材质并插入候选，不改普通角色 shader，不加几何辅助层。只对原 hair mask 覆盖部分替换 Godot 环境反射并加入候选结果，保留直接光和现有漫反射。detach 恢复原材质；复制材质的眼球位置/朝向/半径/启用状态在原控制器之后同步。

## 源依据

固定 VRF `54279ec226cc3e1c561b10f11f0f5e879b981e6e`：[SceneEnvMap.cs](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Renderer/SceneEnvironment/SceneEnvMap.cs)、[environment.slang](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Shaders/common/environment.slang)、[pbr.slang](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Shaders/common/pbr.slang)、[BRDF 绑定](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Renderer.cs)。

原编译角色 PS 为本机 `character-special-effects-20261020/native-ps-glsl/combo-8199-0.glsl`，关键区间：球面切线 507–509、粗糙度轴判定 787–790、环境法线 1214–1239、第二瓣 roughness/LOD 1386–1389、BRDF 表与两瓣合成 1532–1566。原 shader 不公开提交。

## 查验入口与结果

证据目录 `D:/AgentGamePipeline/evidence/character-reflection-normalization-20261022/`，最终三图入口为 `*-certified/` 与同名日志。

| 地图 | 原 SH/BRDF/第二瓣方向 CPU↔GPU 案例 | 最大归一化误差 | 真实角色组合 |
| --- | ---: | ---: | ---: |
| Dust II | 172 | 0.000924 | 8 |
| Mirage | 232 | 0.000930 | 8 |
| Inferno | 464 | 0.000901 | 8 |

共 **868** 组数值，每组检查归一化、single/multi scatter 和第二瓣方向；同时回归 #66 世界坐标/选择 **2140** 组（480 重叠）。真实角色为两种原 hair 材质所属的精英叛军/黑狼，两个实际 run 姿势、1.8m/7m 两个距离，共 **24** 组，保存原材质/候选关闭/主瓣/双瓣四方对照；关闭误差全部 **0**，第二瓣均产生非零差异。另检查绑定不叠加、恢复原材质，以及附着期间移动/骨骼变化/缩放后眼球输入仍同步。角色 96 PNG，加数值图 6 PNG，共 **102 PNG**。

完整本机回归：原生 **208 / RUN_ALL_OK**、Python 非 Blender **62**、GdUnit **2/2**、GDScript 格式/lint、Ruff、Godot 导入/解析、三项资源策略与 diff 检查通过。18 个原模型 SHA256 不变，三图原 SH 系数的全部 float32 字节可直接在各自原 VTEX 的 2672/3184/5232 偏移找到；原 BRDF 的全部 half→float32 转换另用 Python 独立核对。三图已查看的最终角色截图与补齐眼球同步前的对应截图哈希相同。最终审计为证据目录 `audit.json`，PR/精确头/CI/脏状态为 `delivery.json`；四个既有导入改动不纳入提交。

重现：编译 `tools/native/SourceReflectionNormalizationDump.cs`（使用现有 `build_source_lighting_bridge.py --source`），由环境变量 `VB_RESOURCE_INPUT`、`VB_NORMALIZATION_OUTPUT`、`VB_NORMALIZATION_KIND=sh/brdf` 提取；使用 `tools/prepare_reflection_normalization.py` 绑定匹配的反射元数据和输入。运行 `CharacterEnvironmentProbe.tscn`，参数沿用 `ReflectionWorldProbe`，增加 `--normalization <normalization.json> --lighting <lighting.json>`。必须使用本机 Godot 4.7.1 编辑器 Vulkan；普通 release EXE 不支持诊断覆盖。

## 失败与剩余边界

最初误将 SH extra 声明长度当作完整负载；实际头只有 8 字节，系数在声明范围外，已使用 VRF 解析后的完整数组并保留原 float32。首个 GPU 尝试遇到 GDScript 未定类型的字符串变量解析失败，随后引擎/驱动退出崩溃；已显式声明类型，后续先导入/解析再运行。审查发现两个 hair 头材质均启用了球面投影各向异性，且扭曲轴与法线偏移轴不同，已修正并加入独立 CPU/GPU 方向检查。

后续补了 eye_radius/启用状态动态同步后，重新运行三图；私有驱动一次错误替换了 Mirage 的 LPV 输入目录，日志出现断言，未算通过，修正输入路径后重验。早期完整原生回归因同步修正而主动中止，保留中间日志，最终只以新运行 `native-final.log` 为准。

本片是**真实角色上的受控反射候选**，不宣布完整角色环境着色等价：现有漫反射仍由 Godot 处理，完整间接能量分配、软法线/蒙皮切线、原 per-view 常量绑定、AO/阴影、天气/雾、烘焙对象 handshake、多人遮挡、时序稳定和性能仍待完成。不能把几组近远截图当成全图实战远距验收。

归一化的 irradiance 当前取既有六向 LPV 受控样本；原编译 combo 8199 的 diffuse/luma 在 519–520 行来自 per-view SH1 点积，其 combo 选择与 CPU 常量赋值尚未建立对应。下一片必须分清此输入与 LPV 的关系，不能因归一化数值公式通过就认为最终照明已经等价。

旁项：Dust II 首出生点远处屋顶仍有紫/黑辅助样式面，原材质基线截图中也存在；记录回三图材质巡检，不在本片顺手改地图。当前试玩包仍停在 #63；最新同头 18 场、连续人工比赛与逐图 70% FPS 均待完成。

下一片：核对完整间接光的能量分配、法线/切线和实际 per-view 归一化参数，将候选与既有角色 LPV 合成统一，再决定正式启用与更新试玩包；加载策略优化、C4/观战和 AI 运动/难度继续保留。
