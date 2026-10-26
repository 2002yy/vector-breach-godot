# Movement-4 R10：动作与通路分维门闸

基线 `bbc8b9ebfbe17bd3733b3e9610cd50b6005cb261`（#105），分支 `audit/movement-action-route-gates`。仅作者 Python、回归和证据文档；正式玩家、三方案参数、原版资源/几何、UI 不改。

## 判定规则

`tools/movement_dimension_gates.py` 先运行 R9 完整冻结队列验证，包括三图源清单、InputMap/运行时/原碰撞与布局身份、历史轨迹及跳跃/走路配对；随后分两个维度读取原始轨迹：

- **动作**：单次消费边沿与单次真实起跳必须处于同一个采样，起跳前有支撑、起跳后离地且竖向速度为正；两档均用实际引擎过程/物理计数验证一对一，保留消费延迟。动作成功不要求到达目标，不把掉落当起跳。
- **通路**：两档动作、首次落点均成立，原身体胶囊通道可行，配对不跳/静步均未到达，才是 `qualified_jump`。可走通保留 `walk_only`，墙挡保留 `blocked_direct_route`，其余 `route_unproven`。控制组有跳跃或非有限轨迹时拒绝，不能贡献“失败”的对照证据。

动作门闸目前仅接受固定循环比例的**单次受支撑起跳**。它为普通/边缘动作提供同一检查入口，尚未实测这两类，也未定义连跳、离边宽限或变帧率支持。原证据与正式放行器不被覆盖，派生输出永久保留 `formal_release_ready=false`、`precision_equivalence_accepted=false`、`human_acceptance=false`。

## 实际结果及缺口

复用 R9 原始144次，不重新执行游戏；四条关键落点路线 × 三方案 × 两档，共24次动作检查和12组双档路线均通过。三图各有 `critical_landing` 的三方案证据，即 **3/15 类别**。其余12个地图/类别组合明确缺口，尤其 `ordinary` 和 `edge` 无专门动作证据。到达数不能替代类别覆盖、频率精度或原版手感验收。

坐标不入库的[汇总](evidence/movement-action-route-gates-20261026/summary.json)绑定9个R9清单/原始报告、3个R6源清单及本验证器SHA；源证据仍在原位置。本机过程与交付：`D:/AgentGamePipeline/evidence/movement-action-route-gates-20261026/`，最终头/PR/CI首查见 `delivery.json`。

## 验证与复现

- 新增14项回归：有动作无到达、边缘掉落、非向上/无支撑起跳、消费错位、重复起跳、伪造计数、非有限轨迹、旧入口误用、污染控制、缺频率/控制、身体阻断、可走目标、类别与方案误计。
- 普通 Python 222项通过；格式、Ruff F、编译及 Pyright 0错误通过。当前CI的 `test_m*.py` 发现规则自动包含本组。
- 四个已有脏导入、用户设置及原清单/报告SHA保持；无生产改动，不重复完整原生、Blender、比赛或Vulkan。本轮普通 Python 初次直接全发现误载需 `bpy` 的独立 Blender 脚本失败；日志 `python-all.log` 保留。按既有普通测试范围单独排除该脚本后，`python-ordinary.log` 222通过，未改该脚本或其CI。
- 复现：`python tools/movement_dimension_gates.py <R9目录> <R6目录> --project <仓库> --out <新目录/summary.json>`。输出必须是源目录之外的新文件，不覆盖旧记录。

**Movement-4 未验收、Movement-5 冻结；不合并、不发包、不等CI。** 下一片冻结普通原地/边缘专用输入，用三图三方案双档前置队列采集动作证据，独立保留通路资格。原机/人工、剩余精度裁定、18场与逐图70%FPS仍待验。
