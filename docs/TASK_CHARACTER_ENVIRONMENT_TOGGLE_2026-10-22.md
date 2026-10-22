# 角色候选关闭恢复与渲染合同核对

基线 main `5be8fc4b08f808ad8ae25f894d48edb6887e721c`（#69 合并），分支 `fix/character-environment-toggle-20261022`。仅修改受控候选的绑定开关及验证工具，未改地图、原模型/纹理、玩法或试玩包。

## 关闭残差的定位和修复

前片 18/72 组全身候选在 `source_env_enabled=false` 时仍有少量像素差异。本片对同一 Dust II 远景 CT 逐项消融：原材质对象、共享原 shader 的材质副本、同代码新 shader、只加声明、零值 EMISSION/RADIANCE/IRRADIANCE、读取 NORMAL_MAP_DEPTH、完整候选关闭态，以及反向分配材质副本。

原材质对象误差为零；**共享原 shader、参数不变的材质副本也复现相同残差**（整图均值约 0.00000161），其余替换项相同。因此已经将复现条件缩到材质副本绑定，不再把它归因于候选的 SH/BRDF/透明或环境输出公式。Godot 不透明排序键包含 shader/material ID，是可能机制；尚未证明具体重叠面与排序的全部关系，不能将此推断写成底层排序问题已完整定因。

新增 `SourceCharacterEnvironment.set_enabled(bool)`：

- 关闭：恢复 attach 前**同一个 surface override 对象**，包括原本为 null 的情况；保留已准备的候选及原输入。
- 开启：只在表面仍属于本次绑定时恢复候选；重复开启/关闭返回零，不重复绑定。
- 其他代码已接管该表面时跳过；关闭、开启和 detach 都不覆盖新 owner 的材质。

全身验证改为使用该接口，关闭判据从 0.00001 收紧到**严格零**。原始 shader uniform 关闭仍保留材质副本，不承诺逐像素相同；它只用于消融/数值诊断，不能替代材质绑定级关闭。未通过隐藏/丢弃几何或修改原资源消除差异。

## 证据及边界

私有证据：`D:/AgentGamePipeline/evidence/character-environment-toggle-20261022/`；三图 `*-certified/`、消融 `ablation-final/`、`audit.json` 及 `delivery.json` 分别保存数值/截图、本机结果及提交/CI 首次快照。消融入口为 `res://scenes/tests/EnvironmentToggleAblation.tscn`，沿用全身探针的输入参数；最终包含 11 个替换项及基线，共 12 PNG。

验收合同：三图六角色 72 组关闭与卸载均须逐像素恢复，开启仍有非零视觉效果，重复切换幂等，18 组墙体遮挡保留；继续回归前片 24 组 hair/眼球跟随、14986 组六向采样及 243 组布料数值。headless 覆盖 null/显式原 override、重复开关、开启态和关闭态外部接管。完整原生/Python/GdUnit、格式/lint/资源规则及 18 原模型哈希在当前候选上复验，最终实数见审计收据。

三图运行结果：**72/72** 组关闭和卸载误差均为 **0**；18 组墙体遮挡保持通过，原数值及 hair 回归通过。三图 **486 PNG** 加消融 **12 PNG**，检查 Dust II 原残差远景和 Mirage/Inferno 开启近景，无角色缺失或明显合成接缝。未将画面检查当作原引擎等价或完整比赛验收。

冻结候选的完整原生 **208**、Python 非 Blender **71**、GdUnit **2/2**、格式/lint/资源合同及 diff 检查通过；**18** 原模型哈希不变。四个既存导入文件仍保留未提交，原始资源与私有消融数据不加入 PR。

## 环境遮挡与切线核对结果

另读取当前 Godot `a13da4feb` 的原渲染源码，不以其他版本的记忆代替实现：

- [Forward+ 片元阶段](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl) 中 normal-map 使用未归一化插值 TBN，并将 NORMAL_MAP_DEPTH 用于几何法线与映射法线向量的混合。本候选目前预先归一化 T/B，且以缩放 XY 后重建 Z 处理深度，二者不完全相同。下一片应以骨骼动作、非单位插值 TBN、不同 normal strength 的 GPU 对照修正重建合同；本片没有悄悄改直接光或宣称蒙皮切线已完成。
- 同文件在后续阶段合并 SSAO，再作用于内建间接项；最终 emission 单独相加。当前候选通过 EMISSION 合成，不能自动获得该阶段的 SSAO。已有材质 AO 一次生效与墙体深度测试，不能替代此缺口。
- [不透明排序键](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.h) 的 shader/material ID 与本次材质身份实验一同保存在本机；引用仅用于解释可能机制。

下一片修候选的 TBN／normal depth 重建并验证蒙皮动作，另确定可验证的环境遮挡合成路径；原 per-view、眼球时序、雾/平均色、正式启用与性能仍单列。加载策略、C4/观战、AI 运动/难度、最新头 18 场和三图人工试玩不因本片通过而关闭。
