# 眼球远距修正与角色环境输入续修

分支 `fix/character-eye-filter-20261021`，共同基线 main `7ce895b8253a3dd61948b60527eb6c149629e661`。四个既有 `.import` 状态继续保留；本片不改关卡、碰撞、路网、移动和命中规则，不覆盖已验证试玩包。

## 原依据与实现

原私有 `csgo_character_vulkan_50_ps.vcs` SHA256 为 `24efecd81546ad2c5010735b30a0069ce28010eb630204e646a6e1572062dd4a`。此前已通过 VPK CRC 的同版本资源；`native-ps-glsl/combo-32-0.glsl:543` 可核对眼球分支。原文件、反编译和哈希收据保持私有，不提交原数据。

在已投影虹膜坐标 X 的屏幕导数绝对值大于 0.15 时，原 PS 按 `saturate((distance_in_source_units - 100) * 0.005)` 混合原眼色与 `0.8 * 原眼色 + 局部高光`，之后才经过 EyeMask 与朝向权重合入表面。起始距离为 2.54m，7.62m 达到全权重。本片移植此遗漏分支，保留原纹理、虹膜 Alpha、瞳孔、色相和角膜法线；新增默认开启的材质级诊断对照参数，仅在已启用且已校准的眼球上生效。

固定版 VRF `54279ec226cc3e1c561b10f11f0f5e879b981e6e` 的 `csgo_character_eyes_ps.slang` 在相同位置使用 **0.05**。本片按原编译 PS 的 **0.005**，不能直接照抄查看器十倍斜率。原反编译反向 `smoothstep(0.1,0.08,x)` 改写为 `1-smoothstep(0.08,0.1,x)`，避免 GLSL 对反向边界未定义；不改变预期降序平滑曲线。Godot 内置函数依据：[shader functions](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_functions.html)。

## 验证合同与结果

私有证据目录 `D:/AgentGamePipeline/evidence/character-eye-distance-20261021/`。新 Vulkan probe 为 `scenes/tests/CharacterEyeDistanceProbe.tscn`：

- 15 个 HDR GPU 数值金标准：导数正负/零/等于阈值、距离起止/中点/超出、原 0.005 斜率、局部高光内外/中点及 HDR 不截断。
- 三真实角色 × 两姿态 × 五距离（0.45/2/5.08/7.62/15m）× 开关，30 个对照、60 张全画面和 60 张真实眼区裁剪。0.45/2m 不改色；每角色至少一个远距样本实际改变。未命中眼球的远距像素可以保持不变，不伪造最低变化量。
- 本片初验 45 条通过；真实远距变化样本数为精英 4、黑狼 1、凤凰 2。既有布料/皮肤/各向异性/逆反射/发丝/眼球 27 条 Vulkan 检查通过。最终完整套件、提交/PR/CI 与包状态见该目录交付收据；初验不代替最终候选检查。

复核修复：不能直接保留反编译代码中片元命中分支内的 `dFdx`。现在投影坐标和两轴导数由整组片元统一执行，命中分支只取已算结果；虹膜改用显式 `textureGrad`（UV 变换 .5 × 原 bias 的 exp2(-.5)），微法线复用统一分支采样。新 probe 另加三角色各四个亚像素位移的静止重复检查，确认相同姿态/相机画面可复现及实际覆盖发生变化；不是跨设备或连续运动抗闪烁验收。

最终 GPU 合同扩为 **57 条 / 156 PNG**（15 数值、30 开关对照、12 亚像素静止重复），最终远距实际变化样本为精英 6、黑狼 4、凤凰 6；27 条专用材质与 18 张眼球绑定回归重跑通过。近景的距离项开关不改变颜色，但梯度修复可影响眼睑/球面边界采样，不能说与旧 shader 逐像素一致。

这恢复原远距修正规则，不能单凭开关差异声称所有闪烁已解决。三图真实背景、连续相机运动的时序稳定性与 Valve 同灯光参考仍需后续验收。本片没有把候选覆盖到桌面试玩入口。

最终本地验证：完整原生 **207 项 / RUN_ALL_OK**、Python 非 Blender **48 项**、GdUnit **2/2**、GDScript format/lint、Godot 导入与 `git diff --check` 通过；原 18 模型哈希不变。已审看三角色最大差异的远距像素对照。源码候选验证通过不代替独立 PCK/EXE、三图整场或性能验收；提交后精确头 CI 另记收据。

## 发丝环境第二瓣的具体输入缺口

原发丝 PS 的 `combo-8199-0.glsl:1230–1239` 调整第二瓣采样方向，`:1386` 另算 roughness scale 后的反射 LOD。当前三图 LPV 是漫反射辐照度，无法替代这些方向性预过滤反射输入。Godot 的 `RADIANCE` 是写入混合输出，并非可读取当前环境 cubemap 的采样器，见 [spatial shader outputs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。

下一执行片先核对三图原反射 cubemap/探针的来源、方向变换、预过滤 mip 与盒投影绑定，再移植发丝环境第二瓣；不以提亮、EMISSION 或二次使用 LPV 冒充原反射。软法线/蒙皮切线与距离对比度原雾/平均色赋值继续单列。加载、C4/观战、AI 和整场/70% FPS 保留既有顺序与验收要求。

本片继续取得反射输入：三图 `env_combined_light_probe_volume.cubemaptexture` 均指向各图 `cubemaps/env_cubemap_array.vtex`。已从匹配原 VPK 哈希的包内提取并保存原 BC6H 文件与收据：均为 256×256，Depth 分别 Dust II 43、Mirage 58、Inferno 116，flags=80（0x50）。这些是 cubemap 数组的层数，不能按 LPV 的三维六片布局解释；六面顺序、mip 和空间绑定尚待核验。私有收据为 `reflection-input-inventory.json`、`reflection-header-receipt.json`，不将资源已取得算作环境第二瓣已实现。
