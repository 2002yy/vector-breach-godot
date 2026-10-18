# 经典图道路上方灰色悬空面修复

基线：main `0001baef315ca0f63f1aece7d069f09be0c2e328`。分支 `fix/classic-effect-surfaces-20261018`。用户要求修复上轮已记录的道路建筑边缘异常。

根因证据：Mirage B 路中段相机 `(21.62959, 1.694787, -14.9331)`，逐三角形射线命中 `n0_lr0_c0_s_cb_nomerge5_dust_002_meshset_0` 的 `dust_002`。原始 VMAT 使用 `csgo_effects.vfx`，有原生透明通道、多个遮罩、滚动和深度羽化参数；glTF 中没有 `alphaMode`，导出基础色 PNG 仅 RGB 全白。Inferno A 路后段 `(32.64179, 5.197999, 36.48764)` 的同类灰条对应本图唯一同着色器材质 `steam_001`，源参数要求加色混合、遮罩和透明度 0.75。源码适配后同视角灰面消失，保留原几何、UV、植物和建筑。

修复：`tools/prepare_source_effect_materials.py` 从原 VMAT 元数据找出四个输入，用已有 Source2Viewer 20.1 原生解码 VTEX，另存私有 `source-effects/` 和 `source-effects.json`。运行时 `SourceEffectMaterials.gd` 仅在原版地图的视觉资源旁有可用清单时，为指定材质设置实例表面覆盖；缺资源保留原材质，不修改共享材质、glTF、碰撞或路网。`source_effect.gdshader` 采样原生 alpha、三张遮罩及其 UV 滚动，区分普通透明混合与蒸汽加色混合。没有绘制新贴图、删除未知灰面或改动冻结基线。

已知边界：这是 Godot 特效适配，并非完整 Source 2 着色器移植；深度羽化、菲涅耳和距离渐隐尚未逐项重现。灰尘/蒸汽仍有原特效面和动画遮罩；不能将“灰板消失”扩展为所有特效或全图材质验收通过。

遮挡联动：旧 Inferno 遮挡生成器只看 glTF `alphaMode`，把这些错误标为不透明的特效面也烘进去。生成器现在按源着色器排除 `csgo_effects.vfx`；私有遮挡从 59305 面降至 59145 面，旧资源备份在证据目录。原视觉和碰撞不变，冻结 JSON 无需重编。

本机资源安装命令（两图分别执行，将 `<map>` 换为 `mirage` / `inferno`，工作目录必须是新的）：

```powershell
python -X utf8 tools/prepare_source_effect_materials.py --visual assets/local_reference/classic_maps/<map>/official/source_visual/map.gltf --resources D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016/game_loose/csgo --decoder D:/AgentGamePipeline/reference-assets/cs2-official-maps-20261016/tools/source2viewer-20.1/Source2Viewer-CLI.exe --work D:/AgentGamePipeline/evidence/classic-effect-surfaces-20261018/<map>-inputs
```

Mirage 解码四张、Inferno 两张去重原纹理，源 VTEX/新 PNG 哈希见各 `receipt.json`。原始 glTF、bin、已有 PNG、独立碰撞及路网应逐项保持哈希。Inferno 另用更新后的 `build_classic_occluder.py` 与 `save_classic_occluder.gd` 重建遮挡，安装前保留旧 `.res`。

证据根目录：`D:/AgentGamePipeline/evidence/classic-effect-surfaces-20261018/`。初轮修复后同 54 视角为 `after-road-edges/`，实际 Vulkan 检查两处原灰面消失。聚焦回归 18 项通过，包括共享原材质不变、几何不删除、不同混合模式、缺私有资源回退。完整原生、最终遮挡对照、导出包与精确 CI/复审状态由该目录交付收据记录；未产出前不能宣称已交付。

下一片：完成此修复的最终包与相邻区验收后，继续原生 2560×1600 三图性能基线。三图完整美术、AI 整场策略、武器/经济及观战仍按后续清单执行。
