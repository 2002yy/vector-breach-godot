# Movement-1～3：统一速度、起跳时序与独立运动模型

基线：`71b3a8d638de875d51dfc6a7a71e7ae7a2abb6e3`（#94）；分支 `feature/classic-movement-models`。实施合同为用户 2026-10-25 的「经典移动系统重建与三图可玩性验证」裁定。本批止于 Movement-1～3 的实现与自动化；Movement-4 三图固定跳点与 Movement-5 人工可切换试玩仍未验收。

## 默认与方案边界

- **Current** 仍是新玩家实例的默认；run/walk/crouch、重力、跳跃冲量、当前地面/空中参数和武器槽位倍率不调值。修正蹲行绕过 tagging 以及起跳仍扣地面摩擦两个规则问题，因此不能称每种边界行为逐帧不变。
- **Legacy 1.6** 为显式调用 `set_movement_scheme("legacy_16")` 的兼容参考候选。武器映射：AK47/AWP/MP5/M3/Glock18/knife；重力 800、普通跳公式 45 u、地面 10/4/100、空中加速 10 与方向投影上限 30 u/s。
- **Modern CS** 为显式调用 `set_movement_scheme("modern_cs")` 的现代候选。武器映射：AK47/AWP/MP9/Nova/Glock/knife；采用已固定的 CS2 2026-10-22 数据快照：地面 5.5/5.2/80、空中 12/30、重力 800、跳跃冲量 301.99338。GO/CS2 已核实的 AK/AWP 等武器数据可共享；**不能据此称 GO 的跳跃、疲劳或 subtick 已复现**。当前不提供“GO 等价”开关。
- 0.52 静步比例、Modern 0.34 蹲行比例先作为候选种子；Legacy 0.333 蹲行比例有兼容源码依据。未核验值不能称原机默认。无对应武器的装备回退 250 u/s，为明确的候选策略。jump/land stamina、斜坡/边缘摩擦、Source2 特有加速修饰、空中蹲伏清障仍需后续比对。
- 三方案不写 UserSettings，不新增菜单、不生成试玩包、不改原图碰撞、纹理、人物或装备素材。新方案只在开发/测试 API 可选，避免未经三图验证成为正式默认。

参数和算法集中在 `scripts/player/ClassicMovementRules.gd`，实际 PlayerController 共用同一入口，不增加地图分支。

## Movement-1 独立验收

正式物理移动只通过 `resolve_final_move_speed()` 计算最终上限：实际装备/武器 ID 与有效镜头状态 → 武器速度 → 蹲行优先于静步 → actor tagging → 水体倍率。切枪、开关镜和姿态不拥有 tagging 状态，也不重置恢复进度。旧 `resolve_move_speed()` / `get_equipped_movement_multiplier()` 保留兼容调用；旧蹲行 helper 同样补上 tagging。

WeaponSystem 新增轻量 `get_movement_context()`，不每帧构造弹药/后坐力等完整 UI 快照。刀、手雷和 C4 来自 TacticalEquipment 的实际槽位，不能误用收起枪械的 WeaponSystem 索引。联调检查发现了这个独立设备入口，已在最终回归前修正并补真实 select_knife/select_c4/select_next_grenade 测试。

自动检查覆盖三方案 × 六枪型 × 开镜状态 × 三姿态的 tagging/水体组合，以及真实 WeaponSystem/TacticalEquipment 的开镜→受击→关镜→换冲锋枪→蹲行→刀→C4→手雷流程。Current 保留刀 6.448 m/s、主武器 5.828 m/s 等未受击基线；Modern AWP 开镜 2.54 m/s、Legacy 3.81 m/s 是候选值，未写入 Current。

## Movement-2 独立验收

输入快照在物理更新内统一消费，`move_and_slide()` 保持在 `_physics_process()` 中。起跳使用 `grounded_before && !jumped` 选择地面求解；`is_on_floor()` 表示上次 move_and_slide 的接触结果，不能在设定向上速度后继续当作仍处地面。

新增按需连接的 movement_step 诊断信号，无监听时不构造轨迹字典；记录输入/消费帧、原生事件时间戳、起跳标记、前后接地、实际选择的求解器、位置和速度。墙钟时间只用于顺序证据，不当作模拟时间。

两种输入证据分开：

1. 物理边界夹具在相同模拟时间线读取：t=0 持前进，t=0.5 按跳（保持前进或同时松前进），t=0.6 松跳。三方案在 60/120 Hz 均只触发一次起跳，t=0.5 消费，首个离地帧不走地面摩擦。
2. 同一时间线通过原生 InputEventAction/parse_input_event 注入，再走 Player 原生输入采样；观测到缓冲可晚一个物理 tick（60 Hz 约 16.67 ms，120 Hz 约 8.33 ms）。验收上限明确为一个 tick，并核对实际 `_input` 时间戳早于消费时间戳。这个夹具缓冲延迟不冒充键盘到屏幕的真实输入延迟。

松前进同时起跳时，消费帧水平速度与前帧相等（容差 0.0001 m/s），消除已确认的起跳地面摩擦。此前审计中“看似两次扣速”的另一帧与异步输入/采样相位有关，不再全部归咎于游戏逻辑。

## Movement-3 独立验收

候选的 ground_step 独立处理地面摩擦、停止速度和沿愿望方向加速；反向输入通过相同规则减速后加速，不偷偷更改输入方向或瞬时转向。air_step 使用愿望方向投影上限，保留正交动量和无输入滑行，不把 30 u/s 当总速限制。Current 保留原有 44/34/62 地面响应和 6.5 m/s 空中总速规则作为对照，不宣称它已成为经典模型。

每种方案保存 1 秒轨迹：松键至 ≤0.05 m/s、反向至过零、反向达到负向 95% 上限（180°速度翻转）、空中侧向变向的位置/速度序列。另检查 8 m/s 超速滑行、正交加速与投影上限；不只断言最后速度。

跨频率门槛透明记录在 `tools/validate_movement_timelines.py`：

- 平地跳跃最高点差 ≤4 cm；落地时间差 ≤一个 60 Hz tick；边界夹具消费时刻必须相同。
- 求解器过零/反向 95% 时间差 ≤两个 60 Hz tick；1 秒路径终点差 ≤测试速度 6.2 m/s 的两个粗 tick 位移（约 20.67 cm）。这是第一阶离散积分的候选门槛，**不是声称两档完全相同**，也不是三图落点可以容忍 20 cm。
- 实际各方案差异保留于比较 JSON；Current 的反向路径误差较大仍需人工看感受，三图边缘落点要用更严格的场景容差。
- 重跑 60 Hz，去掉墙钟时间和引擎绝对帧号后，完整物理轨迹应逐值一致。

实际最大最高点差约 **3.27 cm**、落地时刻差 **8.33 ms**；Current 反向一秒终点差约 **16.45 cm**。测量保留了原始偏差，不能称频率无差异。三方案平地初步轨迹如下（前进步枪，物理边界输入；未作原版客户端比较）：

| 方案 | 60 / 120 Hz 站跳升高，m | 60 / 120 Hz 松键至停止，s | 60 / 120 Hz 反向至负向 95%，s |
| --- | --- | --- | --- |
| Current | 1.3699 / 1.3488 | 0.3167 / 0.3083 | 0.3500 / 0.3667 |
| Legacy 1.6 候选 | 1.2003 / 1.1720 | 0.4667 / 0.4667 | 0.2000 / 0.2083 |
| Modern CS 候选 | 1.5126 / 1.4805 | 0.4000 / 0.4000 | 0.5500 / 0.5667 |

后两列为统一 6.2 m/s 初速/愿望速度的求解器实验，不是各枪型实际最高速度。候选高度也包含当前控制器的离散积分、碰撞/贴地规则，尚未达到原引擎轨迹等价；不得用它替代理想公式或原机结果。

## 验证、失败记录与复现

本机证据目录：`D:/AgentGamePipeline/evidence/classic-movement-models-20261025/`。包含各档完整轨迹、重复测量、跨频率比较、完整原生/现有 7 项移动回归、GdUnit、Python、增量 lint 和原资产/设置保持记录。最终结果与提交/PR/CI 记录见 `delivery.json`；仓库中保存便于审阅的汇总 `docs/evidence/classic-movement-20261025/summary.json`。

最终候选：完整原生 **224 + 新增移动 13 组**，`RUN_ALL_OK` 且无脚本错误；原有 7 项移动回归全部通过。Python **80**、GdUnit **2/2**、资源合同/层级/元数据通过；新 GDScript 格式和 lint 通过，PlayerController/WeaponSystem 的历史 lint 分别 46→44 / 34→34，无新增。既有风格问题保留，未宣称整个仓库 lint 清零。资源导入自动补出上一片审计脚本的 `.uid`，作为相关资源元数据纳入；四个既有脏导入与设置字节保持。

首轮夹具发现两项测试设置错误：typed Array[Dictionary] 不能动态赋普通 Array、独立 WeaponSystem 需要显式初始化；修复夹具后重跑定向。原生事件的首次严格 t=0.5 断言与已观测缓冲冲突，加入独立事件时戳并按一个 tick 明确限界，未把它归为生产失败。普通 Python unittest discover 误收 Blender bpy 专用脚本；按现有运行时边界单列后普通 Python 80 项通过，本片不改 Blender 资产，未冒称 Blender 测试完成。

第一次完整原生通过后，评审确认 TacticalEquipment/收起枪械状态分离会影响新速度入口，属于真实逻辑修复；补回归后重新运行最终完整套件。保留初次日志，不为仅修断言、声明顺序或文档重跑完整套件。

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . --fixed-fps 60 --scene res://scenes/tests/ClassicMovementTestRunner.tscn -- --rate 60 --out D:/AgentGamePipeline/evidence/classic-movement-models-20261025/rate-60.json
# 再分别运行 120 Hz 和重复 60 Hz，保存 rate-120.json / repeat-60.json
python tools/validate_movement_timelines.py D:/AgentGamePipeline/evidence/classic-movement-models-20261025/rate-60.json D:/AgentGamePipeline/evidence/classic-movement-models-20261025/rate-120.json --repeat60 D:/AgentGamePipeline/evidence/classic-movement-models-20261025/repeat-60.json
```

## 参考与下一片

[Godot CharacterBody3D 原始文档](https://github.com/godotengine/godot/blob/4.7.1-stable/doc/classes/CharacterBody3D.xml) 用于上一轮接触状态和物理更新约束；[固定 ReGameDLL/GoldSrc/CS2 来源清单](evidence/player-movement-20261025/sources.json) 用于兼容算法和武器/ConVar。补核 [ReHLDS sv_phys](https://github.com/rehlds/ReHLDS/blob/550f2d62f13f4ebeb029c1d9d1c212133202611d/rehlds/engine/sv_phys.cpp)、[sv_user](https://github.com/rehlds/ReHLDS/blob/550f2d62f13f4ebeb029c1d9d1c212133202611d/rehlds/engine/sv_user.cpp)、[sv_main](https://github.com/rehlds/ReHLDS/blob/550f2d62f13f4ebeb029c1d9d1c212133202611d/rehlds/engine/sv_main.cpp) 的 GoldSrc 兼容引擎重力/摩擦/停止速度与地面/空中加速默认。它们仍是兼容参考，不是原机验收。

下一片 Movement-4：每张图先确认真实存在的普通跳、边缘跳、助跑跳、蹲跳及关键落点，冻结坐标、输入时间线、碰撞资源身份和落点证据。只读原几何，失败先归因规则/路线，不改地图来凑通过。之后再做 Movement-5 三方案菜单/试玩包与用户评分。

可玩性主线为玩家→AI 共用规则/难度→三图比赛；画质性能线为冷加载→角色→烟雾/照明。两线最终仍需最新头 18 场、连续人工三图和逐图 70% FPS；本批不提前认领这些结果。
