# Vector Breach 当前状态

更新：2026-10-24。此文件为当前实现、优先级和交付状态的权威入口；旧任务文档及历史截图中的“当前版本/尚未实现”只对应当时提交。

## main、PR 与唯一试玩包

- **当前 main 为 `bbfd904fd26636106acc1de4c43c7d7fab69eb70`（#76 已合并）**；#76 精确头 `c8ee16e` 的 Tests `39957199686`、Windows export/smoke `39957199665` 全成功，main push Tests `39994705993` 成功。默认 Main 已有启动/选卡零关卡加载，唯一试玩包仍为 #63。
- **本片从上述 main 独立开发加载分段**：拆出原场景读取/实例化、碰撞生成、各材质修复、静态批次及角色生成/导航/收尾。三图 Vulkan 流程 21 PNG；固定代码单次暖运行原场景读取约 2.34–6.36 秒，Inferno 碰撞生成约 **6.03 秒**、角色生成约 1.68 秒。见 [本片记录](TASK_MAP_LOAD_PHASES_2026-10-24.md)，本机验证及精确提交/PR/CI 首次快照在 `D:/AgentGamePipeline/evidence/map-load-phases-20261024/audit.json` / `delivery.json`。本片增加诊断数据，尚不宣称提速或 70% FPS 通过。
- **#75 仍是独立候选 PR**：已接玩家/观战手臂、普通袖子参数保留、3D 音频监听和 #76 懒加载生命周期，头 `eb5d70431958de3d615089db2d76e5b384ca521f`。本轮首次快照 OPEN/BLOCKED，Tests `39998848984`、Windows `39998849044` 仍运行中，只查一次不等待。本机组合完整原生 209 / Python 80 / GdUnit 2/2、三图 126 PNG 的证据在 `controlled-lazy-integration-20261024/`，不能替代新头 CI/审查或正式画质验收。本分支不包含该 PR 的候选入口生产代码。
- 四个原有脏 `.import` 保留；原模型/材质/地图/碰撞和试玩包不改。返回选图仍保留旧场景，冷启动、峰值内存/最长帧、私有环境包分段和稳态 FPS 待测。下一片优先验证离线碰撞缓存，然后场景/角色加载 → C4/观战 → AI 运动/难度 → 图形地图补全 → 最新头 18 场、连续人工三图、70% FPS 和发布；光追最后独立评估。

- #74 续修：旧头 `03ab625343246d3ad172936f0466c22af9be4ccf` 的 Tests `39920566997`、Windows export/smoke `39920566998` 已成功，但发现跨视口角色绑定审查项，不能据此合并。本批已修 `attach_character` 的现场边界，三图双视口拒绝前后材质身份不变、像素差 **0**；原角色/回退全回归，共 **579 PNG**。完整原生 **208**、Python **80**、GdUnit **2/2**、格式/lint/静态导入/资源合同通过，18 原模型哈希不变。新头提交/CI 首次快照见本机 `character-viewport-boundary-20261023/delivery.json`，不等待新 CI。正式入口接线仍待下一片；见 [续修记录](TASK_CHARACTER_VIEWPORT_BOUNDARY_2026-10-23.md)。
- **#73 已合入 main `8f2dc7e8181a231df1f286bce8e68510a994ad7d`**；精确头 `4504306af964811b338364e99894c4f5805978c4` 的 Tests `39914919499`、Windows export/smoke `39914919468` 全成功且 CLEAN。main push Tests `39916850404` 也已成功。本片从已合并基线继续，不等待新 CI。
- 当前片 `feat/character-runtime-inputs-20261023` 将三图原反射/LPV/SH/BRDF/对齐收据收敛为可重定位私有输入包，新增场景级输入拥有者，整组成功后才发布；错误地图/哈希、旧上传取消、视觉根移出和退出均撤销候选、恢复原材质。正常 Main/Actor 和根视口尚未接线，见 [本片记录](TASK_CHARACTER_RUNTIME_INPUTS_2026-10-23.md)。三包约 **1.1 GB**，不算加载性能优化，试玩包未更新。
- 本片整包路径三图 **72** 组角色对照、**18** 组墙体遮挡、**24** 组 hair/眼球跟随及原数值回归通过；错误哈希/地图和拥有者退出后的画面严格像素差 **0**。共 **573 PNG**。完整原生 **208**、Python 非 Blender **80**、GdUnit **2/2**、格式/lint/导入/三类资源合同通过，18 原模型哈希不变。收据：本机 `D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/audit.json` / `delivery.json`。

- **#72 已合入 main `dab100fac67610f30e8551c8ff9862db131f3592`**；精确头 `98f61fba635fab5b8fb3c74bcb2efed7e0d4366d` 的 Tests `39831294276`、Windows export/smoke `39831294129` 全成功且 CLEAN。本片从这个已合并基线继续，不等待新 CI。
- #73 增加子视口拥有者：自动同步环境开关、真实窗口缩放提交安全重建事务、尺寸合并/取消、分辨率/MSAA 重建、退出卸载和过时代次拒绝；冷启动/重建首帧为中性回退，后续恢复当前 SSAO。根 Window 视口明确拒绝；正常游戏入口和试玩包未改，见 [前片记录](TASK_CHARACTER_SSAO_LIFECYCLE_2026-10-23.md)。
- #73 实际子视口三图 **72** 组角色 SSAO 对照、**18** 组墙体遮挡、**24** 组 hair/眼球跟随及原数值回归通过，关闭/卸载严格像素差 **0**；生命周期 **69 PNG**、能量隔离 **31 PNG**、三图 **558 PNG**，共 **658 PNG**。完整原生 **208**、Python 非 Blender **75**、GdUnit **2/2**、格式/lint/导入/三类资源合同通过，18 原模型哈希不变。收据：本机 `D:/AgentGamePipeline/evidence/character-ssao-lifecycle-20261023/audit.json` / `delivery.json`。不能替代正常对局、根视口或 70% FPS 验收。

- **#71 已合入 main `d21ba4240d8ff5a4e85ca1cbfe97284a2b56ab6a`**；精确头 `12c989b1617c6106aaed83d304bdaf29d6f9c0bb` 的 Tests `39826106691`、Windows export/smoke `39826106732` 全成功且 CLEAN。本批开发未等待 CI，结果就绪后整合已合并基线。
- #72 接实际 Godot SSAO 纹理，只衰减候选间接漫反射/镜面反射，不重复材质 AO，也不修改直接光或原自发光。当时仅有显式暂停/重建流程；后续拥有者见本文顶部，原引擎遮蔽/per-view 和正式集成仍待完成，见 [前片记录](TASK_CHARACTER_SSAO_2026-10-23.md)。普通游戏和唯一试玩包未启用候选。
- #72 整合 #71 后三图 **72** 组角色 SSAO 对照、**18** 组墙体遮挡、**24** 组 hair/眼球跟随及原数值回归通过；关闭/卸载均严格像素差 **0**。隔离直接光/原自发光保持零差，移动第一帧与暂停重建/销毁通过；共 **589 PNG**。完整原生 **208**、Python 非 Blender **75**、GdUnit **2/2**、格式/lint/导入/三类资源合同通过，18 原模型哈希不变。收据：本机 `D:/AgentGamePipeline/evidence/character-ssao-20261023/audit.json` / `delivery.json`；Dust II 基线天空紫黑外露物件单列待查。

- **#70 已合入 main `76337b0c291463ac4b7049f14ea807eb02c93b3e`**；精确头 `cd6f82b6b2905080c1c5969cd211bedca4015691` 的 Tests `39774191397`、Windows export/smoke `39774191440` 全成功。main push Tests `39822146971` 首次快照运行中，本片不等待。
- #71 修复候选的未归一化 TBN 与 normal strength 向量混合；独立 **216** 组数值和六角色 **48** 组实际动作/强度/尺度对照通过，新重建与引擎光照阶段法线全部像素误差为 **0**。当时 SSAO 仅复现缺口，后续实际合成见本文顶部，见 [前片记录](TASK_CHARACTER_NORMAL_FRAME_2026-10-23.md)。普通游戏与试玩包未启用候选。
- #71 完整原生 **208**、Python 非 Blender **75**、GdUnit **2/2**、格式/lint/导入/资源合同通过，18 原模型哈希不变；三图 72 组关闭/卸载仍全部严格零，24 组 hair/眼球跟随、18 组墙体遮挡及原采样/布料数值回归通过。共 **635 PNG**，收据见本机 `D:/AgentGamePipeline/evidence/character-normal-frame-20261023/audit.json` / `delivery.json`。该证据中的 SSAO 仅为边界复现，不替代本片合成证据。

- **#69 已合入 main `5be8fc4b08f808ad8ae25f894d48edb6887e721c`**；精确头 `311442ae6a37b1643a09cdce974502fe899a0fc0` 的 Tests `39742846832`、Windows export/smoke `39742846581` 全成功。main push Tests `39771031078` 首次快照运行中，当前独立片不等待。
- #70 将关闭操作改为恢复原材质绑定，新增材质副本/原 shader/零输出消融，三图关闭要求收紧为严格零，见 [前片记录](TASK_CHARACTER_ENVIRONMENT_TOGGLE_2026-10-22.md)。
- #70 三图 **72/72** 组关闭与卸载均为像素误差 **0**，18 组墙体遮挡及旧数值/hair 回归通过；**486** 张三图截图、**12** 张消融截图。完整原生 **208**、Python 非 Blender **71**、GdUnit **2/2**、格式/lint/资源合同通过，18 原模型哈希不变，详见本机 `D:/AgentGamePipeline/evidence/character-environment-toggle-20261022/audit.json` / `delivery.json`。绑定级关闭已修，原 shader uniform 置零仍只是保留副本的诊断方式。

- **#68 已合入 main `3bba8518f8a5cceb743838fd2f164f204569d88b`**；精确头 `d38b6782ba1f2ad6e910499f0f62814044cead46` 的 Tests `39737778623`、Windows export/smoke `39737778775` 全成功。main push Tests `39739136299` 首次快照运行中；新片独立开发，不等待 CI。
- #69 将 LPV 的四次重复选取收敛为一次六向读取，并扩展六角色皮肤/布料受控候选，加入原布料间接能量与部分遮罩方向规则，见 [前片记录](TASK_CHARACTER_PROBE_CUBE_2026-10-22.md)。
- #69 三图 **14986** 组新旧采样对照、**243** 组布料/金属/AO/方向数值在三图分别通过；**72** 组全身候选、**24** 组 hair 回归、**18** 组墙体遮挡、**486 PNG**。完整原生 **208**、Python 非 Blender **71**、GdUnit **2/2**、格式/lint/资源合同通过，18 原模型哈希不变。其关闭残差的后续处理见本文顶部；详见本机 `D:/AgentGamePipeline/evidence/character-probe-cube-20261022/audit.json` / `delivery.json`。

- **#67 已合入 main `bd480eac0304878e3c78a3d59af82bfd1da1d13a`**；精确 PR 头 `09617cd9af5069fd36549028919defca4e1f1e34` 的 Tests `39651349173`、Windows export/smoke `39651349226` 全成功。main push Tests `39733653675` 首次快照运行中，本片不等待 CI。
- #68 核实原动态探针组合，接入六轴 SH 回退、RGB 软法线和 hair 间接能量分配；三图新增 **210** 组数值与隔离阶段检查、**24** 个角色组合、**156 PNG**，见 [前片记录](TASK_CHARACTER_INDIRECT_ENERGY_2026-10-22.md)。SH 仍是由原光实体推导的查看器候选，未冒充原引擎 per-view 绑定。
- #68 完整原生 **208**、Python 非 Blender **66**、GdUnit **2/2**、格式/lint/资源规则通过，18 原模型哈希不变；24 张关闭新模式的图与 #67 逐像素相同。错误类型溯源字段的校验异常已修复并回归，收据见本机 `D:/AgentGamePipeline/evidence/character-indirect-energy-20261022/audit.json` / `delivery.json`。

- **#66 已合入 main `5ea8c034a48f097dff54aaf4be2a789279680ed5`**；精确 PR 头 `cee5323` 的 Tests `39644309614`、Windows export/smoke `39644309674` 全成功。该 main push Tests `39645959880` 首次查询运行中；此为历史快照，当前基线见上方。
- #67 恢复三图 **217 组原 radiance SH** 和原 **64×64×3 BRDF 表**，将归一化/BRDF/发丝环境第二瓣接到两种原 hair 材质的受控角色候选；三图 **868** 组数值与 **24** 组角色近远景/姿势对照，关闭候选误差为零，见 [前片记录](TASK_CHARACTER_REFLECTION_NORMALIZATION_2026-10-22.md)。普通角色材质、正式对局和试玩包尚未启用；后续间接能量进展见本文顶部。
- #67 本机完整原生 **208**、Python 非 Blender **62**、GdUnit **2/2**、格式/lint/资源规则通过；三图 **102 PNG**，18 原模型哈希不变。精确提交/PR/CI 与保留的四个导入状态见本机 `D:/AgentGamePipeline/evidence/character-reflection-normalization-20261022/delivery.json`。

- **#65 已合入 main `a00f81958a9a640083a5762a00f61efc07880e37`**；精确 PR 头 `69fc7e3` 的 Tests `39601697845`、Windows export/smoke `39601697868` 全成功。合并后 main push Tests `39641681474` 首次查询仍运行；此为当时快照，后续 #66 状态见上方。
- #66 完成三图原反射数组的游戏空间选择/盒投影/重叠混合，**2140 条** CPU/GPU 签名检查（含 480 条重叠）、分数 mip 对照与三图移动反射表面截图通过，见 [运行时记录](TASK_CHARACTER_REFLECTION_RUNTIME_2026-10-22.md)。该片仍为显式诊断，后续角色绑定见本文顶部。
- #66 本机完整原生 **208**、Python 非 Blender **57**、GdUnit **2/2**、格式/lint/资源规则通过；18 原模型哈希不变。其交付收据在本机 `D:/AgentGamePipeline/evidence/character-reflection-runtime-20261022/delivery.json`。

- **#64 已合入 main `290da7628575dc6e2ed679d44dd3f4148d6d7b30`**；眼球远距修正精确 PR 头 `d7f460d` 的 Tests `39595482197`、Windows export/smoke `39595482274` 成功，审查的分支内导数问题已修复。后续片段均独立验证，未沿用这些结果代替新头 CI。

- **#63 已合入 main `7ce895b8253a3dd61948b60527eb6c149629e661`**，包含 #57–#62 全部头；#57–#59 标记已合并，#60–#62 已关闭且保留分支。PR 精确头 `a85d7b5` 的 Tests `39590862440` 与 Windows export/smoke `39590862424` 成功；该 main 精确头的 push Tests `39591520517` 也已成功，单独核验，不沿用 PR 结果冒充。详见 [主线整合记录](RELEASE_MAIN_PLAYABLE_2026-10-21.md) 及其交付收据。
- #55 精确头 `af80048b4f3b21fcc7134fdd064d6f786795377d` 的 Tests `39419830963`、Windows Export / smoke `39419830823` 成功；合并后 main 精确头 `4bd98c1` 的 push Tests **39421373322 成功**（含 Blender 重建与正式原生检查），不是用 PR 绿色结果冒充 main 结果。
- **已验证当前包**：`D:/VectorBreach/releases/VectorBreach-main-20261021/VectorBreach.exe`，导出头 `a85d7b5` 与 **#63 合并提交**的 Git tree 相同；不含后续 #64 眼球修正或本片反射输入。须整体保留目录；旧 `VectorBreach-character-special-20261020` 包保留回退。原探针合成仍只在独立诊断入口启用。
- 桌面 `C:/Users/Zhang/Desktop/3Dgame/启动当前游戏.cmd` 已指向新包；原入口/说明备份后缀 `.before-main-lighting-20261021-192756.bak`。用户设置在包验收后逐字节恢复。
- 按用户“保留最新版”清理了 12 份旧构建，共 39,315,066,527 字节（36.62 GiB）。源码、原版参考资源、测试截图/日志、旧构建的 JSON/TXT 元数据和工具保留；清理清单和收据在 `D:/AgentGamePipeline/evidence/release-consolidation-20261020/`。

## 已有实现与验证边界

| 范围 | 当前已有 | 不能据此声称 |
| --- | --- | --- |
| 三图材质 | 原版三图、贴花 Alpha/偏移、工具面隐藏、三种 Mod2x 与源混合/阴影规则；保留原纹理与 VMAT | 所有区域/资源/渲染规则均等价或逐图 70% FPS 已通过 |
| AI 与武器经济 | 补枪/协同/转点/残局策略、AWP/MP9/Nova/燃烧瓶、预算购买与掉枪拾枪 | 所有路径、炸弹任务、难度、整场平衡已通过 |
| 观战与界面 | 队友双视角/切人及状态、战术大厅、地图卡片、三标签帮助、可展开购买帮助与 FPS | 最新试玩指出的观战视觉与死亡等待问题已修复 |
| 战斗反馈 | 真实击杀/归因、独立队伍消息、默认关闭且按回合冻结的持久化友伤开关 | C4 全员提示/爆炸表现已完整实现 |
| 角色 | 布料/皮肤/各向异性直接光、逆反射、发丝直接光、三套眼球近景与骨骼跟随；18 原模型哈希不变，专用绑定 40/63 | Source 2 环境、软法线、蒙皮切线、发丝环境瓣、眼球远距过滤或距离对比度已完全复现 |

最新已交付头验证：完整原生 **207 项**、Python 非 Blender **48 项**、GdUnit **2/2**；独立 PCK 三图各 **141 条角色检查 / 432 姿势 / 213 PNG**，正常三图连续流程 **15 张**、EXE headless 与 Vulkan smoke。18 原模型哈希不变；半透明合成重复绘制已修。详细证据和哈希见主线整合收据。自动化与局部画面通过不能代替完整人工验收。

历史已完成 **18 场 / 191 回合**自动比赛（跨两个修复头）；不是“18 场从未做”，也不是最新 main 同头全验收。仍有 22 个 Mirage/Inferno 路线候选、AI 运动观感、死亡等待和经济/双方平衡待复验。见 [比赛记录](TASK_MATCH_AI_ECONOMY_SPECTATOR_UI_2026-10-19.md)。

## 当前开发与待修顺序

完整可执行清单见 [当前待修项](CURRENT_PENDING.md)。

1. #65–#73 已恢复三图原反射/SH/BRDF、全身受控候选、绑定级关闭、Godot 法线帧、SSAO 和子视口生命周期；本片追加完整输入包及场景拥有者，见 [本片记录](TASK_CHARACTER_RUNTIME_INPUTS_2026-10-23.md)。下一片准备正常游戏的显式候选启动入口，连接地图加载代次与角色外观重建，并验证菜单/购买/观战输入；不能直接修改原根视口套用旧事后信号。Source 2 原切线/蒙皮、对象遮挡与真实 per-view 仍单列。没有启用正式角色环境效果；眼球时序、原雾/平均色及性能继续保留，加载策略、C4/观战与 AI 运动/难度顺序不变。
2. 启动/选图加载策略与分段耗时；用户明确允许选卡只更新静态真实地图预览，不在后台加载比赛地图。
3. C4 成功提示/爆炸与结算、死亡观战视觉、AI 摇摆/速度与后续难度策略。C4 已有小型指挥完成消息，需改善醒目程度与观战覆盖，不是完全没有事件。
4. 真实底图雷达、天空/高抛投掷边界、闪光 AI/玩家一致性、共享烟雾/环境光/体积雾；光追保持独立研究项。
5. 三图逐区可玩验收、当前头 18 场回归、连续人工比赛及逐图 70% FPS；不得先宣称关闭。

## 前序片段历史证据（下列包/PR 状态仅对应当时）

以下保留开发记录，不作为当前 main、包或缺口状态；当前以本文顶部和 CURRENT_PENDING 为准。

远距对比度本片已完成原数值规则及后照明开发原型，Forward+ Vulkan 26 项解析数值与 9 项阶段检查通过。原型未附加到游戏材质，真实平均反照率/方向光照输入仍待接入，未更新唯一试玩包；详见 [本片任务](TASK_DISTANCE_CONTRAST_2026-10-20.md)。

续片已将 Mirage/Inferno 的原 LPV 数据接入受控运行时诊断：从实际视觉根节点取得 Source→游戏变换、验证地图身份/浮点图集哈希，逐片元选取并混合最多四个探针；73 原出生点的 **438** 组六向校验、**12** 组实际移动表面校验通过。两图六角色共 **120 张**原版背景下的基线/双向/移动截图已记录，诊断显示纯辐照度，不冒充最终角色着色。新增适配器边界测试已纳入 Windows/Linux 全套：本片原生 **207**、Python 非 Blender **31**、GdUnit **2/2** 通过。仍缺 Dust II 原包、SH1 缺省光照、雾/平均色绑定、最终角色合成与性能；实际对局未开启、试玩包未覆盖。详见 [运行时探针记录](TASK_MAP_PROBE_RUNTIME_2026-10-21.md)。

Dust II 本片已按旧 19.2 GLB 的 `(y,z,x)` 轴向及原资源哈希建立显式对齐合同，不改地图/碰撞。**180 组六向 HDR + 6 组移动表面、52 项角色合成**通过，保存 **110 PNG**；Mirage **204 项/60 PNG** 回归通过。原模型哈希不变。本片完整原生 **207**、Python 非 Blender **31**、GdUnit **2/2**、格式/lint、导入与 diff 检查通过。源雾实体与平均色又补充了原数据/开源查看器依据，但不将其算作原引擎属性绑定已证实。详见 [Dust II 运行时核验](TASK_DUST2_PROBE_RUNTIME_2026-10-21.md)。

## 工作树与固定约束

整合复核发现半透明源不在不透明屏幕纹理中，合成会重复淡出并混入背景。续修令 `transparency > 0` 时退出辅助合成，恢复不透明后再启用；动作 probe 增加 0.25/0.65/1.0 三档对照。历史 129 条/177 PNG 结果属于修复前头；新头及包内结果以交付收据为准。正式 release EXE 禁止场景覆盖，独立诊断明确要求本机 Godot 4.7.1 编辑器运行时加载 PCK，不声称 EXE 自带可切换诊断。

动作续片修复无形变网格不跟随透明度/层/裁剪与距离可见性，以及完全透明时的合成残留。新 probe 在真实地图背景、透视相机下检查六角色六类既有动作，每片段 12 个姿势、近远对照及三方淡出对照；不再仅用隔离背景静态 T pose。详细结果、失败修正、原输入证据边界和下一片见 [动作与淡出记录](TASK_CHARACTER_COMPOSITE_MOTION_2026-10-21.md)，本片未启用到正式对局，未更新试玩包。

本片三图各 **129 条检查 / 432 个姿势 / 177 PNG** 均通过；原生 **207**、Python **31**、GdUnit **2/2**、格式/lint、导入及 diff 检查通过。远距为真实地图下约 19.94–28.59m 透视对照，保持显式候选输入；不等价原引擎同灯光/多人遮挡/逐图 70% FPS 已通过。

角色续片 [#60](https://github.com/2002yy/vector-breach-godot/pull/60) 已将双向 LPV 接到照明后的原角色纹理合成，保留实时原材质、逐表面蒙皮与形变；两图各 **52 项 GPU 检查/50 PNG** 通过并查看六角色对照，18 原模型哈希不变。远景用隔离背景及正交相机验证，不能算实战远距/性能通过。平均色仍是候选，雾修改量仅显式诊断常量。Dust II 经当前匿名 manifest 成功恢复，与现用旧原包 SHA256 完全相同，43 探针/30 出生点照明输入已提取；世界坐标/GPU/角色合成仍待验收，无需手机或账号认证。本片未启用到实际对局，未覆盖试玩包；详见 [后照明合成记录](TASK_CHARACTER_PROBE_COMPOSITE_2026-10-21.md)。

本片完整原生 **207 项 / RUN_ALL_OK**、Python 非 Blender **31 项**、GdUnit **2/2**、GDScript 格式/lint、Godot 导入及 diff 检查通过。私有证据与提交/PR/CI 收据在 `D:/AgentGamePipeline/evidence/character-probe-composite-20261021/`，不把本机通过算作 CI/正式可玩验收。

#60 以 #59 分支为 base，当前 workflow 仅匹配 main，因此创建后单次查询无 CI run；待转为 main base 后须在当时精确头运行 CI/复审，当前未合并。

四个既有 `.import` 状态改动继续保留，不纳入功能提交：hand_equipment、c4_device、buy/pistol、buy/rifle。原版资源仅在本机忽略目录，不公开再分发。

`data/levels/*.json` 的碰撞拓扑、路网与语义体积保持权威；视觉/材质修复不得改变冻结碰撞、比赛规则、共享玩家移动规则或命中模型。原冻结赛制、完整比赛/资产验收定义继续有效，详见 [整理前状态与冻结契约](history/PROJECT_STATUS_BEFORE_CONSOLIDATION_2026-10-20.md)；该文件中的旧包/旧优先级描述是历史记录，不作为当前入口。

未承诺独立外部复审或人工美术签核已经完成。后续新实现须按自身精确提交重新验证，不沿用旧头绿色结果。
