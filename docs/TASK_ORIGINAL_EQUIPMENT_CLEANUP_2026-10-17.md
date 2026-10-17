# 原版人物、装备与仓库整理

用户要求确认人物资源来源，继续取得原版玩家双手、枪、刀、C4，保留本项目资产；统一三图性能对照并整理仓库。此片开始于 main `8a11e49`；前序性能 PR #42、#43 已合并，运行行为不在本次文档整理中修改。

## 当前游戏与取得目标

当前六套全身角色来自 Valve CS:GO 角色的社区移植包，保留原网格、UV、贴图与蒙皮；不是从官方安装包逐字节校验出的六套原件。当前玩家手臂从全身网格裁出、重定向本作动作；不是专用原版第一人称完整动作系统。枪、刀、C4 仍是项目现有资产。详情和来源逐套记录在 [角色接入记录](TASK_CS_CHARACTERS_2026-10-16.md)。不得把已取得文件、转换成功与已替换游戏混为一谈。

新增私有取得目录：`D:/AgentGamePipeline/reference-assets/cs2-original-equipment-20261017/`。沿用 [官方地图取得方法](CS_OFFICIAL_MAP_ACQUISITION.md)的固定 app 730 / depot 2347770 / manifest `2520908610273941189`、Steam chunk 验证、原 VPK 条目 CRC、逐文件 SHA-256，不依赖社区 GLB 冒充官方原件。目标包括 AK、M4 消音版、Glock、双方默认刀、C4、共享手臂、默认手套和六套角色；型号与现有项目装备映射须在后续接入前明确。

`seeds.json` 固定原生 `.vmdl_c` 路径，`prepare_equipment_ranges.py` 在地图工具基础上扩展 `weapons/characters/agents` 引用前缀；所有轮次计划单独归档，再通过 `VB_STEAM_RANGE_PLAN` 调用已固定的私有 DepotDownloader。与地图共用局部分卷缓存和 CRC 验证后的 `game_loose`，不覆盖地图的既有完整收据。装备依赖取得进度、缺失、SHA、后续可视转换结果以新目录 `loose-resource-receipt.json` / `receipt.json` 为准。原版动作图、动画事件、着色器与握持转换另需验证，文件到手不代表动作接入。

所有项目原有模型、贴图、装备动作和历史包保留。新 Valve 原件及转换产物只放私有目录，不进入公开 Git；缺失新素材时仍须保留项目原有运行回退。下一执行片为完成原生依赖与导出检查，再做专用手臂和装备握持/换弹/重刺/C4 交互的逐项接入，不能直接覆盖当前可玩包。

## 仓库整理执行边界

先完成只读大小与引用盘点，证据 `D:/AgentGamePipeline/evidence/inferno-performance-20261017/repository-inventory.json`。主要占用为 `.godot` 3,987,215,356 字节（导入与着色器缓存）和 `assets` 3,539,340,786 字节。运行素材、原始工程、`.git`、导入缓存、着色器缓存、所有可玩包和源包均保留。没有为了报出回收数字删除游戏资产。

历史 `.tools` 顶层临时脚本/日志/中间文件、`.godot` 顶层旧截图/日志、旧测试报告归档至 `D:/AgentGamePipeline/evidence/repository-cleanup-20261017/`，保留相对路径。`.tools/lint`、`.tools/weapon-audit`、人物下载依赖的资产锁/目录清单以及最新 `reports/report_19` / `runtime_asset_validation.json` 留在原位。合计归档 447 个文件、32,594,878 字节；这是整理而非磁盘释放。`archive-manifest.json` 记录每个源文件 SHA-256、字节数，可按相对路径恢复。

自动审批拒绝了包含递归缓存删除的整条命令，未执行；随后安全改为全部归档保留。可再生的四个小缓存也在该归档根：`.ruff_cache`、`tools/__pycache__`、`tools/blender/__pycache__`、`tools/tests/__pycache__`，共 527,214 字节。用户选择自行删除；截至本片检查未由 agent 删除。删除这四项不影响游戏、源码和模型，需要时由工具重建；不要扩大到整个归档根或 `.godot`。

`.gitignore` 增补 `.ruff_cache/`。清理后没有运行资源路径改动、没有受跟踪源码删除；文档和忽略规则用差异/范围检查验收，不为其重复生产全套。三图当前测量与优化策略见 [性能记录](TASK_INFERNO_PERFORMANCE_2026-10-17.md)。
