# Mirage 贴地与墙面 overlay 悬空修复

基线 main `84238961e82f55d5e89058dd076d173ef09e385d`，分支 `fix/mirage-low-floating-surfaces-20261018`。用户继续试玩发现大量较低的悬空面，位置为 Mirage 出生地前往对方的路上。用户提供六张实际游戏截图，覆盖路沿/台阶、井盖、门槛、地面纸片、坡道和室内门洞墙面。该反馈重新打开 Mirage 材质验收；PR #47 只验证了灰尘/蒸汽高处特效，不能覆盖这批问题。

证据目录 `D:/AgentGamePipeline/evidence/mirage-low-surfaces-20261018/`，用户原图保存在 `user-report/`。已在原可玩 PCK 复现与用户相同的楼梯旁井盖：`down-before/mirage-classic-local-site-b-0.25-0.png`。相机 `(40.01958, -0.755213, -32.86644)` 向下观察。逐三角形射线命中 `n0_lr0_c293_s_mesh_overlay293_meshset_0` / `manholecover01` 和 `n0_lr0_c9_s_mesh_overlay9_meshset_0` / `sanddecal01`，后面还有真实 `tilefloor01` 与 `curbs001` 表面，详见 `trace-before/views.json`。

源 glTF 有 301 个名称含 `mesh_overlay` 的节点，多数源 VMAT 标有 `F_OVERLAY`。这批网格包含已裁切、不同方向的多个贴花片段，不可整张图按统一高度下移，也不能把整个网格粗略当作一张矩形贴花。以下修复由逐顶点相对承载面的测量和原导出器源码共同确定，保留原三角形、UV 和纹理。

## 已确认的原因与修复

原导出器 [20.1 的 Mesh 代码](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/20.1/ValveResourceFormat/IO/GltfModelExporter.Mesh.cs#L23) 把 `OverlayNormalOffsetDistance` 写为 `0.01f / 0.0254f`，并逐顶点执行 `position + normal * offset`，实际增加约 0.3937008 米。原始非 overlay 三角面 BVH 测量 7400 个有效顶点，其中 6838 个约离承载面 39 厘米，与源码和用户截图相符。`overlay-offset-measurement.json` 保存全部 301 个 overlay 表面的结果；边缘射线未命中不被计为有效距离。

`prepare_source_overlay_offsets.py` 校验既有 glTF 收据和导出器版本，复用上游 `IsMaterialOverlay` 的 F_OVERLAY / F_DEPTHBIAS / F_DEPTH_BIAS / static_overlay 判定，生成私有 `source-overlay-offset.json`；若同名材质的 overlay 判定不一致则拒绝生成。两图当前无同名歧义，Mirage 73 个材质对应 301 表面，Inferno 23 个材质对应 263 表面。

运行时 `SourceOverlayMaterials.gd` 对这些原材质做实例表面覆盖，复用原 PBR、UV、透明通道和纹理，用 Godot `grow` 沿法线抵消过大偏移，仅留 1 mm 防止闪烁。共享原材质、原网格、PNG、碰撞与冻结 JSON 保持不变；按实例缩放扩张剔除边界，避免渲染顶点移动后在边缘消失。遮挡生成同时排除 overlay，它们不能作为实体遮挡面。

初轮同视角源码验证 `down-after-corrected/`：48 张俯视样本，井盖和沙土浮片已落回地面。聚焦测试 19 项通过，覆盖原资源不变、纹理 alpha 保留、墙地旋转、非均匀缩放剔除边界、共享覆盖缓存、重复应用和缺清单回退。

最终运行时代码 `fedaf0e683db0c8c9f7088a24b6600625a014ab7` 已导出到 `C:/Users/Zhang/Documents/VectorBreach-builds/VectorBreach-overlay-fix-20261018/`。D 盘不足以同时保留旧包和新包，故本包放 C 盘；旧包、用户当前试玩窗口和原始资源均保留。PCK 实际 Vulkan 三图俯视路线 144 张，以及 Mirage 双方出生点互通水平视角 88 张已检查，加载后修复计数为 Mirage 301 / Inferno 263 / Dust II 0。与用户相同的井盖同视角见 `before-after-manhole.jpg`；实际发布 EXE 启动退出 0。原 glTF、两图 1231 个依赖、三份碰撞及 25 份原版人物/装备哈希未变。GdUnit 2/2、Python 2/2、资产约束、gdlint、Ruff 和 diff 检查通过；完整原生最终日志及远端状态以私有 `delivery.json` 为准。

本轮水平巡检另发现 A 点黑底黄色秒表条带，修复前后均存在，已保留 `cross-spawn-before/` 与 `export-cross-spawn/` 对照，属于后续须核查的辅助材质/实体可见性问题。本片不把它算作已修复，也不把 232 张路线抽样当作全图通过。六张用户图中井盖已精确复现，其余地标仅由路线抽样和同类 overlay 修复覆盖，未声称每个用户相机位置均已重现。

失败证据保留：初始脚本类型推断错误；随后把 Godot 启用属性误写为 `grow_enabled`，实际属性应是 `grow`。这些运行虽可退出 0、输出截图，但带脚本错误/警告，不能作为通过证据；`down-after/`、`down-after-fixed/`、初始 focused/import 日志均保留。首次完整 182 项虽通过断言，但新增 fixture 释放 MeshInstance 时在 dummy renderer 触发 material=null；等待一帧未解决，显式解除测试网格再释放后聚焦日志无错误。这只改变测试清理，运行时代码与已验证包未变；原完整日志保留为 `full-native-before-test-cleanup.log`，重新执行最终全套。最终验收同时检查退出码、通过标记及无脚本错误，不只看退出 0。

执行验收：用户六种地标的修复前后同视角；补查双方出生点互通路线、俯视路沿/楼梯和室内墙角；原 UV/PNG/碰撞/路网与角色资产保留。新增有意义的几何或投影回归，完整原生与实际 Vulkan/PCK 验证，再提交、推送、当前头 CI/复审和合并。最终结果、仍未覆盖处与包入口必须写回状态页和交付收据。

最终清理修正后的完整原生 12 套件共 182 项 `RUN_ALL_OK`，退出 0 且日志无 `ERROR` / `SCRIPT ERROR`；聚焦 19 项亦无错误。包运行时代码与测试清理前相同，未因测试资源释放修正而重复导出。当前分支的提交、PR、CI 和合并结果后续登记在同目录 `delivery.json`，本文件不把尚未发生的远端检查算成通过。

PR #48 首轮复审指出安装工具仅校验 glTF JSON 不能证明外部 BIN 仍为原导出。已补对每个外部 buffer 的收据哈希和本地路径校验；缺收据/内容变动拒绝生成，内嵌 data URI 由 JSON 哈希覆盖。新增缺失、变动、原字节恢复的测试后 Python 3/3 通过。当前实际资源的所有 BIN 此前已包含在 1231 个依赖校验内，因此无需修改运行时、重新生成地图或导出包；该工具变更以聚焦 Python 测试、Ruff 和当前头 CI 验证，不重复未变的本机原生全套。

性能工作保留：此前已完成双方三图共六份窗口/全屏诊断样本，目录 `D:/AgentGamePipeline/evidence/classic-performance-20261018/`。探针记录 Window.size 为 2560×1600，但实际输出纹理 PNG 为 2560×1440，存在画布比例/留边问题；因此这些样本仅用于诊断，不作为严格 2560×1600 或 70% 达标证据。修复材料后须核对实际渲染纹理尺寸、屏幕尺寸及画布缩放，再继续 CPU/GPU 基线和优化；不可丢弃本轮异常或混用不同画质成绩。
