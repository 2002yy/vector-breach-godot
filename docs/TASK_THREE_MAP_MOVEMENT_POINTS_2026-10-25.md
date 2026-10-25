# Movement-4：三图冻结跳点首轮实测

基线 `b0378218b9ee1a8e51b609bf8e200b9f058a5502`（#95），分支 `audit/three-map-movement-points`。本批只添加只读扫描、执行、截图和汇总工具，不修改 Player、候选参数、默认方案、地图/导航、原版纹理、人物或装备。不等待 CI，不提前合并或发布试玩包。

## 当前结论

三图各冻结 5 类初步**候选**，三方案 × 60/120 Hz 共 **90 次**；所有起点有效、均真正离地。**52/90** 到达冻结目标，**38/90** 未到达。场景复核另发现两处边界候选朝向墙面，点位资格尚未通过；这 38 次不能全算为移动缺陷。不能宣布 Movement-4 或三图可玩性验收通过，也不进入 Movement-5 发包。

| 地图 | 每档次数 | 60 Hz 到达 | 120 Hz 到达 |
| --- | --- | --- | --- |
| Dust II 当前本机入口 | 15 | 11 | 11 |
| Mirage | 15 | 7 | 7 |
| Inferno | 15 | 8 | 8 |

按方案合计：Current **20/30**、Legacy **18/30**、Modern **14/30**。这是同一预设输入能否进入目标区的比较，**不能据此宣布 Modern 较差，或认定未达标点无法到达**。后续必须用不跳跃对照、输入/路线时序对照和碰撞接触归因，区分脚本过早起跳/过冲、地形与碰撞、模型能力差异及真正规则缺陷。

两档频率的达标/未达标判断 **0 项变化**。Inferno Modern 助跑项的失败分类有 1 项变化：60 Hz 高度误差约 **0.2023 m**，120 Hz 约 **0.1563 m**，跨过冻结的 0.18 m 高度门槛；两档距目标仍约 **2.93 / 2.91 m**，均未达标。保留原始离散差异，不归零、不直接称为逻辑缺陷。

## 点位与冻结合同

`ClassicJumpSurvey.gd` 读取现有冻结导航节点，再对**真实运行时碰撞**作射线/胶囊查询，先按几何选点、后执行三种方案；不按某方案是否成功来选点。初步分类为普通站跳、实际爆点附近关键落点、台阶/高差边界跳、助跑升台、预蹲起跳升台。边界项并不代表所有断口/箱体技巧；当前不是人工挑选的全图典型跳点清单，B 点等更多重要区域仍需扩展。

每个清单冻结起点、朝向、目标脚底位置、容差、完整输入时间线、导航节点及几何取样证据。目标区为静止跳半径 **0.35 m**、移动跳半径 **1.6 m**，高度容差 **0.18 m**，均在正式矩阵前确定。1.6 m 为初步区域到达判据，**不是精确边缘落脚或原版跳点等价判据**。地图身份包含关卡、碰撞原文件、碰撞导入设置、冻结布局的 SHA256 和 Godot 引擎 hash；执行前还复用 ClassicMatchLayout 原有原文件/布局合同校验。

本机 `D:/AgentGamePipeline/evidence/three-map-movement-points-20261025/` 保存三个 `*-manifest.json`、冻结哈希 `freeze.json`、每次完整位置/速度/接地/接触轨迹、落地支撑射线和截图。**坐标及原地图派生布局不提交 Git**，延续已有本机原资产策略；仓库只保存工具和 [无绝对坐标汇总](evidence/three-map-movement-20261025/summary.json)。正式 90 次与修验夹具期间未改清单，校验器逐项核对冻结哈希。

Dust II 验证的是当前本机实际入口和其既有审计碰撞；不是重新获得原 `de_dust2.vpk`，也不借本批把既有资源/碰撞来源边界升级为完整原引擎还原。

## 执行证据与失败分类

执行复用实际 `Player.tscn`、MovementTimelinePlayer 输入边界和真实 GrayboxLevel 碰撞构建/已验证缓存。没有额外平地、替代箱体、碰撞补丁或机器人代跑。起点统一静置 **0.5 秒**，以接地且偏离请求起点 <0.2 m 为有效；每种方案从相同输入清单启动。

达标同时要求：起点有效、真正起跳/离地、首个落地样本接地、原冻结碰撞支撑存在、平面距离及高度均在冻结范围内。支撑用脚底及胶囊脚印内五条射线复核，显式排除玩家 RID，并确认命中体属于原碰撞实例；每帧另外记录实际滑动碰撞体、法线和接触点。排查结果分为 invalid_start、no_takeoff、no_supported_landing、wrong_elevation、outside_target、reached，不能把写出 JSON 的退出码 0 当目标全部通过。

本轮最终失败为 **23 次超出目标范围、15 次高度不符**；没有起点无效、未离地或无支撑落地。普通跳三图三方案两档均通过；其他重点包括：

- Dust II 高差边界三方案均落到目标高度之外；Modern 爆点目标区未到达。
- Mirage 助跑项三方案均未到目标；边界与预蹲项存在方案差异。
- Inferno 高差边界、助跑项仍未到目标；Modern 爆点项也未到达。

这些是冻结输入的观测，不先归咎于地图或引擎。原始接触和图像用于下一片逐项定位。

最终 **3 次 Vulkan / 30 PNG**（每候选第一人称起点和概览）已逐图核对。Dust II / Inferno 边界候选的正前方是墙面，射线只发现墙后较低表面，没有证明可直跳通道；Current 接触侧墙分别约 83/82 个采样帧。它们标记为 **blocked_direct_route，点位资格待修**，不能作为有效边缘跳来判定控制器失效。Mirage 助跑候选显示台阶/转角，需不跳跃通行对照，当前也不能宣称是必须跳跃的技巧点。静止普通跳仅证明局部起落稳定。汇总同时记录采样是否完成和点位资格是否完成，避免把前者当后者。

## 验证边界与工具修验

首轮记录保留：启动工具预加载 Player 导致 SceneTree autoload 尚未注册的编译错误，改为执行期动态加载；固定 10 帧等待在 120 Hz 比 60 Hz 更短，统一为 0.5 秒；落地验证改为排除玩家本身、五点脚印及原实例身份。它们是测试工具修正，不是修改正式移动/碰撞。重验保留原冻结坐标、输入与容差。截图首次仅加载 Level，缺少 Main 环境而过暗；最终复用 Main 原环境和地图环境函数，未改材质/亮度参数。概览相机进行碰撞/遮挡检查，诊断标记无碰撞，不属于发布内容。

本批无正式游戏行为、地图数据或 UI 变更；复用 #95 已验证的完整原生 **224 + 13 组**及原移动 7/7，不重复整套。新增作者工具以真实三图执行、两档矩阵、重复测量、身份变更拒绝、Vulkan 场景截图、格式/lint 和 Python 汇总校验验收。最终验证/提交/PR/CI 首查与保持记录见本机 `delivery.json`。截图只证明点位与场景对照，不是人工三图连续试玩、整场平衡或 70% FPS 验收。

最终复测 Mirage 60 Hz **15 次**，位置/速度/接地/输入物理轨迹逐值一致；修改清单碰撞哈希时工具拒绝执行且不写结果文件。`--require-acceptance` 对本批明确返回非零，点位资格没有被“采样成功”绕过。三图原碰撞/导入和清单哈希、四个既有脏导入及 settings.cfg 字节保持；新三份 GDScript 格式/lint、Godot 资源导入及 Python 编译/汇总检查通过。

## 复现

```powershell
# 首次只读发现；清单含本机地图派生坐标，留在外部证据目录
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . -s tools/authoring/audit_classic_jumps.gd -- discover mirage-classic-local D:/AgentGamePipeline/evidence/three-map-movement-points-20261025/mirage-manifest.json
# 冻结哈希后验证。120 Hz 同时替换 fixed-fps、输出文件名及末尾频率
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . --fixed-fps 60 -s tools/authoring/audit_classic_jumps.gd -- verify D:/AgentGamePipeline/evidence/three-map-movement-points-20261025/mirage-manifest.json D:/AgentGamePipeline/evidence/three-map-movement-points-20261025/mirage-60.json 60
python tools/validate_map_jump_audit.py D:/AgentGamePipeline/evidence/three-map-movement-points-20261025 --review D:/AgentGamePipeline/evidence/three-map-movement-points-20261025/point-review.json --out docs/evidence/three-map-movement-20261025/summary.json
# 加 --require-acceptance 会因当前未达标点返回非零，符合预期
```

下一片继续 Movement-4：优先对 Dust II/Inferno 高差边界、Mirage 助跑做走路/不跳对照和碰撞逐帧归因，保留本清单，另建有版本的输入对照；必要时再按证据修共用控制器，禁止通过改原图或直接调正式默认数值消除失败。Movement-5 可切换试玩、最新头 18 场、连续人工三图及逐图 70% FPS 仍未完成。
