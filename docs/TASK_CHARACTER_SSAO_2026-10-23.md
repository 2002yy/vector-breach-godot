# 角色候选 SSAO 实际合成

## 范围与基线

独立分支 `feat/character-ssao-input-20261023`，从 main `76337b0c291463ac4b7049f14ea807eb02c93b3e`（#70）开始开发，没有等待 #71 CI。#71 精确头 `12c989b1617c6106aaed83d304bdaf29d6f9c0bb` 的 Tests `39826106691`、Windows export/smoke `39826106732` 全成功且 CLEAN 后，合入 main `d21ba42`；本片随后整合这个已合并基线，重新验证法线与 SSAO 组合。普通游戏、地图/碰撞 JSON、原模型及唯一试玩包不变。

此前候选用 EMISSION 输出已计算的间接漫反射/镜面反射；Godot SSAO 在最终加上 EMISSION 之前完成，因此没有作用到候选。本片只将屏幕遮蔽乘到这两项候选间接光上，材质 AO 仍在原能量计算中恰好应用一次，原自发光与直接光保持原路径。不是最终画面整体压暗。

## 接入与生命周期

- `SourceCharacterSSAO.gd` 是受控、单视图、单视口 CompositorEffect。每个视口必须使用独立实例。主线程通过 `set_requested(environment.ssao_enabled)` 同步开关，`bind(material)` 只绑定已注入 `source_ssao.gdshaderinc` 的候选材质。关闭立即停用采样；`unbind(material)` 恢复白纹理并移除弱引用。
- 精确 Godot `a13da4feb` 的 `render_forward_clustered.cpp` 在 PRE_OPAQUE 回调之后生成 SSAO，最终纹理名为 `rb_ssao/final`。上一帧已经发布的同一纹理切片在本帧不透明着色前被引擎重新写入，采样当前帧结果；移动遮挡物第一帧与稳定后严格相同。
- 首帧没有分配时使用白纹理。跨帧发布 RID，避免在渲染回调内使当前材质 uniform set 失效。首轮直接改 RID 导致资源绑定错误，失败日志保留；不是忽略错误后继续交付。
- **重建/销毁视口前必须暂停、unbind，等待渲染帧完成白纹理发布，再释放旧视口资源。** 重建后先预热再 bind。绕过这个顺序会遇到引擎释放纹理切片后的旧引用，失败复现保留。自动处理窗口重建、多视图、缩放渲染和正式游戏生命周期仍待接入，不能直接启用为正式角色效果。
- 不支持的多视图或缺失内部纹理回退为白。本片依赖固定引擎内部纹理名，不声称跨渲染器/引擎版本兼容；没有新增一遍 SSAO 计算。

引擎依据：[渲染顺序与最终 SSAO 绑定](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp)、[纹理命名](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/effects/ss_effects.h)、[AO 与最终自发光顺序](https://github.com/godotengine/godot/blob/a13da4feb/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)。原文件快照保留在本机 evidence；没有把这些引擎文件加入项目。

## 验证入口与证据

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --path . --rendering-method forward_plus --rendering-driver vulkan --scene res://scenes/tests/CharacterSSAOProbe.tscn -- --evidence-dir <空输出目录>
```

隔离 Vulkan 场景比较引擎原生、旧 EMISSION 和新采样三条路径，材质 AO 为 1/0.4/0。AO=1 时引擎与候选逐像素一致；AO=0.4 时保留 Source 候选的材质 AO × SSAO 策略，不冒充 Godot 原生 `min(AO, SSAO)`。另验直接光/原自发光、移动遮挡物、开关、暂停重建和解除绑定销毁。

实际三图回归使用 `CharacterBodyProbe.tscn` 原命令附加 `--ssao`；六角色、两姿势、近/远距离逐组比较同一候选的 SSAO 开/关，保留原有绑定级关闭、卸载和不透明墙体遮挡检查。数值/hair 回归不因本片忽略。所有日志须同时检查错误与成功标记。

最终统计与检查结果见 `D:/AgentGamePipeline/evidence/character-ssao-20261023/audit.json`；分支提交/PR/CI 首次快照及遗留四个导入改动见同目录 `delivery.json`。CI 查询一次，不等待运行结束。

## 验收边界与下一片

这是 Godot SSAO 输入的受控合成，不等于 Source 2 原 SSAO 算法、原对象遮蔽/烘焙掩码或实际 per-view 等价。#71 的引擎法线帧修正、原蒙皮切线、眼球时序、原雾/平均色仍单列。没有新试玩包，不把截图/自动化算成最新头 18 场比赛、三图人工连续试玩或 70% FPS 验收。

下一片：将视口生命周期与开关同步收敛到显式拥有者，补自动重建/卸载与第一帧验收，再接受控角色环境效果的正常游戏集成。后续加载策略、C4/观战、AI 运动/难度优先级不变。
