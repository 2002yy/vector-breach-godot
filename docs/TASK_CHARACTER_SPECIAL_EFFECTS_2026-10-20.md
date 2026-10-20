# 角色专用效果续修进展

分支 `fix/character-special-effects-20261020`，基线 `74f353f1c489e3ee8ca9f316e2693bd6f438f870`。提交、独立包、哈希及验证收据见私有证据目录 `delivery.json`；未取得当前头 CI、独立复审或合并，不声明全部角色修复完成。保留原有四个 `.import` 改动，不纳入本片。

## 已接入候选

逆反射使用 `csgo_character.vfx` 原 `F_RETRO_REFLECTIVE` 与 `g_tMetalness` 红通道，不能用绿色金属通道或发光替代。直接高光采用 `normalize(mix(N, L-reflect(-V,N), mask))`，保留原漫反射 NoL。来源为 [固定版 VRF pbr](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/54279ec226cc3e1c561b10f11f0f5e879b981e6e/Renderer/Shaders/common/pbr.slang) 和 complex 的角色通道分配；这属于查看器重建算法移植，未取得 Valve 实机同灯光金标准。

发丝直接光使用原 SSS 红通道（皮肤仍为绿通道）、原两轴粗糙度和 roughness scale / shift / transmission。按原编译 PS 的规则移动较宽高光轴、混合第二瓣高光，并使用 .046 反射率和原发色。环境第二瓣仍开放，不能据此关闭完整发丝条目。

眼球使用原 EyeAlbedo RGBA、EyeMask 红通道与球面射线求交，接入虹膜缩放、瞳孔、色相、饱和度和角膜法线。三套角色眼球/目标骨骼跟随动画，使用原左右外斜参数和注视限幅。`prepare_character_eye_bindings.py` 对每个模型的 86 个对应绑定骨骼拟合已知转换及身高归一化，三模型最大残差低于 1.1 微米；原半径 .6 分别校准为约 13.82–13.91 mm。保存原导出/GLB 哈希，运行时另核验三根绑定骨骼位置，不能猜测头部中心或把源单位当米。

另修正球面各向异性极轴映射为 Source +X → 游戏 -Z、+Y → -X、+Z → +Y；原骨骼/导出骨骼配对支持该转换，但尚不代表蒙皮切线空间完全等价。

`prepare_character_shading.py --profile eyes` 独立保存原 VTEX 解码、哈希与完整 VMAT，不重写原模型、原纹理或旧 special/shading sidecar。新契约含 24 唯一材质、37 张专用纹理；18 个真实模型绑定从 37/63 增为 40/63。缺少校准时眼球保持关闭；没有新契约则沿用旧契约，不完整纹理不安装对应 Shader，headless 不创建 GPU 材质。碰撞、路网和命中模型未改。

## 当前证据与限制

私有目录 `D:/AgentGamePipeline/evidence/character-special-effects-20261020/`：

- `gpu-eyes-final/pixel-checks.json`：Forward+ Vulkan 27 项通过，包括原 7 项、逆反射 4 项、发丝 6 项与眼球 10 项。眼球负对照覆盖错误通道、零半径、射线未命中、零权重及虹膜 Alpha 为零时眼白不改色。
- `actual-bindings.json`：18 真实模型、63 材质定义、40 专用着色器绑定通过。
- `actual-eyes-final/`：三角色 × 静止/头骨旋转/整角色位移旋转缩放 × 开关，18 张；断言实际眼球中心跟随骨骼，半径随模型缩放。已审看精英叛军开关、黑狼转头和凤凰正面，虹膜/瞳孔恢复，未见漂离眼眶。
- `actual-final-vulkan-v2/`：眼球接入前的 67 张全角色/双臂/动作/5v5 与光照对照。发丝仅开关近景已查看；不能把该旧批次作为眼球后的全面回归。
- 完整原生 13 套件共 206 项，`RUN_ALL_OK` 且无 ERROR；Python 非 Blender 全套 31 项、GdUnit 2/2、Ruff、6 份修改 GDScript 的 lint/format、资产层/元数据/运行契约和 9 个正式 GLB 验证通过，`git diff --check` 通过。
- 独立 PCK 的 Forward+ Vulkan 27 项像素检查、18 张眼球对照与 67 张全角色/动作/双臂/5v5 通过。实际 EXE headless 启动退出 0，无 ERROR。不是仅验证源码后就推定包一致。
- 同一 Steam manifest `2520908610273941189` 的 features/PS/PSRS/VS 四份 VCS 已提取并通过 VPK CRC，收据 `native-shader-receipt.json`。现已解出 features KV3、指定 PS 与蒙皮 VS 变体，不是仍未取得发丝/距离算法。原文件与反编译片段仅存私有证据目录。
- 早期 Compatibility 真角色探针在退出时报两份 349524 字节纹理泄漏，逆反射批次已有。Forward+ 最终样本无此错误；Compatibility 退出泄漏仍开放。
- 独立包目标 `C:/Users/Zhang/Documents/VectorBreach-builds/VectorBreach-character-special-20261020/`；三张冻结碰撞源必须随目录保存并核验哈希。桌面旧入口未自动更换。
- 保留本轮失败 `pack-flow.log`：旧 `ClassicMapsUIProbe` 仍查找改版前 `SettingsButton` 路径，不是有效的当前大厅验收。改用已适配大厅的 `three_map_flow.gd` 复测，最终以 `pack-flow-final.log` 与交付收据为准；旧探针失配单列待整理，没有修改生产菜单去迎合旧路径。
- `pack-flow-final.log` 三图连续流程通过：选图/大厅、帮助展开、购买帮助、开始、死亡观战/切换及返回，15 张留证；每图实际 9 个 AI。最终包绑定审计 63 条定义/40 Shader，包括发丝和眼球启用及对应纹理检查。用户设置已有同目录时间戳备份，流程后逐字节恢复。

## 未完成与下一片

- 眼球：近景采样与骨骼绑定已接入，远距导数抗混叠和原引擎同灯光金标准仍开放。
- 发丝：直接光已接入，原环境第二瓣和完整照明等价仍开放。
- 远距对比度：原编译 PS 已找到后照明/雾阶段规则，400–1400 源单位距离平滑权重、原 exposure、平均反照率、周围光照与对比强度共同参与。Godot 阶段及输入尚未接齐，仍未实现；不能用 ALBEDO 上的自拟提亮冒充恢复。
- 原环境 BRDF、皮肤软法线近似和各向异性骨骼空间等价缺口继续保留；本次逆反射只影响直接光。
- 三图逐区人工验收、逐图 70% FPS、18 场长局及连续试玩仍开放。本片探针不能替代；CI、独立复审与合并状态不沿用旧头结果。

下一执行片为远距对比度的环境输入与渲染阶段接入。用户追加加载、C4、观战、AI 运动体验另见 [试玩反馈](PLAYTEST_FEEDBACK_2026-10-20.md)，尚未修复，不撤销角色优先级。
