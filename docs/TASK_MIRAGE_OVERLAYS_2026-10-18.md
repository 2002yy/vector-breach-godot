# Mirage 贴地与墙面 overlay 悬空修复

基线 main `84238961e82f55d5e89058dd076d173ef09e385d`，分支 `fix/mirage-low-floating-surfaces-20261018`。用户继续试玩发现大量较低的悬空面，位置为 Mirage 出生地前往对方的路上。用户提供六张实际游戏截图，覆盖路沿/台阶、井盖、门槛、地面纸片、坡道和室内门洞墙面。该反馈重新打开 Mirage 材质验收；PR #47 只验证了灰尘/蒸汽高处特效，不能覆盖这批问题。

证据目录 `D:/AgentGamePipeline/evidence/mirage-low-surfaces-20261018/`，用户原图保存在 `user-report/`。已在原可玩 PCK 复现与用户相同的楼梯旁井盖：`down-before/mirage-classic-local-site-b-0.25-0.png`。相机 `(40.01958, -0.755213, -32.86644)` 向下观察。逐三角形射线命中 `n0_lr0_c293_s_mesh_overlay293_meshset_0` / `manholecover01` 和 `n0_lr0_c9_s_mesh_overlay9_meshset_0` / `sanddecal01`，后面还有真实 `tilefloor01` 与 `curbs001` 表面，详见 `trace-before/views.json`。

源 glTF 有 301 个名称含 `mesh_overlay` 的节点，多数源 VMAT 标有 `F_OVERLAY`。这批网格包含已裁切、不同方向的多个贴花片段，不可整张图按统一高度下移，也不能把整个网格粗略当作一张矩形贴花。下一步量化每顶点相对真实承载表面的距离、方向、UV 和材质语义，再选择保留原三角形/UV/纹理的适配方式；未验证前不删除网格或把几处相似画面算成用户问题已关闭。

## 已确认的原因与修复

原导出器 [20.1 的 Mesh 代码](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/20.1/ValveResourceFormat/IO/GltfModelExporter.Mesh.cs#L23) 把 `OverlayNormalOffsetDistance` 写为 `0.01f / 0.0254f`，并逐顶点执行 `position + normal * offset`，实际增加约 0.3937008 米。原始非 overlay 三角面 BVH 测量 7400 个有效顶点，其中 6838 个约离承载面 39 厘米，与源码和用户截图相符。`overlay-offset-measurement.json` 保存全部 301 个 overlay 表面的结果；边缘射线未命中不被计为有效距离。

`prepare_source_overlay_offsets.py` 校验既有 glTF 收据和导出器版本，复用上游 `IsMaterialOverlay` 的 F_OVERLAY / F_DEPTHBIAS / F_DEPTH_BIAS / static_overlay 判定，生成私有 `source-overlay-offset.json`；若同名材质的 overlay 判定不一致则拒绝生成。两图当前无同名歧义，Mirage 73 个材质对应 301 表面，Inferno 23 个材质对应 263 表面。

运行时 `SourceOverlayMaterials.gd` 对这些原材质做实例表面覆盖，复用原 PBR、UV、透明通道和纹理，用 Godot `grow` 沿法线抵消过大偏移，仅留 1 mm 防止闪烁。共享原材质、原网格、PNG、碰撞与冻结 JSON 保持不变；按实例缩放扩张剔除边界，避免渲染顶点移动后在边缘消失。遮挡生成同时排除 overlay，它们不能作为实体遮挡面。

初轮同视角源码验证 `down-after-corrected/`：48 张俯视样本，井盖和沙土浮片已落回地面。聚焦测试 19 项通过，覆盖原资源不变、纹理 alpha 保留、墙地旋转、非均匀缩放剔除边界、共享覆盖缓存、重复应用和缺清单回退。最终包、全套测试和当前头远端检查尚待交付收据闭环。

失败证据保留：初始脚本类型推断错误；随后把 Godot 启用属性误写为 `grow_enabled`，实际属性应是 `grow`。这些运行虽可退出 0、输出截图，但带脚本错误/警告，不能作为通过证据；`down-after/`、`down-after-fixed/`、初始 focused/import 日志均保留。最终验收同时检查退出码、通过标记及无脚本错误，不只看退出 0。

执行验收：用户六种地标的修复前后同视角；补查双方出生点互通路线、俯视路沿/楼梯和室内墙角；原 UV/PNG/碰撞/路网与角色资产保留。新增有意义的几何或投影回归，完整原生与实际 Vulkan/PCK 验证，再提交、推送、当前头 CI/复审和合并。最终结果、仍未覆盖处与包入口必须写回状态页和交付收据。

性能工作保留：此前已完成双方三图共六份窗口/全屏诊断样本，目录 `D:/AgentGamePipeline/evidence/classic-performance-20261018/`。探针记录 Window.size 为 2560×1600，但实际输出纹理 PNG 为 2560×1440，存在画布比例/留边问题；因此这些样本仅用于诊断，不作为严格 2560×1600 或 70% 达标证据。修复材料后须核对实际渲染纹理尺寸、屏幕尺寸及画布缩放，再继续 CPU/GPU 基线和优化；不可丢弃本轮异常或混用不同画质成绩。
