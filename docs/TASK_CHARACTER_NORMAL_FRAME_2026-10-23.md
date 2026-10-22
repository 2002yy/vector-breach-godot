# 候选法线重建与 SSAO 合成边界

基线 main `76337b0c291463ac4b7049f14ea807eb02c93b3e`（#70 合并），分支 `fix/character-normal-frame-20261023`。本片修复受控环境候选的映射法线，不改原角色直接光、原模型/纹理、地图/碰撞、玩法或唯一试玩包。

## 修复

前片候选使用归一化后的 T/B，且先缩放 normal-map XY 再重建 Z；这与当前运行引擎的 [Godot a13da4feb Forward+ 处理](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl) 不同。

新增独立 `source_normal_frame.gdshaderinc`：保留插值 TBN 的长度与 handedness，从最终 NORMAL_MAP 的 XY 重建 Z，以 NORMAL_MAP_DEPTH 在原法线与 TBN 映射向量间混合，最后归一化。直接读取最终 NORMAL_MAP，也覆盖眼球投影修改及没有法线纹理时的平面默认值；退化帧提供有限保护，不将病态输入保护宣称原引擎等价。

`SourceCharacterEnvironment` 的环境法线调用该函数，后续 Source／游戏方向转换、RGB 软法线、布料/发丝 BRDF、原材质绑定级开关不改。这里完成的是 **Godot 运行时映射法线一致性**，不是 Source 2 各向异性切线、骨骼算法或完整材质等价证明。

## 可执行验证

独立入口：`res://scenes/tests/CharacterNormalFrameProbe.tscn`，参数 `--evidence-dir <目录> --normal-cases <CPU JSON>`。`tools/source_normal_frame.py --output <JSON>` 生成独立 CPU 对照。

- **216** 组 CPU/GPU：非单位 TBN、两骨骼线性混合、正负 handedness、深度 0/0.5/1/2、平面／非平面／超单位 XY；GPU 编码法线最大绝对误差约 **0.000487**，阈值 0.002。
- **48** 组实际角色：六角色 × 两种 run 姿势 × 四档 normal strength；第二姿势加非均匀模型缩放，眼球参数沿用原控制器跟随。使用同一个绑定材质，仅切换光照输出，在引擎处理后的 `light() NORMAL`、新重建、旧重建之间对照。**48/48 新结果像素误差为 0**；旧算法 **43** 组有可测差异，整图均值最大约 **0.002021**。有效对照不是只将同一公式写两遍。
- SSAO 独立 Forward+ 正负对照：同一受遮挡接收面，内建间接光在开启 SSAO 后产生约 **0.005307** 整图均值变化；改为候选采用的 EMISSION 合成模式后，变化严格为 **0**。这复现了 SSAO 尚未进入候选的缺口，**没有把“SSAO 不起作用”标为功能修复完成**。
- 上述入口保存 **149 PNG**（角色 144、数值 1、SSAO 4）。三图全身 **72** 组关闭／卸载严格零、**24** 组 hair/眼球跟随、**18** 组墙体遮挡及 **14986** 组六向采样／**243** 组布料数值回归通过，另存 **486 PNG**。

本机证据：`D:/AgentGamePipeline/evidence/character-normal-frame-20261023/`，`frames-final/` 是新增对照，`*-certified/` 为三图。`audit.json` 保存当前候选验证，`delivery.json` 保存 base/head/PR/CI 首次快照及保留的四个导入状态。

冻结候选完整原生 **208**、Python 非 Blender **75**、GdUnit **2/2**、格式/lint、导入/资源合同与 diff 检查通过；18 原模型哈希不变。最终 **635 PNG**；检查 SSAO 正对照、角色法线颜色图及三图近景，无角色缺失或明显合成接缝。四个既存导入文件保留未提交。

## 下一步与边界

下一片实现可分离候选间接项的 SSAO 合成路径，防止重复乘材质 AO 或误改直接光；不能仅凭整体变暗验收。Source 2 原始切线/蒙皮与各向异性空间、真实 per-view、眼球时序、雾/平均色和性能仍需单列。普通游戏与包尚未启用候选；加载策略、C4/观战、AI 运动/难度、最新头 18 场、三图人工试玩和逐图 70% FPS 继续保留。
