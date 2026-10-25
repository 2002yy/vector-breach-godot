# Movement-4 R1：点位资格、逐点门闸与 v2 重放

增量基线 `c65649d067e16c47ae8d390a1d1ad77e24bfca6b`，原 #96 的 PR 基线仍为 #95 精确头 `b0378218b9ee1a8e51b609bf8e200b9f058a5502`。在原分支 `audit/three-map-movement-points` 修复两条 P1，不改变两条 PR 的依赖关系；不修改正式 Current 参数、Player/AI、原版资产或地图几何，不做 Movement-5 菜单/包。

## R1 结果

15 个原候选的证据分类：**4 qualified_jump、7 walk_only、3 blocked_direct_route、1 route_unproven**。资格参考为未改参数的 Current；只能证明本轮冻结路线/输入和对照，不能证明地图不存在其他路线或两套候选永远不能跳过。

| 地图 | qualified_jump | walk_only | blocked_direct_route | route_unproven |
| --- | --- | --- | --- | --- |
| Dust II 当前本机入口 | 助跑、预蹲 | 普通、爆点目标 | 边界 | — |
| Mirage | 预蹲 | 普通、爆点目标、边界 | — | 助跑 |
| Inferno | 预蹲 | 普通、爆点目标 | 边界、助跑 | — |

原 90 次及原清单不回写。4 个已资格化跳点另建 **schema 2 / qualified-v2** 清单，冻结父清单哈希、资格凭据哈希及完全相同的坐标/输入，重新运行三方案 × 60/120 Hz **24 次**，**20/24** 达到目标。剩余 4 次均为 Mirage 预蹲项的 Legacy/Modern 两档结果；Current 四点两档均达到。仍须区分输入时序与候选运动/姿态差异，不据此调整默认数值或宣布原版手感通过。

**Movement-4 仍未通过，Movement-5 继续冻结。** 新清单只是已证明点位的子集，不能用缩小清单绕过原 15 点完整资格、每图角色覆盖或整场验收；门闸同时保留原点位结论和新版本重放。52/90 不解释为移动系统成功率；v2 20/24 也不是最终可玩性评分。

## P1：身体通道漏检

`ClassicJumpSurvey.body_corridor()` 在目标脚印之外，沿直连的四个有界包络（0 / 0.8 / 1.2 / 1.7 m 抬升）连续扫掠完整玩家胶囊，保存每段起终点、初始重叠、可行比例和碰撞法线。半径 **0.4 m**、站姿 **1.8 m** / 预蹲 **1.2 m**，脚底检查余量 **0.04 m**；连续分段不是只发一条中心射线。`_edge()` 返回带通道证据的候选，discover 的升/降候选池拒绝无通道项；爆点候选也补同一检查。此处仅为测试工具，不改变实际碰撞体或玩家物理。

Dust II / Inferno 原边界在非零跳跃包络均触及侧向立面，原普通前进和静步对照也不能到达；两点明确为 blocked_direct_route。零抬升包络可能先触地，单独保存为不跳对照，不能把它伪装成跳跃墙面证明。该结论指本轮直跳包络和输入，**不声称穷尽空中绕行、其他蹲伏时机或全地图所有路线**。

三种合成反例通过：目标可站立但整墙隔断、移除墙后身体通道可行、中心线未碰撞但侧边细柱阻挡整个身体；还检查扫描池不会把隔墙目标收为合格升台。这些是回归夹具，不替代真实三图证据。

## Mirage 助跑对照

所有 15 点均补 Current 的不跳前进与 Shift 静步，两档共 60 次。Mirage 助跑额外覆盖三方案：原起跳时刻 **0.35 s** 已留在原矩阵；新增提前 **0.15 s**、延后 **0.55 s**，并补齐其余方案的不跳/静步，两档共再补 20 次，合计 **80 次新对照**。

Mirage 助跑在这些对照下均未达目标。Current 提前跳比原输入更近，但仍约 **1.76 / 1.89 m**，超过冻结半径 1.6 m。不能由“更近”推断调整加速度即可修复；此点保留 route_unproven，后续先证实阶梯/转角路线和输入路线，再讨论模型。没有为变绿而移动目标或放宽容差。

## P1：逐点资格门闸

`tools/map_jump_qualification.py` 定义版本化资格 schema 2；每点必须有 map、level、case、manifest_sha256、status、reason、evidence。覆盖三图各五类、无缺项/重复，且两档身体/对照文件和两档实际跳跃矩阵均需完整。

- 对证据文件核验 SHA256、路径边界、地图/引擎/碰撞身份和冻结清单；跳跃证据必须就是被审计目录中的对应矩阵，不接受另一个同名/同头文件替代。
- 核对身体胶囊、全部包络、连续分段和冻结起终点；不相信一个 clear 摘要值。对照必须使用冻结输入的明确不跳/静步变体、真实完整时间线、有效起点；失败对照也不允许偷偷起跳。
- 从原始证据重算 status；声明不符即拒绝。walk_only 保留为对照，不算跳跃能力；全是走路的语料不能通过跳跃验收。blocked/unproven 不放行。
- 不读旧 complete 布尔量；旧 schema、complete-only、缺项、错图、错哈希、缺档、路径越界、伪造 clear/状态、缺通道证据均拒绝并返回非零。核心策略使用显式异常，`python -O` 也不能关闭检查。
- v2 子集必须逐字典保持父清单的坐标/时间线，绑定父哈希和资格凭据；必须有绑定 v2 新哈希的两档新矩阵。旧矩阵不能替新版本背书，改变输入也不能复用旧资格。

只有资格和矩阵同时合格，`--require-acceptance` 才可成功。**正向合成完整证据可通过**，本机真实语料因 3 blocked + 1 unproven 和 v2 未完成项正确返回非零；这不是执行错误。

## 验证与 CI

本机证据：`D:/AgentGamePipeline/evidence/movement-4-r1-20261025/`；包含 6 份通道/对照报告、schema-2 逐点凭据、qualified-v2 及 6 份新矩阵、反例日志、保持检查和交付记录。坐标、原几何和本机派生布局不提交 Git；仓库存 [去绝对坐标汇总](evidence/movement-4-r1-20261025/summary.json)。原来的 `three-map-movement-points-20261025` 保留。

新增 **25 项**门闸回归通过，含全部到达情况下 complete=true 绕过的负例、有效完整证据的正例、blocked/unproven/全走路语料、双档/清单/证据身份、跳跃混入不跳对照、宽目标区不能掩盖隔墙通道、分段跳过空间、父子清单/新矩阵绑定、拒绝覆盖父清单及 Python -O。普通 Python 全集 **105** 通过；Blender bpy 专用脚本仍使用其独立环境，不混入此数。Godot 身体通道反例、资源导入、格式/lint 和 Python 编译另验。没有正式行为/地图/UI 改动，沿用 #95 的原生基线，不为作者工具反复跑完整游戏套件。

Tests 工作流增加这两类回归，并允许以 feature/**、audit/** 为基线的堆叠 PR，防止今后再次因 main-only 过滤而没有 Tests。反例步骤同时检查错误日志和成功标记，不能因 quit-after 的零退出码误放行。

#95 保持原 HEAD、原基线和 COMMENTED 待审状态。Windows 手动运行 **40185544720** 成功；保持同头的临时 CI 草稿 #97（main 基线，仅触发 CI）另取得 [Tests 40189968249](https://github.com/2002yy/vector-breach-godot/actions/runs/40189968249) / [Windows Export 40189968302](https://github.com/2002yy/vector-breach-godot/actions/runs/40189968302) 成功，两者 headSha 均为 `b0378218b9ee1a8e51b609bf8e200b9f058a5502`。#97 已关闭且未合并。这补足同头 CI 证据，**不代表 #95 获批或合并**，也不用于给 #96 新头背书。#96 新头须重新查 CI/复核两条 P1；不等待 CI、不擅自 resolve 线程。

本机复现主要命令（真实语料门闸目前预期退出 1）：

```powershell
python tools/build_map_jump_qualification.py D:/AgentGamePipeline/evidence/three-map-movement-points-20261025 D:/AgentGamePipeline/evidence/movement-4-r1-20261025 --out D:/AgentGamePipeline/evidence/movement-4-r1-20261025/qualification-v2.json
python tools/validate_map_jump_audit.py D:/AgentGamePipeline/evidence/three-map-movement-points-20261025 --review D:/AgentGamePipeline/evidence/movement-4-r1-20261025/qualification-v2.json --qualified-directory D:/AgentGamePipeline/evidence/movement-4-r1-20261025/qualified-v2 --out D:/AgentGamePipeline/evidence/movement-4-r1-20261025/validated-summary.json --require-acceptance
python -X utf8 -m unittest discover -s tools/tests -p test_map_jump_qualification.py -v
```

## 后续边界

下一片调查 Mirage 助跑 route_unproven 的合法转角/台阶路线，并对合格预蹲点的 Legacy/Modern 未达目标做姿态与输入时序归因。需新坐标/输入时必须新版本、重新证明资格与重放。原版资产和布局、正式 Current 参数继续冻结；人工三图、最新头 18 场和逐图 70% FPS 仍未完成。
