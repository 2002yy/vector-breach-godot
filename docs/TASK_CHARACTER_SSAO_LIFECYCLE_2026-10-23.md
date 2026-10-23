# 角色 SSAO 子视口生命周期

## 基线和范围

分支 `feat/character-ssao-lifecycle-20261023`，基于 main `dab100fac67610f30e8551c8ff9862db131f3592`。前片 #72 精确头 `98f61fba635fab5b8fb3c74bcb2efed7e0d4366d` 的 Tests `39831294276`、Windows export/smoke `39831294129` 全成功且 CLEAN 后合入 main；本片不等待新 CI。四个既存导入改动保留未提交。

新增 `SourceCharacterSSAOOwner.gd`，统一拥有一个受控 SubViewport 内的 SSAO effect、WorldEnvironment 开关同步、窗口尺寸跟随、分辨率/MSAA 重建和卸载。没有改原地图、碰撞、纹理、模型或开启正常游戏候选，也没有更新试玩包。

## 失败、原因与修复

第一版直接监听视口 `size_changed` 并解除纹理绑定，截图数值断言虽然通过，日志仍有 invalid ID，不能作为通过证据。精确 Godot `a13da4feb` 的 `Viewport::_set_size` 先调用渲染服务器释放/调整缓冲，再发出 `size_changed`；因此事后响应已经太晚。保留失败复现 `D:/AgentGamePipeline/evidence/character-ssao-owner-initial.log`。

实际修复改为**拥有重建操作**：窗口尺寸事件只提交目标；owner 暂停采样、恢复白纹理，经过 `frame_post_draw` 屏障后才实际修改子视口。连续请求合并为最后的尺寸/设置。重建后重新发布新切片，首帧使用中性结果，随后恢复当前帧 SSAO。没有通过吞掉错误或整体压暗画面来处理资源问题。

`SourceCharacterSSAO.gd` 为每次分配/失效增加代次。延迟发布必须同时匹配当前代次和开启状态，失效之前排队的回调不能把旧 RID 重新绑回来；解绑还检查材质采样器身份，保留外部接管。owner 的会话代次使取消后重新 attach 不会被旧重建协程修改。`reconfigured(applied)` 明确区分完成与取消。

依据：[Viewport 调整顺序](https://github.com/godotengine/godot/blob/a13da4feb/scene/main/viewport.cpp)、[Texture2DRD 的渲染线程替换](https://github.com/godotengine/godot/blob/a13da4feb/scene/resources/texture_rd.cpp)。本机保留固定提交原文件快照，没有修改 Godot 二进制。

## 接入合同

1. 将 owner 放入目标子视口内，`attach(world_environment, follow_window)`；它保留原合成器并只追加自己的 effect。根 Window 视口明确拒绝，不能声称任意现有视口已自动修好。
2. `bind(material)` 只绑定已有角色环境候选的材质。owner 每帧同步同一 WorldEnvironment 的 `ssao_enabled`；环境资源替换也会失效并重绑。
3. 只通过 `request_size` / `request_render_settings` 重建拥有的子视口；开启 `follow_window` 后真实窗口缩放会自动提交安全事务。禁止外部直接改这个子视口的缓冲配置，也不能同时用自动伸缩容器重新分配它。
4. `detach`、owner/WorldEnvironment/子视口退出会自动退役旧引用，恢复原合成器身份。外部替换的合成器或材质采样器不被覆盖。请求取消通过 `reconfigured(false)` 通知。
5. 固定 Forward+ 单视图诊断；全局渲染质量重建、Camera 环境/合成器覆盖、多视图及暂停/最小化的恢复仍不在验收范围。首帧中性回退是明确行为，不声称首帧已具有完整 SSAO。

## 验证

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method forward_plus --rendering-driver vulkan --scene res://scenes/tests/CharacterSSAOLifecycleProbe.tscn -- --evidence-dir <空输出目录>
```

该入口验证冷启动/四次重建首帧严格中性、预热后与引擎原生 SSAO 逐像素一致、环境开关/资源替换、0.75 分辨率 + MSAA4X、真实窗口缩放、请求合并/取消/重挂、两个同时运行的独立视口、三次自动销毁、外部合成器/材质接管，以及过时代次延迟回调。成功标记必须结合零脚本/渲染错误检查。

三图入口使用 `CharacterOwnedViewportProbe.tscn`，原 `CharacterBodyProbe` 参数改为 `--ssao-owner`，其余反射/LPV/SH/BRDF/原数值输入沿用前片。实际场景、模型、相机都在受控子视口内，不用原根视口截图冒充新路径。

最终统计见 `D:/AgentGamePipeline/evidence/character-ssao-lifecycle-20261023/audit.json`；分支/提交/PR/精确 CI 首次快照见同目录 `delivery.json`。旧手动生命周期与能量隔离入口同时回归；原始失败和中间成功输出均保留，最终以 `qualified-final`、`energy` 和三图 `*-certified` 为准。

最终实际子视口三图 **72** 组角色 SSAO 对照均有作用，绑定级关闭/卸载严格为像素差 **0**；**18** 组墙体遮挡、**24** 组 hair/眼球跟随及原六向/布料数值回归通过。三图 **558 PNG**、生命周期 **69 PNG**、能量隔离 **31 PNG**，共 **658 PNG**，已查看三图角色和生命周期代表图。完整原生 **208**、Python 非 Blender **75**、GdUnit **2/2**、格式/lint、编辑器导入/静态解析、三类资源合同、diff/scope 检查通过，**18** 原模型哈希不变。没有修改冻结关卡 JSON。

## 下一片与验收边界

下一片核对正常游戏渲染入口与资源输入归属，准备受控候选接线；根视口直接调整尺寸不能复用本片的事后信号方案。原 Source 2 per-view、对象掩码/蒙皮切线、眼球时序、雾/平均色、性能，以及加载策略、C4/观战、AI 运动/难度仍按项目状态推进。

最新头 18 场自动赛、三图连续人工试玩与逐图 70% 帧率目标继续待验收。本片自动化和截图通过只覆盖角色候选及其拥有者，不能替代整场或地图完整视觉验收。Dust II 基线天空紫黑外露物件仍单列。
