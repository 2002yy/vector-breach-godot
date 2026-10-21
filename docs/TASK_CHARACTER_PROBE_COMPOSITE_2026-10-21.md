# 原探针驱动的角色后照明合成

分支 `feat/character-probe-composite-20261021`，提交基线为 #59 的 `d0747ce6152acee458190ddb6f7c2cae75b079e9`。这是明确依赖已提交运行时适配器的续片，PR 以 `feat/map-probe-runtime-20261021` 为 base；没有依赖其他工作树未提交代码，也不等待 CI 才继续开发。main 仍为 `2e0187874c500004ac517bab7cfd9d625f5024eb`。

## 实现与保留规则

`SourceCharacterPostlit.gd` 将 #59 的地图身份/坐标/图集检查和逐片元双向 LPV 采样接到 #56 的原距离对比度公式。新的合成 pass 读取照明后的 HDR 屏幕值，保留原角色 base texture、UV 缩放/偏移、染色、遮面方式和 opaque 曝光反转规则；不是用纯辐照度替换角色颜色。

必须显式配置 `purpose=diagnostic`、`accept_average_candidate=true`、`fog_input_kind=diagnostic-constant`，并提供有限范围内的强度/雾修改量。私有输入合同须与旁存 `source-materials.json` 哈希一致，材质名及完整原 VMAT 参数须匹配。输入不足、图集失效、覆盖不足、强度/雾为零或距离不超过 400 Source 单位（10.16m）时保留已有帧。未制造 SH1 fallback，也未默认开启到正式游戏。

每个合格不透明表面建立独立辅助 draw。保留原 ShaderMaterial 实例及眼球控制器的实时引用，复制原表面数组/蒙皮权重/全部形变，绑定同一 Skin/Skeleton；逐帧同步 blend shapes。支持 T 角色四表面/三形变模型。重复附加不叠加；卸载只移除自有辅助节点，外来 overlay 不受影响。原版 18 模型 SHA256 全部保持不变。新增几何副本/绘制成本尚未做性能验收。

当前用于公式的逐片元反照率是 base texture × 原 UV/染色；尚未重建眼球程序化 UV、湿润或顶点混合等专用效果对该输入的全部修饰。原材质这些效果仍参与被读取的照明结果，但不能据此宣称合成的反照率输入已完全等价。

## 平均色与雾：继续单列

- 原 PS 的 `g_vAvgAlbedo` 来自 `TextureAverageColor(g_tColor)`。30 个材质的 VTEX reflectivity 与解码 PNG 线性平均色对照，最大单分量差约 **0.008322**，平均约 **0.001812**。这支持“线性平均色候选”，仍不能证明编译器/运行时采样合同完全一致。受控绑定保持候选标签及显式开关。
- 原 PS 将 `g_flFogModificationAmount` 声明为 `FogModificationAmount` 渲染属性、默认 0，但未携带可恢复的动态绑定表达式。不能把地图雾不透明度直接当作该值。本片使用显式诊断常量 1，仅验证合成；原雾输入仍未关闭。
- Dust II 的目标 manifest 为 `118363704811264052`，目标 VPK SHA256 为 `51d6bb432b6553bfae6c38219a527c5de2464a2b107080f2b8be7d8427ebb885`。单文件匿名下载被 Steam 拒绝旧 manifest 访问，未替换成错误版本。
- 用户表示本机 Steam 已登录后，已核实正在运行的 `C:/Program Files (x86)/Steam/steam.exe`，并检查其登记的 C 盘/D 盘库、steamapps 下载内容/缓存及常见资源/备份目录。两个库都没有 CS2 `appmanifest_730.acf`，未找到 `de_dust2.vpk`。独立下载器支持手机 Steam QR 登录，但客户端现有登录不会自动认证独立工具；未读取或迁移登录令牌/密码。后续需独立交互认证后再尝试目标单文件，不能盲目整 depot 下载。

## 验证与证据

本机目录：`D:/AgentGamePipeline/evidence/character-probe-composite-20261021/`。

- `CharacterProbeCompositeProbe.tscn`，Mirage/Inferno **各 52 项**：26 原数值、14 HDR 合成阶段、12 六角色近/远检查。14 项覆盖零强度/雾/输入/覆盖、明暗双向采样、曝光阈值、材质调整关闭与全局效果、HDR 和黑色贴图。
- 两图各 **50 PNG**（14 阶段、36 六角色基线/合成/平移），已查看两图六角色对照拼图及原图。近景 3m 使用真实地图背景；远景 40m 为避免地图遮挡，隐藏关卡画面，以同一真实探针位置和受控照明单独验证角色材质。使用正交相机，不能据此签核透视远距辨识度或实战表现。
- 多表面 Skin/Skeleton/形变数量在原角色场景中逐项断言；独立微型变形表面验证真实 process frame 上的 0.4→0.8 同步。只拍摄对象平移，没有声称完整动画/多角色/烟雾遮挡通过。
- 在已有原生适配器测试内新增 8 组复合边界；仍计一个集成测试，不把断言组数冒充新增测试数。完整原生 **207 项 / RUN_ALL_OK**、Python 非 Blender **31 项**、GdUnit **2/2**、GDScript 格式/lint、Godot 导入和 diff 检查通过；相关日志无 `SCRIPT ERROR` / `ERROR`。提交/PR/CI 收据在本机 `delivery.json`。
- 有效最终 GPU 日志为 `mirage-final.log`、`inferno-final.log`。早期单表面/跳过形变版本确实失败，原因和日志保留；已改为逐表面辅助 draw + 形变跟随，并增加嵌套断言失败向顶层传播，不能只凭退出码或 PASS 字样判定。

## 下一片

优先恢复 Dust II 原包及其照明输入，确定原 `FogModificationAmount` 与 `TextureAverageColor` 的真实绑定，再进行完整动画、多个角色/透明遮挡、透视实战对照与帧率成本评估。发丝环境瓣、眼球远距过滤、软法线/切线仍按 [待修项](CURRENT_PENDING.md) 单列。唯一试玩包未覆盖；本片是可审核的受控诊断实现，尚不属于正式距离对比度已完成。
