# R37 雷达原字节 PCK 验证

基线 f8cda2d。默认 Windows all_resources 导出不构成原字节契约：RadarAtlas 使用 FileAccess 读取 atlas.json、PNG、level JSON、原碰撞 GLB 与原 .import 的哈希，常规资源导出会将导入资源转换/重映射。仅添加 PNG include_filter 无法证明原 GLB 与 sidecar 身份完整，因此本批不修改 export_presets.cfg，也未生成正式试玩包。

新增独立作者工具 `tools/authoring/check_radar_pack.gd`，用 PCKPacker 明确纳入三图 v4 清单、26张PNG、三份level JSON、原碰撞GLB和.import，以及RadarAtlas脚本，共39文件。build 使用新路径防覆盖。check 必须从只有检查脚本与project.godot的空项目启动，挂载前断言RadarAtlas不存在，排除工程目录回退；挂载后真实异步校验三图来源并逐张解码26切片，缓存不超过2张。

本机证据 `D:/AgentGamePipeline/evidence/radar-player-package-20261028/package/`：build/check均EXIT0，RADAR_PACK_READY maps=3 slices=26。独立缺失layer-00的负包触发texture_identity_mismatch，未错误放行。results.json绑定两个PCK的SHA256；check_missing.log包含预期缺失文件诊断。正包359,490,460字节，负包359,414,160字节；大部分为原碰撞源，不能把此验证包直接重复附加到正式分发而忽略体积。

执行：在完整工程以Godot headless --script该工具 -- build <新的pck路径>；将同一脚本复制至空项目check.gd，使用空项目--path、--script res://check.gd -- check <pck路径>。负测用build_missing/check_missing。该包仅证明明确原字节清单可以从PCK工作，不证明标准Windows导出已修复，也不包含游戏完整可玩资源。

后续正式整合方案：把这些精确路径纳入现有最终打包清单，在最终产品PCK中一次保存原字节，或将仅缺失的身份文件与雷达数据写入独立附包并在主场景前挂载；必须通过真实最终PCK/EXE三图校验后才放行。诊断PCK内的RadarAtlas源码只为在空项目执行验证；正式附包必须仅含资产，不能用诊断源码覆盖产品脚本。不得额外复制全部 ignored original assets。需先评估重复原GLB的体积成本，再决定源身份清单的长期架构。本批未修改生产渲染/资产/参数；真实EXE、缺失全atlas回退、损坏sidecar及GPU/FPS仍待独立验收。
