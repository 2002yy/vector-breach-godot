# 原反射数组：游戏空间选择与混合

## 当前交付与范围

分支 `feat/character-reflection-runtime-20261022`，base 为 main `a00f81958a9a640083a5762a00f61efc07880e37`（#65 已合并）。#65 精确头 `69fc7e3` 的 Tests `39601697845`、Windows export/smoke `39601697868` 成功；main 合并后 push Tests `39641681474` 首次查询仍在执行，不等待它开始本片。

本片新增显式反射适配器，将已验证 BC6H 原数组用于实际视觉根节点的 Source→游戏坐标、逐片元盒投影和重叠混合。没有更改原模型、地图/碰撞/路网或正式角色材质，没有更新当前试玩包。

## 规则与入口

- `SourceReflectionDiagnostic.gd` 验证地图身份、原 VPK 哈希、视觉对齐、原数组编号覆盖、支持的探针记录与压缩数据哈希；只有调用者明确传入 `diagnostic=true` 才上传。重配/取消上传保留上传所有者，清空时失效已绑定材质，防止上一张图的纹理残留。
- `source_reflection_sampling.gdshaderinc` 接收真实世界坐标和反射方向，转换到 Source 坐标后逐片元选择和采样；保留原七级 mip，采用线性纹理/mip 过滤。
- 规则依据固定 VRF `54279ec226cc3e1c561b10f11f0f5e879b981e6e` 的 [Scene.cs](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Renderer/Scene.cs) 和 [environment.slang](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Shaders/common/environment.slang)，不是把漫反射 LPV 的混合直接套过来：优先级降序，同级按原数组编号升序；盒边界扩大 0.02 Source 单位，逆边宽为 `1/(edge_fade+0.02)`；总量从 0.01 开始，smoothstep 权重乘剩余总量，大于 0.99 后停止。辐射权重不重新归一到 1。
- 当前只支持原三图已恢复的 `env_combined_light_probe_volume`、无父级且单位缩放的 yaw 变换；遍历动态点的几何候选，不实现烘焙对象 handshake 可见掩码。仍是查看器规则的受控移植，未证明与原引擎完整反射路径等价。

## 查验结果

证据目录：`D:/AgentGamePipeline/evidence/character-reflection-runtime-20261022/`。CPU 独立参照由 `tools/prepare_reflection_world_cases.py` 生成，使用原出生点、每个原探针七个边缘/内外位置及远离所有探针的位置；GPU 从加载后的真实地图视觉根取得对齐，Dust II 继续使用三锚点/哈希 receipt。

| 图 | 世界坐标/选择签名 | 多探针样本 | 最大签名轴误差 | 分数 mip 最大归一化误差 |
| --- | ---: | ---: | ---: | ---: |
| Dust II | 482 | 97 | 0.000488 | 0.002641 |
| Mirage | 605 | 153 | 0.000488 | 0.000733 |
| Inferno | 1053 | 230 | 0.001719 | 0.001504 |

合计 2140 条，包括 103 个原出生点的六向样本；签名检查原编号、投影方向 XY 和总覆盖权重，投影 XYZ 及原 HDR 解码另由 #65 的 1953/1890 条检查覆盖。当前分数 mip 检查比较 LOD 3.5 与 GPU 的 LOD 3/4 平均值，误差为 `abs(actual-expected)/max(1,abs(expected))`，设 1% 容差，仅证明本设备过滤的近似一致性，不证明与原 GPU 精确逐位相同。

三图各三张实际地图中移动反射球的截图，加一张签名图，共 12 PNG；已查看三图各中间移动截图：原场景反射可见，粗糙级别区分清楚。球体为原反射辐射的独立显示，未乘角色 BRDF，不代表角色最终观感验收。

## 失败记录与限制

完整本机回归：原生 **208 / RUN_ALL_OK**、Python 非 Blender **57**、GdUnit **2/2**、GDScript 格式/lint、Ruff、Godot 导入/解析、三项资源策略和 diff 检查通过。18 个原模型 SHA256 与源清单一致；仅保留四个既有 `.import` 脏状态，不纳入提交。审计结果为证据目录 `audit.json`。

最初 spatial unshaded 诊断使用 EMISSION 配合黑色 ALBEDO，球体输出黑色，已改用 ALBEDO 并重新截取；背景诊断环境也补了显式环境光颜色。这不是原资源缺失。分数 mip 最初采用绝对 0.01、随后归一化 0.2% 阈值，Dust II/Inferno 失败；最终保留失败日志，记录实测最大值并采用上述 1% 检查，不将失败日志中的成功字样计为通过。另补顶层非空结果断言，防止子协程断言退出后误印成功。

仍缺：原 radiance SH 归一化、原 BRDF 与发丝环境第二瓣、烘焙对象掩码、动态角色实际合成/时序/性能、多 GPU 对照；眼球远距时序、软法线/蒙皮切线、雾与平均色原赋值仍单列。当前包仍停在 #63；最新头 18 场、三图连续人工比赛与 70% FPS 目标均未关闭。

## 重现

先使用 `tools/prepare_reflection_world_cases.py --reflection <reflection.json> --lighting <lighting.json> --output <cases.json>` 生成 CPU 参照，再运行本机 Godot 4.7.1 编辑器：

```text
Godot --path . --rendering-method forward_plus --rendering-driver vulkan --scene res://scenes/tests/ReflectionWorldProbe.tscn -- --input <reflection.json> --goldens <cases.json> --evidence-dir <out>
```

Dust II 额外传 `--alignment-receipt <dust2 alignment.json>`。原资源与运行证据仅在本机忽略目录，不公开提交；普通 release EXE 不支持这个诊断场景覆盖。

## 下一执行片

提取原 VTEX 的 radiance coefficients，核对原编译角色 PS 的归一化/BRDF及发丝第二瓣，再将本片采样器接入受控真实角色材质；不能拿球体截图宣布发丝已修。
