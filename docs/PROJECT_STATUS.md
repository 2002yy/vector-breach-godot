# Vector Breach Project Status

Updated: 2026-10-18

Mirage 低处悬空贴花已按根因修复：Source2Viewer 20.1 把 overlay 沿法线推离约 39.37 cm，现抵消多余偏移、保留 1 mm，覆盖 Mirage 301 / Inferno 263 个表面，原网格、UV、纹理与碰撞保持不变。新包位于 `C:/Users/Zhang/Documents/VectorBreach-builds/VectorBreach-overlay-fix-20261018/`，实际 EXE 和 PCK 三图 144 个俯视、Mirage 88 个水平路线视角通过；井盖与用户同位置前后对照保存。测试、当前头 CI/复审/合并和包哈希见 [本片任务](TASK_MIRAGE_OVERLAYS_2026-10-18.md) 及私有交付收据。另有修复前已存在的 A 点黑底黄色秒表条带待查，**全图材质验收未通过**。三图六份性能诊断因 Window 与实际纹理尺寸不一致不算严格分辨率达标；下一片先核对实际渲染纹理，再继续性能目标。

道路上方悬空灰面已完成本机修复及包验证：Mirage `dust_002` 灰尘与 Inferno `steam_001` 蒸汽的源特效语义未进入 glTF，导致不透明面。已接入原生解码 alpha/遮罩、普通透明/加色混合，并从 Inferno 遮挡中排除特效面。最终 PCK 同 54 视角中两处灰面消失，额外遮挡开关对照通过，实际 EXE 正常启动退出 0；完整原生 181 项、GdUnit 2/2 通过。原几何/纹理/碰撞/路网保留，PR #47 与远端交付收据见 [本片记录](TASK_CLASSIC_EFFECT_SURFACES_2026-10-18.md)。Dust II 本次 18 张未发现同类明显异常，不代表全图通过；深度羽化等完整源特效及三图完整材质验收仍未关闭。

最新要求与未完成验收：三张经典图全部原版资源、实测可玩及 AI 基本策略；用户接受公开 RTX 5060 笔记本原生实测作临时性能参考。临时平均目标 105 FPS（公开 2.5K 高画质平均 149.2 的 70% 向上取整），目前未达标验收；AI 整场协同/残局、更多武器与经济、死亡观战和完整比赛平衡明确未完成，详见 [三图与完整比赛后续清单](TASK_CLASSIC_GAME_ACCEPTANCE_2026-10-18.md)。原版手雷与完整作战动作图仍需补齐。下一执行片为原生 2560×1600 三图前台基线与瓶颈分析。

官方人物和装备已接入本机：六套全身及对应专用双手、M4A1-S / AK-47 / Glock、双方默认刀、手持及地面 C4，购买页使用原模型图片；旧资产和缺失资源时的回退保留。完整原生 180 项、GdUnit 2/2 和 Vulkan 画面通过。PR #45 已合并 main `0e605be`，候选 `6ca73fe` 的 CI 和复审通过；最终包及 main 远端状态见 [本批记录](TASK_OFFICIAL_CHARACTER_EQUIPMENT_IMPORT_2026-10-17.md) 和私有交付收据。完整原版作战动作图尚未移植，现有时间轴与部分原生枪械片段已适配。

性能 PR #43、整理 PR #44 已合并。装备替换前 CT 固定出生视角、1600×900、正常 5v5 平均 Dust II 191.31、Mirage 107.72、Inferno 76.68 FPS；这是历史抽样，不是新包全图性能验收，见 [性能记录](TASK_INFERNO_PERFORMANCE_2026-10-17.md)。

本文档是仓库唯一的状态、边界与优先级来源。README 和各地图设计记录只保留入口说明或设计约束；如与本文冲突，以当前检出、自动测试和本文为准。

## 2026-10-17 Inferno 密集路网性能切片

原材质与渲染性能 PR #42 已合入 main `1e7e9c8`。后续逐帧检查揭示周期寻路长帧，现对大于等于 256 点且成本完全为欧氏距离的图使用原生 AStar3D；危险事件和加权图继续保留原战术成本。Inferno 四条实际路线查询从约 8–18 ms 降至 0.15–0.31 ms，节点序列一致。新增危险绕行、重新配置和最短路回归；默认显示设置、完整回归与精确远端闭环见 [本片记录](TASK_INFERNO_PERFORMANCE_2026-10-17.md) 及交付收据。秒级间歇停顿和长局/全图验收仍需与寻路查询收益分开，不宣称稳定 60 帧。

## 2026-10-17 官方原始地图接入与 Inferno 性能

Inferno、Mirage 已在本机切换为固定官方 VPK 导出的原网格、UV、原始贴图与独立原生物理；旧重建版保留备份。3408 个公共依赖 CRC/SHA 校验、113 张原 VTEX 非恒定 alpha 恢复、1229 张 BC7/mipmap 导入已完成，两图实际选图/换肤/购买/点击就绪/5v5 通过。Source 2 着色器、烘焙灯光与全部查询层不等同原游戏。

Inferno 原正常速度 CT 5v5 34 FPS（中位）主要受绘制提交/阴影开销限制。新增保守不透明墙面遮挡剔除及本图 60 米/两级太阳阴影；相同 1600×900 复测中位 69、最低 59 FPS，贴图/分辨率不变。十处开关遮挡画面对照未见误隐藏；这是抽样，保留远处阴影精度与距离的画面取舍。渲染配置切换恢复及实际碰撞射线回归通过，重新冻结的路网布局完全不变。

可复用步骤见 [官方地图取得手册](CS_OFFICIAL_MAP_ACQUISITION.md)，失败、验证、私有证据和最终交付收据见 [本批任务](TASK_OFFICIAL_CLASSIC_MAPS_2026-10-16.md)。性能修改后原生 178 项 `RUN_ALL_OK`、GdUnit 2/2 及资产约束检查通过；进攻方正常速度 60 秒中位 112、最低 96 FPS。原材料不进入公开 Git，最终包验证/远端闭环以交付收据为准。长局人工平衡与全部区域的性能验收仍开放。

## 2026-10-16 官方地图原始资源取得方法归档（历史）

已回查第一张 Dust II 的官方 depot / manifest、VPK 哈希、视觉/物理/导航转换来源，并实测 Steam 匿名取得当前 app 730 / depot 2347770 的完整清单。可复用的固定版本、定向下载、断点、哈希校验、公共依赖补齐、导出及 Godot 适配步骤见 [官方地图取得手册](CS_OFFICIAL_MAP_ACQUISITION.md)。本次新两图原包及工具下载遇到 CDN 超时/SSL 错误，已停止并保留私有断点；未宣称原始材质版取得、转换或替换成功。当前可玩版本保持不变，下一片为恢复下载并先完成一张图的原始资源导出验收。

## 2026-10-16 新经典图与实际换肤入口

本机新增炼狱小镇 Inferno、荒漠迷城 Mirage，游戏组标注“经典复刻·重建材质”，接入冻结路网、双爆点、5v5、$800 手枪局、最多 60 秒购买和点击就绪。它们保留来源几何，使用重建材质及独立的简化地图物理，并非原始贴图版；素材与坐标不进入公开 Git。设置页真实点击选择已验证对应第一人称原生袖子/手套；暂停后新增“结束当前对局，返回选图”，避免原先选项看似可换、实际被忽略。

新图自然局揭示旧 AI 缺少离散台阶跨越、密集拐角过早跳过路点；现加入与玩家同为 42 厘米上限的碰撞检测抬步，并为离线烘焙门户配置较小到达半径。修复后 Inferno 防守视角 110 秒记录 55 次 AI 射击；Mirage 60 秒记录 26 次并安装 C4，最高脱困分别 4 / 1 次。原生 176 项和 GdUnit 2 项通过；这不关闭全图材质、全部路径、长局平衡或人工验收。来源、复现、实际 UI / 导出包证据和最终远端收据见 [本批任务记录](TASK_CLASSIC_MAPS_UI_2026-10-16.md)。

## 2026-10-16 六套 CS 角色接入

已将本机取得的六套原生角色接入 AI 全身与第一人称蒙皮袖子/手套：防守方海豹、英国特勤、联邦特警；进攻方凤凰、精英叛军、黑狼。同队 AI 轮换三种外观，设置可分别选择两方玩家外观并持久化。核心骨架统一并重定向步枪/手枪/刀的站立、跑动、蹲伏及受击、死亡；原碰撞和伤害规则独立。运行素材留在被忽略的本机目录；公开仓库提交转换工具、加载/回退、设置和行为回归。本机六套动作、实际经典图 5v5、手腕与肘部接触已验证；远端测试与交付记录、来源和剩余的第一人称纹素/贴合打磨边界见 [角色接入记录](TASK_CS_CHARACTERS_2026-10-16.md)。未将本次接入称为完整 Valve 第一人称动作或用户最终美术批准。

## 2026-10-15 用户截图反馈：前臂与握持修正

基线 main `5f74e7a`，分支 `fix/viewmodel-sleeves-grip-20261015`。用户指出前臂粗糙，覆盖此前局部美术审查结论：胶囊前臂确实仍是占位，枪械 GLB 还残留旧静态手臂，与关节双手重复显示。现以可编辑 Blender 的收窄椭圆袖子、非对称褶皱、双侧裁缝线和针织袖口替换；手套软垫边缘与指节柔化，隐藏两把枪自带的静态袖子/手套，步枪左手移至护木下方。新增跨装备/动作袖口接触和重复手臂回归。详情、验证与交付边界见 [修正记录](TASK_SLEEVES_GRIP_2026-10-15.md)。这次改善不代表最终写实蒙皮双手或用户美术批准。

## 2026-10-15 经典图修复、背刺、独立训练和装备升级

用户明确授权本批改造、验证和既有远程交付流程，覆盖旧的 G2 前具体功能冻结。基线 main `1e2f1b8`；当前功能、证据和交付状态见 [任务记录](TASK_CLASSIC_TRAINING_ART_2026-10-15.md)。

- 经典图回收路线卡点根因为三角网格坡脚处的小步横向速度被 floor-stop 取消；共享 TacticalActor 以真实接触法线补入切线抬升，不跳跃、不瞬移、不修改地图碰撞或路网。守点队友在目标附近让位，安装/拆除/回收仍保持严格交互距离。隔离旧卡点的完整回收探针实际捡到 C4，0 次脱困；路径修复阶段自然局最大 1 次脱困；最终复测另发现守点队员阻挡出发，已补主动侧让，复测最大 2 次脱困且回收者实际离开 B 点，但仍以 TIME 结束，不宣称全面战术或平衡通过。
- 两种经典视觉版本沿 A 长路、A 小道、中路至 B、B 通道和高架共 40 个视角检查。额外修正 olive_bark_01 的动画权重误作紫色顶点色；保留原贴图与透明规则。重构版为简化风格，未冒充恢复原图全部纹理；研究素材继续仅本机保留。
- 刀具背后 120 度扇区接触伤害为基础 3 倍，轻砍 120 / 重刺 195（本作规则，仍经部位与护甲结算）。判定使用接触时的位置和目标朝向；敌我 AI 共用。真实命中、正面/侧面、墙体阻挡及背刺提示有回归。
- 默认游戏菜单新增独立训练场，不计比赛分数/经济，不限时。步枪/手枪、无限备弹（保留弹匣和换弹）、自动补雷、靶子重生；F5 重置玩家/目标/统计，F6 补给清场，F7 返回选图，F4 统计。回到比赛后恢复 $800 手枪局、计时与实际库存。
- 新原创 Blender canonical master 和运行 GLB 替换手套掌背/指节、刀与三类手雷；PBR 材质、UV、外部保险环/压杆和 32 关节动作保留，插值细化。六面正交与第一人称动作检查独立留证，仍为风格化资产，未宣称最终写实蒙皮双手。
- C4 六面、掉落/安装/紧迫状态已重新采样审查。资产人工签核字段仍为 draft；不将自动化或截图代替最终用户美术/听感批准。G2 十场人工比赛与 G3 全面战术质量仍开放。

## 2026-10-13 用户授权的入口与 AI 缺陷修复

历史 PR #33 和 #27 已分别合并。C4 已补本机 Vulkan、输入/混音器与全套原生证据；当前头 `8a68658` 的 Tests 及完整 Windows Export / smoke 均通过，main 合并为 `a97f787`。详情见 [C4 集成记录](TASK_C4_INTEGRATION_2026-10-13.md)。本次明确集成授权覆盖旧记录的待 L3 合并授权；资产人工美术/听感仍保留 draft，不宣称完成 G2。

最新覆盖：用户继续授权经典图 5v5、明确购买页、生成枪械插画、最多 60 秒准备并点击就绪立即开战，以及整理合并所有 PR。两种经典沙线入口现已接入玩家加四名队友对五名敌人的单机爆破，复用经济、换边和结算；首局/换边改为手枪 $800。门厅区保留 3v3。旧的“经典图仅练枪/5v5 未实现”记录已被本段覆盖。购买页面使用 Codex 生成的透明枪械图片，已检查本机 Vulkan 显示。玩家死亡不提前判整队输，AI 斜坡误绕、五人经济阈值与缺少回合收入已修复；经典路网由本机冻结 JSON 控制，资源变动时拒绝启动而不自动重建。范围、执行证据和未完成人工验收见 [5v5 购买任务](TASK_CLASSIC_5V5_BUY_2026-10-13.md)。历史 PR #33/#27 已合并；购买与 5v5 的远程交付见 [PR #34](https://github.com/2002yy/vector-breach-godot/pull/34)；精确提交、CI 与合并状态记入任务的交付 JSON。四类装备的外形与功能差距见 [经典装备核对](CS_WEAPON_SLOTS_AUDIT_2026-10-14.md)。

- 游戏位置、操作和地图历史已集中到 [中文指南](GAME_GUIDE_ZH.md)，桌面 `3Dgame\游戏在哪里.md` 留有入口。工作分支 `fix/onboarding-maps-ai-20261013`，基线 `main / 99f0506`；用户已授权提交并推送，远程交付见任务记录。
- 菜单分为互斥的游戏 / 开发测试列表；本机可用时两种沙线研究入口默认可见。铸造仓库改名“路线回归”，三张开发图都有现行测试依赖而保留；没有改变碰撞 / 路线数据。开局左侧缩短地图说明并收起设置，右侧独立显示操作或设置。
- 门厅区保持首局 / 换边手枪与 $800；练习图开局真实拥有步枪与手枪；经典研究图现为竞技手枪局，后续购买主武器。菜单解释规则，战斗常驻按键提示并支持 F1 帮助。
- 修复 AI 实战武器与显示手枪不一致、没有真实步枪购买步骤、玩家队伍资金漏算和隔墙近敌人压掉可见目标。敌我使用同一修复，未改伤害、反应或瞄准数值。
- 经典 CS（Dust II / `de_dust2`）两种本机研究版本已验证落地、移动、步枪 / 手枪、切枪与练习靶真实掉血；现为本机 5v5 爆破，两种视觉版本共用同一套路网与规则。原始材质版的顶点动画权重误作颜色已修复，Vulkan 出生点植物 / 布篷截图通过；全图材质和最终美术尚未验收。经典 HUD 显示双方五人、比赛阶段和真实爆破任务。
- 本次用户明确要求具体 AI 修复，优先于此前 G2 前的缺陷冻结；G2 十场人工比赛、G3 完整战术质量和最终平衡仍未关闭。详情与验收证据见 [任务记录](TASK_ONBOARDING_AI_2026-10-13.md)。

## 2026-10-14 装备第一人称显示与 C4 交互

5v5 / 购买页 PR #34 已合入 main `7e2aaec`；精确头 `886ec89` 的 Tests `38442545583` 与 Windows Export / smoke `38442545406` 全绿，两个审阅缺陷已修复并关闭。

用户继续授权刀具、手雷等接入第一人称，同时改善 C4 交互与显著提示。本次基线 `7e2aaec`，分支 `feature/equipment-viewmodel-c4-20261014`：刀、高爆、闪光、烟雾为原创程序化显示模型，手持与投出共用类型外形；C4 复用已集成的 GLB 并调整第一人称尺度/朝向。装备选择、使用、自动切换与重置同步显示；同一枪槽重新选取和未持有枪的输入已明确处理。按 5 查看持有的 C4，爆点内按住 E 或持 C4 按住左键安装，释放取消；附近拾取与拆除提示、真实进度、拆弹器 5/10 秒说明、世界 C4 状态标签已接入。此段记录 PR #35 时的状态；右键重刺与关节双手已由 PR #36 实现，背刺和可编辑资产升级见 2026-10-15 记录。证据和远程交付见 [装备显示任务](TASK_EQUIPMENT_VIEWMODEL_2026-10-14.md)。

## 2026-10-14 双手动作、右键重刺与 AI 路径进度

装备显示 PR #35 已合入 main `009be98`。用户继续明确授权完整手部动作、刀具右键重刺、修复 AI 绕静止玩家及优化行为策略，本次授权覆盖 G2 前的具体缺陷冻结。执行契约见 [双手与 AI 任务](TASK_HANDS_KNIFE_AI_2026-10-14.md)。

- 原创程序化双手有 32 个手腕/手指关节，前臂连接随手腕运动；AnimationPlayer 驱动拔出、开火、换弹取弹匣/上膛、挥砍、重刺、拔销投掷、安装/拆除，并保留待机呼吸、行走、落地。交互时收起枪/刀，安装时显示 C4。属于可玩原型动作覆盖，未宣称最终写实蒙皮资产。
- 刀具左键 40 基础伤害、2.15m、0.45s；右键 65、1.85m、0.95s。0.12s/0.22s 接触时判定，使用共享伤害路径、共用冷却。切装备/暂停/死亡不能遗留延迟攻击；投掷物 0.30s 出手，动作完成再自动切换。数值为本作设定，背刺倍率尚未实现。
- 修复周期性 A* 刷新将长边路径索引归零导致折返的问题。加入近战追近/受击换枪、堵路侧移制动、换目标重新反应、到点观察；C4 掉落后指定一名存活 AI 回收，回收者死亡后重分配，其他人维持原任务。敌我策略一致，碰撞、路线 JSON 与枪械伤害不变。
- 本机原始 CS 研究图自然 5v5：早期 CT 记录出现 53 次 AI 出手并完成安装/拆弹；最终候选复测 CT / T 分别 50 / 54 次出手，均以 TIME 结束。平地回归证明远处回收分工与死亡接替生效，但经典图仍观察到一处回收路径的局部障碍脱困循环，不能宣称完整导航或可靠回收已验收。此前 headless 探针进入测试图而非经典图的结果已排除，新探针要求本机真实地图、9 个 AI 并使用 Vulkan；这些记录不替代 G2/G3 人工长局。

本次完整测试、视觉证据、精确提交与 CI 收录在任务交付记录。下一阶段仍为 G2 人工十场及基于长局证据的 AI 战术审计。

## 产品方向

- 当前产品是 Godot 单机 3D 战术枪战原型：复现经典竞技射击的移动、枪械纪律、经济与爆破决策，同时以原创地图、战术 AI 和枪械手感形成自主内容。
- 自研优先级为：战术 AI > 原创地图 > 枪械手感。
- 当前目标不是逐帧复制某一款游戏，也不继续旧 Babylon/WebGL 实现。
- 私人研究可以保留高相似度对照内容；公开仓库和作品集只使用原创或来源/许可清晰的内容。

## 当前可验证基线

### 核心玩法

- 移动：默认奔跑、Shift 静步、蹲伏、普通跳与蹲跳；包含急停、有限空中修正、落地精度惩罚、受击减速和坠落伤害，无二段跳或自动翻越。
- 枪械：步枪 30 发固定后坐力轨迹、半自动手枪、距离衰减、五类命中部位、护甲/头盔、材质与厚度穿透、掉落/拾取、换弹和第一人称反馈。
- 回合：T/CT 阵营、冻结购买、经济奖励、C4 携带/掉落/拾取、持续安装/拆除、爆炸、淘汰胜负和自动进入下一回合。
- 战术装备：刀、HE、闪光和烟雾；烟雾会同时阻断视觉、雷达侦测和 AI 视线。
- HUD：比分、时间、存活人数、生命、护甲、金钱、弹药、击杀信息、逐单位计分板、C4 交互和回合训练总结。
- 环境语义：地图 JSON 可定义梯子和浅/深水体积；碰撞与路线权威来自 JSON，视觉 GLB 不得静默改动玩法拓扑。

### 战术 AI

- Gatehouse 与 Core Vault 已配置 3 T + 3 CT；玩家选择阵营后，异队 Bot 成为敌人，同队 Bot 成为 AI 队友。
- Bot 使用带危险、掩体与通行属性的双向连接图和 A* 重规划，支持视听感知、烟雾遮挡、反应/瞄准延迟、急停、分级火力、换弹、蹲伏、侧移、低血撤退和脱困。
- 爆破闭环已覆盖 T 携带/安装、CT 回防/拆除、Bot 互射、同队报点、C4 掉落拾取、目标区投烟、交火 HE/闪光和持续交互归属保护。
- Bot 已具备独立金钱、强起/半起/eco、完整基础武器与备弹库存、冻结购买、掉枪拾枪、团队经济分级、跨回合保枪、距离化投掷和曲线压枪。
- 当前 AI 仍基于带属性路线图而非完整导航网格；未标注区域、复杂自由寻路和跳跃连接仍可能失败。队伍战术尚未形成完整补枪、回防优先级和玩家指令树。

### 表现与资产

- 共享低模战术角色使用 15 骨骼 Armature，33/33 可见网格具有蒙皮权重，内嵌 idle、run、crouch、hit、death 五个动作；胶囊碰撞和五区命中仍是战斗权威。
- 现有角色属于可用的低模表现资产，不是最终正式角色。敌我识别由深色主体和 CT 蓝/T 橙局部标识承担。
- 战斗音频包含 14 个已核验来源的 CC0 Ogg 采样及程序化回退；尚无语音报点。
- 第一人称步枪与手枪已由独立确定性 Blender 管线重制为原创近未来战术资产：步枪包含分体护木、上下机匣、骨架枪托、红点、制退器和操作件，手枪包含切角套筒、退壳口、套筒纹、底把导轨和独立控制件；现有移动摆动、后坐、落地和换弹反馈保持兼容。2026-08-25 用户直接授权该 G5 局部例外，但它不代表 G2/G5 整体门槛通过。
- 7 个 Git tracked Blender canonical master 已集中在 `assets-source/blender/` 并由 Git LFS 管理；每个 master 都有相邻 `*.asset.json` sidecar 记录资产身份、canonical source path 与 tracked runtime outputs。Godot 运行时资产继续位于 `assets/`，源 `.blend` 不直接成为运行时权威。
- Foundry Reforged 已有 Vulkan 视觉、性能和作品集录屏证据；Gatehouse 尚未达到同等级作品集画面。
- 2026-08-24 用户授权的视觉基础已扩展为全地图默认体系：Test Collision Room、Foundry Depot、Gatehouse、Core Vault 与 Foundry Reforged 均继承 CC0 阴天纯天空、暖色阴影方向主光、冷色环境光、ACES、轻量雾和 SSAO；旧地图头顶点光默认关闭，Gatehouse、Core Vault 与 Foundry Depot 的悬空灯具几何已从确定性生成资产移除。Gatehouse 仍保留 28 根接地且贴合边界的尺度节奏柱。该改动是 G5 前置基础，不代表 G5 作品集验收完成，也不解除 G2 十场人工比赛门槛。
- Dustline Depths 是唯一复刻研究图；本机可用时菜单提供 `dustline-depths-original-local`，直接使用 `assets/local_reference` 下的原始视觉/材质和项目内审计碰撞。第三方原始素材保持 local-only、排除于 Git 与公开主演示。
- 本机默认游戏入口 `play.cmd` 固定以 `--gpu-index 0` 启动 Forward+；当前设备枚举中 #0 为 RTX 5060 Laptop 独显、#1 为 Intel 核显。Vulkan 视觉探针已确认实际使用 #0。

## 地图归属与用途

| 地图 | 设计来源 | 当前用途 | 下一阶段承诺 |
|---|---|---|---|
| Test Collision Room | 自研测试夹具 | 移动、碰撞、梯子、水体验证 | 仅回归，不做正式美术 |
| Foundry Depot v2 | 参考 CS/Source 尺度规范的原创布局 | 冻结历史基线与回归 | 不改布局 |
| Foundry Reforged | 基于 Depot 经验独立重建的原创双目标地图 | 原创视觉展示与性能基线 | 不迁移完整 3v3 |
| Gatehouse | 项目旧灰盒的 13 个障碍尺寸 + 新增原创战术/视觉层 | 当前最完整的 3v3 爆破图 | 唯一主验收图 |
| Core Vault | 项目旧灰盒的 15 个障碍尺寸 + 新增原创战术/视觉层 | 更密集的 3v3 回归图 | 只做回归，不做同级平衡 |
| Dustline Depths | `de_dust2` 地面拓扑派生 + 自研 B 区空中走廊 | 本机复刻研究与尺度对照 | 不进入公开主演示；原创化另立后续阶段 |

## 当前验证

- Windows 与 Linux 聚合脚本统一运行十二套原生测试：关卡数据、武器、灰盒关卡、命中反馈、战术 Bot、爆破 AI、比赛生命周期、Gatehouse 场景集成、主状态流、音频资产、C4 设备和性能预算；上一轮 main `1e2f1b8` 为 165 项；本轮增加坡脚、背刺和训练回归，最终数量与执行结果见当前任务记录。
- 已接入 GdUnit4 v6.2.1（`addons/gdUnit4`，经 Godot 4.7.1 headless 验证 2 用例 PASS），作为原生测试之外的行业标准补充框架；新测试放 `test/`，报告目录 `reports/` 已忽略，运行方式为 `runtest.cmd`（需 `GODOT_BIN` 指向引擎）。
- Required `Tests` 已在 Godot 之前执行 Asset Layer、Asset Metadata 与 Asset Runtime Contract policy：当前 canonical source master 为 7 个，metadata sidecar 覆盖 7/7、资产 ID 唯一；7 个 Blender producer 拥有 14 个 runtime outputs，其中 8 个 GLB 必须具有合法 runtime contract。sidecar 中 runtime outputs 必须是 `assets/` 下规范、去重且 Git tracked 的实存路径；mandatory source coverage 同时包含 Blender/Krita/PSD/FBX 等源资产与音频 master。
- Step 13 已接入 Blender 5.2.1 LTS headless source gate：6/6 tracked Blender master 在真实 canonical path 上通过 naming safety、外部 FILE/SEQUENCE/MOVIE/TILED/UDIM 资源实存、geometry unit scale、finite/non-singular transform、metadata/source identity 与二进制/LFS preflight；正向 PR #18 随后继续通过 Godot import、GdUnit4 与 native suites。
- Step 13 的 do-not-merge 负测 PR #19 在 Asset Layer/Metadata 保持 PASS 后，仅在 CI 工作树把 `GEO-pistol-barrel` 临时改为 scale `(2, 1, 1)`；Blender gate 精确报 `geometry object has unapplied scale` 并失败，Godot 安装、import、GdUnit4 与 native suites 全部 skipped。坏 `.blend` 未提交或合并，证明 source-art gate 具备 fail-fast 阻断能力。
- Step 15 正向 PR #25 head `5f525aeaca53e71f5914a3367db1c784ff4b1265` 的 required `Tests` run `33308981479` 与 legacy `Godot Tests` run `33308981476` 均 success；fresh rebuild 后 7 个 Blender-owned GLB 全部通过 runtime structural/budget validation，随后 Godot import、GdUnit4 与 native suites 全绿。
- Step 15 do-not-merge 负测 PR #26 仅把 Gatehouse `max.triangles` 从 5000 降为 3000；fresh `gatehouse.glb` 实测 3356 triangles，required `Tests` run `33310639857` 精确报 `actual=3356 max=3000` 并在 Asset Runtime Gate 失败，Godot install/import、GdUnit4、Native 全 skipped。PR #26 已关闭未合并，负向分支已复位到 #25 正向 head。
- Step 16 runtime/workflow 证据 head `69d2a3395d2cb7799f923868a1d07adb5fe34e96` 的 required `Tests` run `33326528374` 与 legacy `Godot Tests` run `33326528372` 均 success；required 链从 cheap policy、Blender 5.2.1 source validation、fresh publish/rebuild、C4 runtime contract/budget validation继续通过 Godot 4.7.1 import、GdUnit4、native suites 与报告上传。
- Step 16 `Windows Export #14`（`33326528381`）在同一 `69d2a339` head 上 success：增量 detector 对 `.github/workflows/windows-export.yml` 的 synchronize 变化输出 `should_export=true / synchronize-runtime-or-export-change`，随后 Godot 4.7.1 完成资源导入与 Windows EXE/PCK 导出，产物校验、ZIP/SHA256、artifact 上传以及 `windows-latest` runner 的 SHA256 校验、解包和真实 `VectorBreach.exe --headless` 启动均 success。
- Step 16 docs-only 增量门禁验收 head `8d22af07f69a398a6d9d8ea22fecaf80326c4f13` 的 `Windows Export #15`（`33327150974`）success：detector 对唯一变化 `docs/STEP16_WINDOWS_EXPORT_INCREMENTAL_GATE.md` 输出 `should_export=false / synchronize-nonruntime-only`，`export-windows` 与 `smoke-windows` 两个重型 job 均 skipped。由此验证两级门禁同时满足“runtime/workflow 变化必须导出”和“后续 docs-only synchronize 不重复烧重型构建”；若 `before` SHA 缺失或不可验证则 fail-open 到完整导出。长期验收记录见 `docs/STEP16_WINDOWS_EXPORT_INCREMENTAL_GATE.md`。
- Step 16 do-not-merge 负测 PR #28 将 C4 runtime triangle budget 降到真实产物以下；Asset Layer、Metadata、Runtime Contract policy、Blender source 与 fresh publish/rebuild 均 PASS，Asset Runtime Gate 精确 FAIL，Godot install/import、GdUnit4 与 native suites 全 skipped。PR #28 已关闭未合并，证明 C4 真实 feature 仍遵守 runtime fail-closed 顺序。
- Gatehouse 场景集成测试以真实 `Main.tscn` 覆盖 T/CT 开局与半场、6:6 两局加时、同一 Main 新比赛隔离和重复 end/restart 幂等；验证真实 3v3、出生/换边、经济装备、逐单位统计、C4 唯一归属与旧实体清理。G1 已通过，下一门槛为 G2 十场人工完整比赛。
- Gatehouse 路线图为 39 节点/48 连接，三路首次接触为 7.83–8.39 秒，A/B 守方轮转为 4.49 秒；西路已绕开检查平台楼梯碰撞。
- Core Vault 路线图为 44 节点/54 连接，三路首次接触为 8.23–8.42 秒，A/B 轮转为 10.16 秒。
- Gatehouse Vulkan 爆破探针已验证 T Bot 携带并安装、CT Bot 携钳回防并拆除，且回合合法结束。
- Foundry Reforged 在 RTX 5060 Laptop / Godot 4.7.1 Forward+ 的参考基线为 196.40 FPS、平均 5.09 ms、p95 7.15 ms、977 draw calls、18,960 primitives 和 226.93 MiB 报告显存，无趋势警告或硬失败。
- 枪械确定性构建校验为步枪 55 对象、手枪 42 对象、共享网格 0；显式接口均为零间隙或受控小重叠。`WeaponViewModelVisualProbe` 已在 RTX 5060 Laptop / Forward+ 同时捕获步枪后坐、换弹、落地和手枪持枪画面，并通过显隐与运动状态契约。

## 工程管线状态（不等同于产品 Gate）

以下条目描述“仓库能否以 fail-closed 方式验证、重建、测试和发布”的工程能力，不代表 G2 十场人工比赛、G5 作品集表现或最终游戏内容已经通过。

- **Git / main 门禁：PASS。** `main` 已启用 branch protection，required check 为 `tests` 且要求分支 up-to-date；管理员同样受保护，force-push 与删除被禁止。故意失败 PR 已实测在无 `--admin` 绕过时被 GitHub 拒绝合并，证明“CI 变红”与“红灯真的挡 main”已经闭环。
- **Godot 自动化：PASS。** Godot 4.7.1 headless import、GdUnit4、十一套 native suites 已进入 required `Tests`；native runner 现在会为每个场景打印 START/PASS/FAIL，并在首个失败场景产生 GitHub error annotation。
- **Windows build：PASS（Step 16 runtime/workflow head 已复验）。** 官方 Godot 4.7.1 CLI + matching export templates 已在 CI 生成 Windows EXE/PCK、ZIP、SHA256 和 artifact。`69d2a339` 的 `Windows Export #14` 已对当前 C4 runtime/workflow tree 完整导出成功。PR 级 `paths` 覆盖 `assets/**`、`data/**`、`scenes/**`、`scripts/**`、工程/导出配置与 workflow 自身；`synchronize` 再由增量 detector 比较 previous head → new head，只在本次变化触及 runtime/export 路径时运行重型导出，无法验证 `before` SHA 时 fail-open。`8d22af07` 的 `Windows Export #15` 已用 docs-only 提交证明重型 job 会正确跳过。早期导出后 SIGABRT 仍由 `exclude_filter="addons/gdUnit4/*"` 按上游建议规避，而非白名单 exit 134。
- **Windows runtime smoke：PASS（Step 16 runtime/workflow head 已复验）。** `Windows Export #14` 的 CI-built artifact 已在 GitHub `windows-latest` runner 上校验 SHA256、解包并真实启动 `VectorBreach.exe --headless --quit-after ...` 成功；`Windows Export #15` 同时证明 docs-only synchronize 不会重复运行该重型 smoke。该证据关闭了所有云端 Windows export/runtime-smoke blocker，但仍不替代用户本机的图形、输入和声音人工验收。
- **Asset Layers / LFS（Step 11）：FULL PASS。** 三层为 `assets-source/` canonical source、`assets-generated/` 可重建 staging、`assets/` reviewed runtime。当前 7 个 Blender master 与 HDR 历史资产已处于真实 Git LFS/受控源资产体系，CI checkout 使用 `lfs: true`；路径门禁已做正/负验收。
- **Asset Metadata（Step 12）：FULL PASS。** 当前 7/7 canonical Blender master 具有相邻 `*.asset.json`；source identity、provenance/license/AI usage 状态、producer、runtime outputs 等由 CI 校验。历史未知信息保持显式 `unknown`，不伪造来源或许可证。
- **Blender Source Validation（Step 13）：FULL PASS。** Blender 5.2.1 LTS 在 CI 中直接打开当前 7/7 canonical `.blend`，验证命名、外部纹理、scale、finite/non-singular transform、metadata identity 与 LFS/binary preflight。PR #19 的 unapplied-scale 负测证明坏 source 会在 Godot 之前 fail-fast。
- **Blender Publish/Rebuild（Step 14）：FULL PASS。** 当前 7 个 canonical producer 通过 metadata 合同拥有 14 个 runtime outputs；Gate 会在 builder 前删除旧 declared outputs，要求 fresh 重建，拒绝未声明 asset-side effect，producer 间恢复工作树，然后让 runtime validator、Godot import、GdUnit4、native suites 消费 fresh runtime set。PR #20 已合并为 `bcb24be4a71b6863d558a73511e00d89e612a9fe`，其建立的 fail-closed publish 机制继续由 Step 16 required `Tests` 成功复用。
- **Step 14 负向证据：PASS。** do-not-merge PR #22 故意让 Tactical Actor producer 创建未声明的 `assets-source/blender/characters/NEGATIVE_ACCEPTANCE_UNDECLARED.txt`；`Blender publish rebuild validation` 精确失败，Godot install/import、GdUnit4、Native 全 skipped。PR 未合并，负向分支随后复位到正向 head。
- **Asset Runtime Gate（Step 15）：FULL PASS。** 当前 7 个 sidecar 为 8 个 Blender-owned GLB 提供 asset-specific runtime contracts；cheap contract policy 在 Blender 安装前校验 schema，fresh rebuild 后 `tools/validate_runtime_assets.py` 校验 GLB/glTF container、引用/embedded resource、bufferView/accessor 边界、finite transform metadata、triangle primitives、结构/预算指标与 extension allowlist，再允许 Godot 消费。Step 16 required `Tests #93` run `33326528374` 已在 C4 与最终 Windows-export 增量门禁代码上全绿，docs-only `Tests #94` 又复验同一 runtime tree 全绿。
- **Step 15 负向证据：PASS。** PR #26 仅改变 Gatehouse triangle budget `5000 -> 3000`，fresh runtime 实测 3356；runtime gate 精确失败并阻断全部 Godot 后续阶段。负测 PR 已关闭未合并，分支已复位，证明 Gate 基于 fresh artifact fail-closed，而非只验证 tracked stale 文件。
- **云端 / CI / Review：FULL PASS。** PR #27 当前两条 P1 inline review thread 均已修复并 resolved；review submissions 仅为 `COMMENTED`，无 `REQUEST_CHANGES`。Source→Runtime、负向 fail-closed、Godot 4.7.1、GdUnit4、native、Windows export/runtime smoke、Windows 增量正/反路径均已有可执行证据。当前不再保留任何可在 GitHub/CI 侧独立完成的 Step 16 blocker。
- **当前人工遗留：OPEN。** 自动化通过不等同于最终人工图形验收；仍保留用户本机 Windows 下的实际画面/输入/声音 smoke，以及必要时 Godot Editor 内的交互式 GdUnit4/场景人工复核。Step 16 还必须读取本机 C4 Vulkan visual/performance evidence，自动化不得替代这些证据。

### Step 16：C4 工程集成已闭环，最终美术签核待定

Step 16 已选定 C4 Device 作为第一项真实 asset-driven feature pressure test，而不是继续预装更多工具。它验证 Step 11–15 的 source ownership、metadata、canonical Blender source、deterministic publish/rebuild 与 fresh GLB runtime gate 是否能支撑真实玩家可见功能变化。

当前已完成：

1. **Feature / Asset Impact Audit。** C4 生产资产、运行时集成、对象状态与测试边界已经进入审计；爆炸半径、致死半径、拾取/交互距离和伤害公式等冻结玩法数值未改。
2. **完整 Source → Runtime 正向链。** C4 canonical `.blend`、sidecar、producer、runtime contract、fresh GLB rebuild、Godot scene/runtime integration 已由 runtime/workflow 证据 head `69d2a3395d2cb7799f923868a1d07adb5fe34e96` 的 required `Tests #93`（`33326528374`）全链验证通过。
3. **Fail-closed 负向证据。** PR #28 只降低 C4 triangle budget，精确在 Asset Runtime Gate 失败且阻断全部 Godot 后续阶段；PR 已关闭未合并。
4. **状态回归补强。** 已修复 armed C4 在跨状态/跨回合时可能残留高亮、beep pitch/播放状态和 site label 的泄漏；C4Device runner 现含 6 项对象级回归，`69d2a339` 的 required `Tests #93` 与 legacy `Godot Tests #122` 双路径 native 均通过，docs-only `8d22af07` 的 #94/#123 又复验同一 runtime tree。
5. **发布门禁压力测试闭环。** Step 16 暴露并修复了两层 Windows 发布问题：首先让 `assets/**`、`data/**`、`scenes/**`、`scripts/**` 的正常 runtime feature 自动进入发布验证；随后用 previous-head → new-head 增量 detector 阻止同一 PR 后续 docs-only synchronize 重复烧重型构建。`Windows Export #14` 在 `69d2a339` 证明 `should_export=true` 时完整 EXE/PCK + Windows smoke 全绿；`Windows Export #15` 在 `8d22af07` 证明 `should_export=false` 时重型 export/smoke 均正确 skipped；不可验证 previous head 时 fail-open。
6. **云端审查闭环。** PR #27 两条 P1 finding 均已修复并 resolved，review submissions 无 `REQUEST_CHANGES`；负测 PR #28 已关闭未合并。当前没有可在 GitHub/CI 侧继续完成的 Step 16 review blocker。
7. **本机视觉/性能探针已就绪。** `run-c4-visual-probe.cmd` 会先删除旧证据，再在真实 `Main.tscn` Gatehouse 场景采样 hidden baseline / dropped / planted calm / planted urgent，输出 `reports/step16-c4-evidence.json` 与 dropped/planted/urgent 三张 PNG；探针主动退出属于正常完成行为。

**当前覆盖状态（2026-10-15）：** 原 PR #27 已合并，旧的 DO NOT MERGE / L3 等待不再适用。2026-10-13 已补本机输入/混音器和 Vulkan 证据；本轮再补 C4 六面、掉落、安装及紧迫状态截图与性能采样。紧迫状态灯光能量和声音 pitch 状态可执行验证通过；主观听感与最终美术签核仍开放，sidecar 保留 draft。旧的“尚无本机证据”不是当前待办。

该 Step 16 属于工程压力测试，不解除产品侧 G2 十场人工比赛和 G5 作品集表现 Gate。当前产品主线仍以 Gatehouse G2 为最近人工验收门槛。

## 下一阶段：Gatehouse 3v3 单机竞技切片

### 目标

在 Gatehouse 上交付可连续完成、可记录、可录制的 3v3 短赛制爆破：玩家与两名 AI 队友对抗三名 AI，完成比赛内换边、经济循环和完整胜负结算；另提供独立训练入口。阶段结束时，项目应同时具备可复现的稳定性证据和作品集级第一人称演示。

### 比赛规则

- 常规阶段最多 12 回合；6 回合后攻守换边并重置双方经济和装备，保留比赛比分及逐单位统计。
- 常规阶段一方先取得 7 分即结束比赛。
- 6:6 时忽略“先到 7 分”并完整进行一组两回合加时，双方各进攻一次；加时组结束后高分方获胜，若仍平分则允许平局。本阶段不做无限加时。
- 每场保留冻结购买、经济局、掉枪拾枪、保枪、安装和拆除，不采用预安装炸弹或取消经济的 Retake 规则。
- 赛后返回结算页，可开始新比赛并彻底重置比赛级状态。

### 实施顺序

1. 比赛生命周期与证据：比赛开始/半场/加时/结束/新比赛、比赛级统计与可导出记录。
2. AI 稳定与战术：按“稳定 > 战术 > 玩家协作 > 拟人表现”处理缺口，先消除阻断，再优化行为质量。
3. Gatehouse 与训练：只依据长局数据局部调整掩体、门洞、卡点和转点距离；增加独立训练入口。
4. 表现与交付：升级第一人称武器模型，完成 Gatehouse 灯光、HUD、特效、动画和作品集录屏。

不得并行扩展多个步骤；前一步验收通过后再进入下一步。

第 1 步的自动化与状态正确性已完成并通过 G1。G2 十场人工完整比赛仍是整体产品的下一门槛；2026-10-13 用户直接授权的具体武器、经济与视线缺陷修复例外已记录于本文开头，其他 AI 行为质量扩展仍不提前启动。

### 允许修改的边界

- 可修改比赛/回合状态、AI 决策与协作、Gatehouse 路线元数据和局部几何、训练 UI/逻辑、第一人称武器表现、Gatehouse 灯光与演示资产。
- Gatehouse 必须保持三路、双爆点和现有主尺度；局部调整须重新测量首次接触、转点和玩家胶囊通行。
- 战斗数值或枪械判定如需改变，必须由长局数据支持，并增加对应回归；视觉资产不得成为碰撞或命中的隐式权威。

### 明确非目标

- 联网、服务器权威、状态复制、延迟补偿、匹配、排位、断线重连或观察模式。
- 新正式第三人称角色模型、完整语音报点或全武器库扩充。
- Core Vault 同等级长局平衡、Foundry Reforged 3v3 迁移、Foundry Depot 布局修改。
- Dustline 原创化、公开主演示或第三方参考资产提交。
- 外部玩家测试；先完成本阶段内部验收，外部试玩另开阶段。
- 无限加时、复杂赛制投票、长期账号成长或商业化系统。

### PASS / FAIL 验收门槛

#### G1：自动化与状态正确性

- 聚合原生测试出现 `RUN_ALL_OK`；新增比赛、AI、训练、地图和 UI 行为必须有自动回归。
- 半场换边、经济/装备重置、比分与逐单位统计保留、加时双方各进攻一次、平局/胜负、新比赛全量重置均有可执行测试。
- 任一状态只能结束一次；不得重复结算、跨比赛泄漏金钱/装备/C4 所有权或遗留实体。

#### G2：十场完整比赛

- 人工完成连续 10 场 Gatehouse 比赛；每场从菜单开始，经半场和合法终局返回结算页，不借助调试跳过回合。
- 10 场必须覆盖玩家从 T 和 CT 起始；胜负与加时结果由玩家自然进行,不作强制要求。常规胜负边界与完整 6:6 加时生命周期由确定性探针单独留证（2026-08-23 规则修订：不再强制人工批次覆盖这些低频边界）。
- 正式批次必须先开启不间断外部录屏，再用 `tools/run_g2_session.ps1 -RecordingConfirmed` 启动唯一可见 Godot 进程；采集器记录进程、提交和旧文件基线，只复制该进程期间新增的完整 Gatehouse 终局记录。JSON 证明状态正确，连续录屏证明人工、菜单路径与无调试跳局，二者缺一均不得通过 G2。
- 每场原始 JSON 必须保留；`tools/validate_g2_records.ps1` 只读取 `raw/*.json`，校验生命周期、3v3 计分板、连续比赛序号、5 次 T/5 次 CT 开局和 SHA256 唯一性，并生成 `aggregate.json`、`aggregate.md` 与 `SHA256SUMS.txt`（胜负/加时覆盖仅记录统计，不作 FAIL 条件）。
- 任何崩溃、软锁、无法结束的回合、AI 永久卡死、C4 无主且不可恢复、换边/新比赛状态泄漏均为 FAIL。
- 操作手册（一键启动 `play-g2.cmd`、彩排流程、失败条件、产物结构）见 [`docs/G2_OPERATOR_GUIDE.md`](G2_OPERATOR_GUIDE.md)。

#### G3：AI 行为质量

- 稳定：所有 Bot 能从已知卡住状态恢复；不存在持续阻断玩家或比赛目标的行为。
- 战术：T 能分路、携带/回收 C4、安装和处理经济局；CT 能分点、回防和拆除；保枪与投掷行为可在比赛记录中观察。
- 玩家协作：同队 AI 能共享合法侦测/受击信息，并执行不与玩家目标冲突的基础分工；不得把“独立巡逻”冒充队伍协作。
- 拟人：反应、瞄准、火力分级和失误保持可读，不要求本阶段实现完整人类战术树。

#### G4：地图与训练

- Gatehouse 每项局部改动都通过碰撞代理、路线通行、接触时序和守方轮转回归；不得静默改变三路双爆点结构。
- 独立训练入口支持无限弹药、投掷物补充/重置、玩家/目标重置，以及命中率、爆头、压枪散布、投掷距离和飞行时间反馈。
- 训练状态不得污染正式比赛的金钱、装备、比分或遥测。

#### G5：作品集表现

- 替换第一人称武器灰盒；保留现有低模第三人称角色，但完成 Gatehouse 的材质、灯光、HUD、特效和动画一致性检查。
- 生成至少一段可独立理解的 1080p、30 FPS 或更高演示，包含购买、AI 协作、交火、安装/拆除、换边和比赛结算。
- 相关 Vulkan 截图需人工检查敌我识别、关键路线可读性、准星/HUD 清晰度、烟雾边缘和第一人称武器遮挡。
- 静态资产与 Vulkan 性能预算不得新增硬失败；允许的已知债务必须继续保持路径限定并记录。

## 后续候选（本阶段不启动）

1. 外部玩家试玩与 Gatehouse 平衡复测。
2. 将成熟 3v3 系统迁移到 Foundry Reforged 或 Core Vault。
3. 重新设计 Dustline 的地面拓扑、爆点和交火距离，使其从复刻研究图转为原创地图。
4. 联网权威与多人同步。
5. 公开发布前确定仓库级许可证并复核代码、原创资产与第三方资产的发布清单。

审阅修正：PR #35 在 `528999d` 报出两个 P2，均已修复：C4Device 记录唯一实体 owner ID，玩家 5 键、E/左键安装、丢弃、死亡和 HUD 都检查本地真实归属；AI 拾取后设置其 owner ID，回收者死亡只掉落该实体。AI 目标交互提示按安装 T / 拆除 CT 与玩家阵营区分队友和敌方。新增两项真实场景回归覆盖 Bot 实际拾取、玩家不能复制/丢弃 Bot C4、回收者死亡及敌我提示四组合。旧脚本回归直接改玩家阵营，却未转移 C4，已补齐 fixture 归属；没有放宽生产持有限制。最终精确头与 CI 见交付 JSON，不沿用旧头绿色结果。
