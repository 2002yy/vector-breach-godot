# 玩家手感复核与经典版本基线

日期：2026-10-25。工作分支 `audit/player-movement-baselines`，游戏代码基线 `6855feed4f52bfae03a9a06ff7b449a8fd123cb2`（#93）。本批只增加测量工具、证据和计划，未修改正式玩家/AI 参数、地图或用户设置。用户决定：多个版本先调研，最后通过实测选择；不得提前把某个版本设为默认。

## 结论与证据边界

当前移动是项目自定义规则，不能称为已经对齐经典 CS。旧回归复跑 **7/7** 通过，但它们主要锁定本项目的急停、空中限速、台阶、静步、蹲伏和受击行为，没有证明与 CS 的跳跃曲线、武器速度或疲劳机制等价。

新增真实 Player.tscn + Jolt 平地探针，60/120 Hz 两次均 `PLAYER_MOVEMENT_AUDIT_OK`。这两档是**物理频率**，不是帧率目标，也不是在原版 CS 客户端上的测量。原生输入延迟、鼠标手感、原图跳点、斜坡、梯子/水体、连续落地与实际试玩仍待验。没有据此宣布 70% FPS、三图试玩或最新头整场验收完成。

## 版本与来源

| 对照 | 可核实内容 | 证据限制 |
| --- | --- | --- |
| CS 1.6 | ReGameDLL_CS 兼容实现的武器上限、跳跃公式、空中加速、蹲伏倍率；Valve GoldSrc SDK 用于算法交叉参考 | ReGameDLL 是社区兼容实现，不是 Valve 原始 CS 1.6 源码；服务端配置/插件可改变行为，仍需官方原版客户端实测 |
| CS:GO | 2023-01-26 跟踪的已发行武器数据；Valve 2014-10-02 公告的竞技移动/受击规则 | 不使用泄露源码；本批没有足够一手证据给出精确跳跃冲量/原机滞空时间，不用 CS2 数值补空 |
| CS2 | 2026-10-22 跟踪的游戏 ConVar dump 与 weapons.vdata | 为提取的默认值快照，不保证每种服务器模式都相同；ConVar 不能证明 subtick 的完整实现，仍需原机输入/轨迹采样 |

每份原始来源的完整 SHA、日期、文件 URL 和 SHA256 见 [来源清单](evidence/player-movement-20261025/sources.json)。下载的原文旁存在本机 `D:/AgentGamePipeline/evidence/player-movement-baselines-20261025/sources/`。Valve 通用 Source SDK 仅作算法参考，不能冒充 CS:GO/CS2 的实际实现。

地图导入明确使用 `0.0254 m/Source unit`，见 `tools/prepare_local_classic_map.py` 和 `tools/blender/convert_local_classic_map.py`。以下速度按此换算；没有拿不同单位的 accelerate/friction 数字直接比较大小。

## 武器、姿态与跳跃数据

| 项目 | 当前项目，60 Hz 实测 | CS 1.6 兼容参考 | CS:GO 数据快照 | CS2 数据快照 |
| --- | --- | --- | --- | --- |
| 刀 | 6.448 m/s | 本表未单独核验刀 | 250 u/s = 6.350 m/s | 250 u/s = 6.350 m/s |
| AK 类主武器 | 5.828 m/s | AK47 221 = 5.613 | AK47 215 = 5.461 | AK47 215 = 5.461 |
| AWP 未开镜 / 开镜 | 同一主武器规则 5.828；无开镜移动倍率分支 | 210 / 150 = 5.334 / 3.810 | 200 / 100 = 5.080 / 2.540 | 200 / 100 = 5.080 / 2.540 |
| MP9 类冲锋枪 | 同一主武器规则 5.828 | 无 MP9，不跨枪型替代 | MP9 240 = 6.096 | MP9 240 = 6.096 |
| 手枪 / 静步 / 蹲行 | 6.200 / 3.200 / 2.200 m/s | Glock18 250 = 6.350；蹲伏倍率 0.333 | 本批未核验全部手枪及姿态倍率 | 本批未核验全部手枪及姿态倍率 |
| 重力 | 9.800 m/s² | 普通跳公式内使用 800 u/s² 参考值 = 20.320 | 原机默认/模式待采集 | sv_gravity 800 = 20.320 |
| 站跳初速 | 5.100 m/s | sqrt(2×800×45) = 268.328 u/s = 6.8155 m/s | 精确数值待一手/原机核验 | 301.99338 u/s = 7.6706 m/s |
| 跳跃高度 | 实测根节点升高 1.3706 m | 理想抛物线 45 u = 1.1430 m | 待原机采样 | 理想抛物线约 57 u = 1.4478 m |
| 跳跃时间 | 指令至落地 1.000 s | 理想同高往返约 0.6708 s | 待原机采样 | 理想同高往返约 0.7550 s |

**后两行不能直接当作同口径的原机对比测试**：当前是含采样/输入阶段和贴地处理的真实控制器结果；经典列为忽略离散步进、碰撞、疲劳和 subtick 的解析值。当前高度接近 CS2 理想高度，但重力更低、跳跃持续更久；仅改 jump_velocity 不能同时对齐高度与时间。CS 1.6 兼容公式的扩展构建可读取自定义 jump_height，本表对应普通兼容默认分支。

CS:GO/CS2 的武器原始数据分别见 [CS:GO AK47](https://github.com/SteamDatabase/GameTracking-CS2/blob/e25a5a3d872f0a52a33a9c0d116a597b9df6d846/csgo/scripts/weapon_ak47.txt)、[CS:GO AWP](https://github.com/SteamDatabase/GameTracking-CS2/blob/e25a5a3d872f0a52a33a9c0d116a597b9df6d846/csgo/scripts/weapon_awp.txt)、[CS:GO MP9](https://github.com/SteamDatabase/GameTracking-CS2/blob/e25a5a3d872f0a52a33a9c0d116a597b9df6d846/csgo/scripts/weapon_mp9.txt)、[CS2 weapons.vdata](https://github.com/SteamDatabase/GameTracking-CS2/blob/04d3e4a67ac60168d0e79594c69a2116bb3b7278/game/csgo/pak01_dir/scripts/weapons.vdata)。

## 当前控制器的复测

| 测量 | 60 Hz | 120 Hz |
| --- | --- | --- |
| 手枪 / 主武器 / 刀，m/s | 6.200 / 5.828 / 6.448 | 同左 |
| 静步 / 蹲行 / 斜向，m/s | 3.200 / 2.200 / 6.200 | 同左 |
| 站跳抬升 / 指令至落地 | 1.3706 m / 1.000 s | 1.3492 m / 0.975 s |
| 预蹲后起跳抬升 / 指令至落地 | 1.6187 m / 1.100 s | 1.5955 m / 1.075 s |
| 持续前进跳跃距离 | 6.2004 m | 6.0454 m |
| 松前进同时跳，首次离地水平速度 | 4.9849 m/s | 5.5759 m/s |
| 求解器：静止至 95% 速度 | 0.2833 s | 0.3000 s |
| 求解器：松键至 ≤0.05 m/s | 0.3167 s | 0.3083 s |
| 求解器：反向输入至速度过零 | 0.0833 s | 0.0750 s |
| 8 m/s 空中初速，无输入 / 侧向输入后一帧 | 8.000 / 6.500 m/s | 同左 |
| 1 点伤害后，站立 / 蹲行速度 | 2.976 / 2.200 m/s | 同左 |

求解器行是直接调用实际水平求解函数，测的是速度，不是射击准确度恢复。两个频率都没有按住跳跃自动连跳。蹲跳采样从已蹲稳状态开始，不能据此证明在空中缩腿可跨越多高障碍；站跳/蹲跳清障高度需要额外几何夹具。

“松前进同时跳”前八帧已存入 JSON：第一样本仍在地面且已经减速，第二样本离地再次减速。源码在设置跳跃竖直速度后仍用 `is_on_floor()` 传入水平求解，因此起跳帧的地面摩擦值得修验。但这组异步 Input 注入也存在相位影响，**不能把两次摩擦全部归因为正式输入路径缺陷**。下一片必须用带时间戳的物理回调输入，分开测起跳前帧、起跳帧与首个离地帧，再决定修复。

原始数值见 [60 Hz](evidence/player-movement-20261025/current-60.json)、[120 Hz](evidence/player-movement-20261025/current-120.json)。

## 发现的问题与处理次序

1. **先建立完整可选手感参数与清障基线，再改默认。** `get_equipped_movement_multiplier()` 只按槽位区别，狙击/冲锋/霰弹没有独立速度和开镜降速。先补武器 ID/姿态数据与狭窄通道、台阶/蹲跳夹具，避免破坏地图跳点和 AI 追赶关系。
2. **跳跃曲线与输入时序。** 当前重力 9.8、站跳 5.1、蹲跳额外冲量 5.55，没有完整的连续跳跃/落地疲劳。60/120 Hz 已出现高度、时长和松键起跳速度差异。先修验同帧输入、落地吸附和蹲伏缩腿，再制作可切换对照候选。
3. **受击减速绕过蹲行。** `resolve_move_speed()` 对 crouch 提前返回，未应用 `_tagging_multiplier`，实测 1 点伤害后站立降至 2.976、蹲行仍 2.2。CS:GO 官方明确曾改为累积 tagging 且与所持武器移动能力相关；当前固定下限 0.48、恢复 1.9/s 不能称为同一规则。先定一套对所有姿态一致的伤害政策，再按选定版本细化。参见 [Valve 2014-10-02 公告](https://blog.counter-strike.net/2014/10/10300/)。
4. **地面/空中加速算法不同。** 当前地面加速度是 `accel × dt`，反向另加速；GoldSrc 参考使用 wishspeed、friction 的乘积。当前有输入时把空中总速封顶 6.5，无输入时却保留超速；CS 1.6 兼容实现的 30 u/s 为愿望方向投影限制，不是总速上限。不能仅抄 10/12 等 cvar 数字。
5. **AI 与玩家共用运动合同。** #93 缓解摇摆和慢速，但精确路径约 3.89 m/s，与玩家主武器 5.828 仍有明显差距。待玩家候选确定后统一武器/姿态上限，随后做拥堵、转角与难度，不能先靠难度倍率掩盖基础差异。

CS2 快照额外记录：accelerate 5.5、airaccelerate 12、air_max_wishspeed 30、friction 5.2、stopspeed 80、stepsize 18、staminajumpcost 0.08、staminalandcost 0.05、staminamax 80、staminarecoveryrate 60、autobunnyhopping false、enablebunnyhopping false。参见 [固定提交的 ConVar dump](https://github.com/SteamDatabase/GameTracking-CS2/blob/04d3e4a67ac60168d0e79594c69a2116bb3b7278/DumpSource2/convars.txt)。它们是后续对照输入，不是声称已经复现 subtick。导航 hull 的 max climb/jump 字段也不当作玩家实际跳跃/碰撞参数。

## 后续实测方案

保留当前参数作 A；分别准备可回退的 1.6 风格和 GO/CS2 风格候选，**GO 与 CS2 的时序结果分别记录**。精确 GO 跳跃参数确认前不发布为“GO 等价”。同设备、分辨率、输入设置，在同一平地/台阶夹具测加速、松键、反向、武器切换、开镜、受击、站跳/蹲跳/连续跳、斜坡/梯子/水体；然后三图跑固定路线与跳点，由用户决定默认。物理 60/120 Hz、渲染帧率和鼠标输入时延分别记账。

这批没有发布新试玩包；最后包仍为 `D:/VectorBreach/releases/VectorBreach-playtest-20261024/`，main `598cde1`。2026-10-25 本次查询确认 #93 OPEN、未合并；main 未包含后续串联候选，不能把最新工作头实测称为桌面包行为。

## 复现与验证

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . --fixed-fps 60 --scene res://scenes/tests/PlayerMovementAuditProbe.tscn -- --rate 60 --out D:/AgentGamePipeline/evidence/player-movement-baselines-20261025/current-60.json
# 120 Hz：同时将 --fixed-fps 和 --rate 改为 120，另写 current-120.json
uv tool run --offline --from gdtoolkit gdformat --check scripts/tests/PlayerMovementAuditProbe.gd
uv tool run --offline --from gdtoolkit gdlint scripts/tests/PlayerMovementAuditProbe.gd
git diff --check
```

现有 7 项复核：counter_strafe_and_air_control、tactical_movement_solver、classic_shift_walk、authored_height_step、crouch_hull_without_double_jump、movement_and_radar_scale_map_invariant、damage_tags_and_death，完整名称及日志见本机 `focused.log`。无正式行为改动，未重复完整原生/图形套件；#93 的历史 224 原生测试不能冒充这批重新全跑。四个既有脏导入和 settings.cfg 的字节核验另存本机 `preservation.json`。
