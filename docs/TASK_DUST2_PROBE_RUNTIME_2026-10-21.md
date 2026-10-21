# Dust II 原探针坐标、GPU 与角色合成核验

分支 `feat/dust2-probe-runtime-20261021`，基线为 #60 已提交头 `948aa5df0874cb930860f86046bc1e7b1df9ab91`。依赖 #59/#60 的已提交适配器与合成器，不依赖其他工作树 WIP，不等待 CI。私有源数据沿用上片已验证的 Dust II 原包 SHA256 `51d6bb432b6553bfae6c38219a527c5de2464a2b107080f2b8be7d8427ebb885`。

## 实现与发现

Dust II 原视觉使用 Source 2 Viewer **19.2** 导出，顶点保留 Source 世界单位，各世界网格节点已经执行 `(y,z,x) × 0.0254`。它没有 Mirage/Inferno 后来添加的 `OfficialSourceAlignment` 父节点，直接套用两图的 `(x,z,-y)+offset` 会把探针放错位置。

新增 `SourceVisualAlignment.resolve`：原明确根节点路径继续沿用 #59；旧格式必须另传显式私有合同 `source-world-visual-alignment-v1`。合同绑定关卡 ID、权威原 VPK SHA256、实际实例场景路径及整个原视觉文件 SHA256，要求三个不同的相对网格路径、Source 顶点包围盒与一致的有限等比世界变换。拒绝绝对/逃逸/属性路径、重复/缺失节点、错误资产/关卡/包哈希、错位/缩放及混入另一种对齐根的歧义；未提供合同不会自动猜轴向。只读取实际节点，不更改原图、碰撞、路网或根变换。

本机 `prepare.py` 对未修改 GLB 的三组原矩阵和全部 POSITION accessor 的联合包围盒，与 Godot 实例数据独立核对，再生成私有合同。移动采样金标准使用 #58 已提交提取器的 CPU 算法；旧轴向下游戏 +Z 对应 Source +X，正反视线另行转换，未复用其他地图的方向假设。

两个现有 GPU probe 增加 `--alignment-receipt <json>`；运行时数值 probe 接受对应旧轴向 metadata，并将嵌套异步断言失败传回顶层，防止内层失败仍打印整体 PASS。正式游戏没有调用此路径。

## 验证与证据

本机目录 `D:/AgentGamePipeline/evidence/dust2-probe-runtime-20261021/`：

| 范围 | 本片结果 |
| --- | --- |
| Dust II 世界坐标/六向 HDR | 30 出生点 × 6 = **180** 项；正反坐标与实际 GLB 轴向核对通过 |
| Dust II 移动表面 | **6** 项，三个位置各双向；GPU 片元跟随位置/视线，与 CPU 原图集金标准相符 |
| Dust II 六角色合成 | **52** 项（26 原数值、14 HDR 阶段、12 近/远角色），**50 PNG** |
| Dust II 原图角色诊断 | 六角色、两个站位、基线/双向/移动，**60 PNG** |
| Mirage 原路径回归 | **204** 项（198 六向 + 6 移动）、**60 PNG**，无需旧格式合同 |
| 原资源 | 18 原角色模型哈希不变；未改 Dust II 原视觉、纹理、关卡 JSON 或碰撞 |

Dust II HDR 最大 RGB 向量误差 **0.012906**，判据为 `.01 + .005 × 参考向量长度`，不能混同 8bit 画面检查或将其表述成绝对 `.01`；移动表面最大误差 **0.012654**，小于 `.025`。Mirage 回归对应误差为 **0.001253 / 0.008725**。

已查看六角色近景/远景/移动拼图及原图。近景 3m 保留原地图；40m 为避免遮挡使用隔离背景及正交相机，属于材质合成验证，不签核透视实战远距辨识度。原角色完整动画、多角色与烟雾遮挡、性能仍未关闭。

新增旧格式合同边界在现有一个原生适配器集成测试中验证，未把断言数量冒充新增测试数。完整原生 **207 项 / RUN_ALL_OK**、Python 非 Blender **31 项**、GdUnit **2/2**、GDScript 格式/lint、导入与 diff 检查通过；最终日志无脚本/引擎错误。精确提交/PR/CI 结果记录于本机 `delivery.json`。

## 雾与平均色的继续核查

Dust II 的 `env_cubemap_fog` 为 sky entity 来源，距离 512–9000 Source 单位、最大不透明度 .5，另有高度参数。原 PS 中角色 `g_flFogModificationAmount` 是独立渲染属性，仍没有证据将这两者直接等同，故没有把 .5 填进角色合成器，也未默认开启合成效果。

核查开源 Source 2 Viewer 上游提交 `9b80f485916db6c5fb2dc32fad2bd63fb0c1153d`：[RenderTexture](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/9b80f485916db6c5fb2dc32fad2bd63fb0c1153d/Renderer/Renderer/RenderTexture.cs) 从 VTEX 读取 Reflectivity，[RenderMaterial](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/9b80f485916db6c5fb2dc32fad2bd63fb0c1153d/Renderer/Renderer/Materials/RenderMaterial.cs) 将其作为纹理平均色用于颜色校正。这增加了现有候选的依据，但不构成 Valve 原引擎 `TextureAverageColor` 内部实现或角色 `g_vAvgAlbedo` 绑定的直接证明。源文件快照与原材质/PS 证据分别保存，仍保留 `accept_average_candidate` 与诊断常量雾的显式限制。

## 交付边界与下一片

当前三图均有受控原探针角色合成的局部证据，但正式对局和唯一试玩包未启用/替换。SH1 fallback、真实雾属性、平均色合同、程序化眼球等专用反照率修饰仍待核验。下一片针对这些真实输入继续接入，并将验证推进到完整动画、透视远距、多角色/透明遮挡和成本；发丝环境瓣、眼球远距过滤、软法线/切线仍列在 [待修项](CURRENT_PENDING.md)。

本片 PR 以 #60 分支为 base，当前 workflow 只接受 main，因此不能据本地通过宣称 CI 绿色或合并就绪。转 main base 后仍须在当时精确头运行 CI 和要求的复审。四个既有 `.import` 改动继续保留，不纳入功能提交。
