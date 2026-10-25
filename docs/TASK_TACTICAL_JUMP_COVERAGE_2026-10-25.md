# Movement-4 R5：类别覆盖、新候选与窗口观察

基线 `3a421bd3f93202a114bd1a5011bccc2c0a544fbf`（#100），分支 `audit/tactical-jump-coverage`。仅作者工具、实图证据和文档；不改正式玩家、三方案规则/参数、原地图/资产，不合并或发包。

## 新候选的实际结果

按目标附近高差的几何条件先选点，再执行 Current 参考的真实 InputMap 输入，配套身体胶囊通道、无跳与站立静步对照。三图共 **4 条新路线**，与原 15 点没有相同起点/目标组合：

| 地图 | 目标附近高差路线 | 目标距离 | 60 / 120 Hz |
| --- | --- | --- | --- |
| Dust II | objective_rise_00 | 6.66 m | 首落成功，两个走路对照均未到 |
| Mirage | objective_rise_00 | 6.44 m | 首落成功，两个走路对照均未到 |
| Inferno | objective_rise_00 | 3.42 m | 首落成功，两个走路对照均未到 |
| Inferno | objective_rise_01 | 7.21 m | 首落成功，两个走路对照均未到 |

合计 **24 次**（4 路线 × 3 模式 × 2 频率），跳跃首落 **8/8**、走路对照 **16 次均未到**。四条均有原几何的完整站立身体包络；几何证据与物理频率无关，复用同一冻结几何证明，物理输入则两档分别执行。状态按现有四分类策略判为 qualified_jump，属于本轮研究凭据，**不自动替换 R1 的正式 schema-2 门闸或给 Movement-4 放行**。

这些新路线只验证了 Current。目标邻近是候选筛选依据，不代表已经证明实战收益、原版跳点等价或另外两方案通过。旧 20/24、R3 2/12、R4 新输入 24/24 均保留。

## 三图覆盖缺口

| 类别 | Dust II | Mirage | Inferno |
| --- | --- | --- | --- |
| 普通原地跳 | 旧点为 walk_only，保留作动作/走路参考 | 同左 | 同左 |
| 目标附近关键落点 | 本轮 1 条 Current 参考通过 | 本轮 1 条 Current 参考通过 | 本轮 2 条 Current 参考通过 |
| 边缘/跨缺口 | 原点直线隔墙，本轮未找到合格跨缺口候选 | 原点可直接走下，本轮未找到合格跨缺口候选 | 原点直线隔墙，本轮未找到合格跨缺口候选 |
| 助跑 | R4 合格点新键输入通过 | 合法绕行已证实，原直跳资格仍未放行 | 原候选被墙阻挡，仍需替代路线 |
| 蹲跳 | R4 新键输入通过 | R4 后退助跑输入通过 | R4 新键输入通过 |

普通跳需按离地/落地与动作稳定性观察；原地站着就在目标内的 walk_only 不能用来冒充跳跃通路能力。原关键落点三图同样是 walk_only，本轮补的是另外的高差路线。

跨缺口搜索每图有明确上限：按到 A/B 最近距离排序的 **128 个导航节点**，四个正交方向、2.4/3.0/3.6 m，要求同高可站立终点、三个中间采样至少两个落差 >0.6 m 或无支撑，并且有完整身体通道。本轮三图均未找到符合条件的缺口，**不是全图穷尽，也不证明原图不存在相关跳点**。不得用普通台阶或可走下的边缘补成“已完成”。

## 窗口观察入口

新增 `tools/authoring/open_jump_playtest.gd` 与 `JumpPlaytestSession.gd`，独立运行、未接入正式菜单，本批未更新试玩包。真实窗口加载原地图及 Main 的地图环境辅助逻辑，显示无碰撞的首落区域标记；标记只用于诊断，不写回地图。默认 Current，F7 只改变这次独立进程内的方案。

在仓库根目录运行（输出文件必须不存在）：

```powershell
& 'D:/Godot/4.7.1/Godot_v4.7.1-stable_win64.exe' --path 'D:/AgentGamePipeline/repos/VectorBreach-godot' -s tools/authoring/open_jump_playtest.gd -- 'D:/AgentGamePipeline/evidence/tactical-jump-coverage-20261025/mirage-candidates-v1.json' 'D:/AgentGamePipeline/evidence/tactical-jump-coverage-20261025/manual-mirage-001.json'
```

另两图将清单换成 `dust2-candidates-v1.json` / `inferno-candidates-v1.json`，输出换成新的文件名。

- WASD、鼠标、空格、Ctrl、Shift 使用正式玩家绑定；F5 重试，F6 下一点，F7 换方案。
- Esc 释放鼠标并停用玩家操作，F4 继续；F8 保存退出，关窗同样保存。不会覆盖既有凭据。
- 保存每次重试的输入/物理帧、事件与消费时间、位移/速度、方案及冻结资源身份；每次最多 7200 样本，超出显式标记截断。
- 人工记录应分别评价移动响应、跳跃、急停、开镜、地图可达性和舒适度；本入口没有枪战或完整比赛，不能代替开镜/战斗评测。原机多版本对照仍独立待验。
- 输出始终 `human_review=pending`、`formal_release_ready=false`。自动保存、切换次数或看过截图都不能自动判人工通过。当前窗口按项目默认物理频率；120 Hz 的人工窗口比较仍待安排，不能用本轮自动回放替代。

## 验证与证据

普通 Python **153 项**（新增 11 项），GDScript 格式/lint、Python 编译/Ruff F、资源导入及身份/保持检查通过。原四个脏导入与用户设置逐字节保持，生产路径未改，不重复完整原生或比赛套件。

窗口逻辑冒烟覆盖切方案、重试、换点、Esc/F4 和保存；真实 **Vulkan / Forward+** 的 Mirage A 区渲染、观察提示与目标标记已截图查看。首次入口的动态类型推断错误已修，首次环境节点 owner 警告已清理，过大的标记已缩小并调淡；失败/初稿保留，最终日志无脚本错误。渲染检查是短时自动冒烟，**不是人工试玩、三图全视觉审查或 70% FPS 验收**。

完整本机证据在 `D:/AgentGamePipeline/evidence/tactical-jump-coverage-20261025/`；仓库仅保存[无绝对地图坐标汇总](evidence/tactical-jump-coverage-20261025/summary.json)。最终窗口图为 `window-render-reviewed.json.png`，人工复核仍 pending。提交/PR/精确头 CI 首查见本机 `delivery.json`，不等 CI。

下一片先给四条新路线补 Legacy/Modern 双频率矩阵，再从原地图真实高差/走廊明确剩余助跑与边缘候选；人工窗口观察与原机对照并行准备。**Movement-4 未验收，Movement-5 冻结**；最新头 18 场、连续人工三图与逐图 70% FPS 仍未完成。
