# Vector Breach 当前状态

更新：2026-10-24。此文件为当前实现、优先级和交付状态的权威入口；旧任务文档及历史截图中的“当前版本/尚未实现”只对应当时提交。

## 当前批：碰撞文件后台校验与 Jolt 定位

基线已提交 `5ef3d32d72b07df05496dea107aea05788effc44`（#84；Tests `40092648783`、Windows 导出/冒烟 `40092648780` 全成功），分支 `feature/background-collision-verification`。分段探针确认大网格耗时在 Jolt 接入形状，树外组装仅转移耗时，未作为优化发布。本片把独立文件哈希移到后台工作池；每次加载重新校验原源、导入、缓存字节身份，主线程消费前复核文件状态及缓存/导入哈希，节点/变换/形状仍按原规则验证。未改变物理线程设置、几何或资源。取消结果丢弃，任务由会话拥有者完成回收。详见 [本批记录](TASK_BACKGROUND_COLLISION_VERIFICATION_2026-10-24.md)，最终验证/提交/PR/CI 见本机 `collision-backend-preparation-20261024/delivery.json`。试玩包未覆盖，Jolt 单网格约两秒的阻塞仍单列。

最终本机验证：原生 **216**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；真实三图 **123 形状、3,265,932 三角面、11,725 射线、1,467 胶囊** 一致，普通/候选 **6 次 Vulkan、126 PNG** 通过。Inferno 文件校验后台约 699 ms、等待最大主循环间隔约 11.5 ms；主线程缓存消费约 244 ms、单网格约 1.5 秒仍未解决。四个脏导入及用户设置逐字节保持。

## 前批：专用碰撞层分帧注册

基于已提交 `767f7d32a8e9e52f76a2dff5fd23341bd8b67051`（#83；Tests `40081728126`、Windows 导出/冒烟 `40081728141` 全成功），分支 `feature/staged-collision-registration`。仅异步开局的专用碰撞层按原网格逐个注册、让出主循环帧，缓存验证和形状不改；同步 API 与视觉层自建碰撞路径保持同步。缓存校验/读取与单个大网格仍可能阻塞，不宣称总加载或最长帧达标。主视觉后台读取须等专用碰撞全部完成，过期代次/销毁停止旧注册。工作与验证见 [本批记录](TASK_STAGED_COLLISION_REGISTRATION_2026-10-24.md)，最终提交、PR/CI 见本机 `staged-collision-registration-20261024/delivery.json`。现有试玩包未覆盖。

本机最终验证：原生 **215**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；真实三图 **123 形状、3,265,932 三角面、11,725 射线、1,467 胶囊** 对照一致，双入口 **6 次 Vulkan、126 PNG** 通过。注册窗口最大采样间隔约 Dust II 306 ms、Mirage 80 ms、Inferno 1,918 ms；大网格和校验仍阻塞，整体加载/FPS 未验收。

## 前批：地图视觉资源后台读取

基线已提交 `1c7be484198c8dd24706f9d64387064cdc658ce7`（#82；Tests `40077149926`、Windows 导出/冒烟 `40077149929` 全成功），分支 `feature/threaded-map-visual-read`。仅点击开始后，先执行原碰撞构建/释放网格，再后台读取主视觉场景；实例化、材质和覆盖层仍在主线程。串行服务合并同路径请求、排空已销毁调用者的请求，过期代次不能覆盖新地图；同步 load_level API 保留。等待期间 Warmup、game_started=false。三图读取期最大主循环采样间隔约 16–69 ms，不覆盖其他阻塞阶段。详见 [本批记录](TASK_THREADED_MAP_VISUAL_READ_2026-10-24.md)；最终验证、提交、PR/CI 见本机 `threaded-map-visual-read-20261024/delivery.json`。试玩包未覆盖，整体最长帧与 70% FPS 未验收。

本机最终验证：完整原生 **214**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；三图普通/候选 **6 次 Vulkan、126 PNG** 通过，失败收尾修复未改变成功路径，复用其画面检查。原生失败令牌释放/同路径重试聚焦通过，四个既有脏导入与用户设置逐字节保持。

## 前批：外观场景存活期

基于已提交 `75dda9d3cf3f5b47d9f1761d2e8346b7248d97ab`（#81；Tests `40074824735` 和手动完整 Windows 导出/冒烟 `40074878721` 已成功；普通 PR Windows 曾跳过，不算该项通过证据），分支 `feature/appearance-scene-lifetime`。实测六角色专用材质暖处理约 1 ms，资源读取才是主要部分，未按最初假设修改 shader。角色/第一人称手臂与原版装备实例持有自己的源 PackedScene，旧阵容源资源仅临时保留到新阵容就绪，最后持有者销毁后释放，无应用级常驻缓存。最终原生 213、Python 80、GdUnit 2/2、格式/无新增 lint/资源合同和三图双入口 6 次 Vulkan（126 PNG）通过，独立工厂后续 16/16 次缓存命中及参数隔离通过。工作范围、回归/交付头与 CI 首次快照见 [本批记录](TASK_APPEARANCE_SCENE_LIFETIME_2026-10-24.md) 和本机 `appearance-scene-lifetime-20261024/delivery.json`。试玩包仍为 main `598cde1` 的已验收版本；本片未覆盖。冷读、上传及整体加载/帧率仍待验。

## 前批：角色路网准备复用

基于已提交 `eca9a6d7ed5f027e10cadf413e0c464af31effc7`（#80，当前 Tests `40073238664`、Windows `40073238667` 已成功；本批不等待远端审查或 CI），分支 `feature/actor-navigation-preparation`。每次阵容准备只解析/归一化一次路网，拓扑逐层只读，AI 分别拥有 AStar、封路与动态危险状态。无跨地图静态缓存，不共用可变寻路实例。此前单角色测量中，外观安装暖态约 125–141 ms，其余配置约 54–60 ms，本片先消除重复路网解析。完整原生 212、Python 80、GdUnit 2/2、格式/无新增 lint/资源合同、三图双入口 6 次 Vulkan（126 PNG）已通过。验证、提交、PR/CI 及限制见本机 `actor-navigation-preparation-20261024/delivery.json` 与 [本批记录](TASK_ACTOR_NAVIGATION_PREPARATION_2026-10-24.md)。试玩包仍为 main `598cde1` 的已验收版本。

## 前批：开局角色分帧生成

基线 main `598cde156cf9de6a99e88045d5f71849e06f906c`（#79 已合并，main push Tests `40071323710` 已成功）。分支 `feature/staged-opening-actors`。开始后按角色让出帧，完整阵容前停用 AI/动画；轮次重置和训练补员保留同步行为。增加生成工作量、单角色最大工作时间与让帧数，旧加载被替换后拒绝继续发布。完整原生 211、Python 80、GdUnit 2/2、三图普通/候选六次 Vulkan（126 PNG）及格式/无新增 lint/资源合同通过。验证、交付头及 CI 首次快照见本机 `staged-opening-actors-20261024/delivery.json`，详见 [本批记录](TASK_STAGED_OPENING_ACTORS_2026-10-24.md)。地图资源/碰撞/材质同步阶段、单角色实例化以及候选包上传仍会阻塞；未宣称最长帧或总加载时间达标。

唯一已验收试玩版为 `D:/VectorBreach/releases/VectorBreach-playtest-20261024/`，源码组合等同 main `598cde1`；普通入口和显式角色环境入口均已发布，完整原生 211、实包三图双入口与实际 EXE 已通过。四个原有脏导入保留。当前批尚未更新该包。下面整合阶段记载为历史过程，最终发布结果见 `playable-cleanup-20261024/delivery.json`。

## main、PR 与唯一试玩包

- **本片整理仓库并整合新试玩版**：基线 main `bbfd904fd26636106acc1de4c43c7d7fab69eb70`，整合 #75 / #77 / #78 的已提交头，分支 `integrate/playable-cleanup-20261024`。最终 PR/main 头、实际发布状态及验证见本机 `D:/AgentGamePipeline/evidence/playable-cleanup-20261024/delivery.json` / `audit.json`，详见 [发布说明](RELEASE_PLAYTEST_2026-10-24.md)。不在候选阶段预写已合并。
- 新目标包 `D:/VectorBreach/releases/VectorBreach-playtest-20261024/`：普通 Main 与独立 `角色环境候选.cmd` 双入口；前者保持正常对局，后者按图接全身和玩家/观战手臂环境。源码组合、实包与实际 EXE 验证后才更新桌面入口；旧 #63 包保留到新包通过。包的完整目录、候选输入与缓存须一起保留，正式画质/70% FPS 未验收。
- 整合修正旧阵容 `detach_ms`/延迟释放标注，并把加载开始回调与 JSON 读取分开；另修 PCK 导入重映射导致的缓存身份不符，使用旁置原字节校验。三图实包缓存命中和三角面/射线/胶囊一致性以本片最终收据为准，首轮失败证据保留。
- 36 个确认已合入旧主线的本地分支已保留恢复引用后整理，未合并/有独有提交/被工作树占用的分支保留，远端未批量删除；原资产、原证据、`.godot` 与四个原有脏 `.import` 不清理。生成报告仅在归档后移除，实际清理和入口更新记录在交付目录。
- 后续顺序：场景/角色加载和最长帧/内存 → C4/观战 → AI 运动/难度 → 图形地图补全 → 最新头 18 场、连续人工三图与 70% FPS。光追保持最后独立评估。以下各批历史状态仅描述当时提交。

- **本批续修 #75**：玩家与动态观战第一人称手臂加入环境候选，换外观/销毁先解绑；补查普通 PBR 袖子遗漏，增加限定原角色手臂的适配和参数保留；同时开启受控子视口 3D 音频监听以修复代码审查项。默认 Main、#63 试玩包未启用候选；见 [手臂任务](TASK_FIRST_PERSON_ENVIRONMENT_2026-10-24.md)，最终本机验证与当前头/CI 首次快照在 `D:/AgentGamePipeline/evidence/first-person-environment-20261023/audit.json` / `delivery.json`。
- 本片三图六套手臂开关/恢复及玩家/观战生命周期实际候选流程通过，共 **84 PNG**；按原 GLB 核对每套全部 **4–6 个原表面**接入（无独立袖子的两套为四个），关闭恢复原覆盖和精确像素，FBI 蓝袖色调读回与原参数一致。此项只验接线、参数保留和回退；亮度/光泽及完整材质观感仍需同原引擎参考，不是正式画质/稳态帧率验收。
- 续修完整原生 **208**（不包含 #76 的新增懒加载用例）、Python 非 Blender **80**、GdUnit **2/2**、导入/资源合同/格式/lint 无新增错误通过，18 原模型 SHA256 不变。并行验证曾发生 Vulkan/图片内存分配失败，最终改为串行完整回归并保留失败日志；这不是内存性能已修的证据。
- 待接入与待修重新排序为：**手臂/入口收口 → 实际加载性能 → C4/观战 → AI 运动/难度/规则 → 图形与地图补全 → 最新头整场、连续试玩、70% FPS 及发布**；光追最后独立评估。眼球时序、远距后照明/雾/平均色、Source 2 per-view/切线等价、默认启用和旧包升级仍是独立缺口，见 [完整规划](DEVELOPMENT_ORDER_2026-10-24.md)。
- #76 独立片曾验证启动/选卡零关卡加载、开始一次与失败回退，暖开始约 9–24 秒；当时未组合 #75。合并与本批组合进展见本文顶部，旧证据在本机 `lobby-lazy-load-20261023/`，不能替代组合头。

- **#74 已合入 main `bfc7ba5dbe4e0739f2781a4a45faf05104f37cfe`**；精确头 `38cee770e413892bd0492246a88a829cb3a6996c` 的 Tests `39925209809`、Windows export/smoke `39925209839` 全成功、审查项已解决且 CLEAN。本片 `feat/controlled-game-viewport-20261023` 从已合并基线继续，不等 CI。
- #75 原批新增 `scenes/ControlledGame.tscn` 显式候选入口：实际 Main/菜单/HUD 置于受控子视口，手动单次转发输入和安全调整尺寸；按地图就绪代次加载私有包，角色外观替换/阵容重建时撤销与重绑。新增删除前材质覆盖清理和观战过期/跨视口目标保护。当时手臂环境未接线，续修见本文顶部。证据及执行入口见 [原批记录](TASK_CONTROLLED_GAME_VIEWPORT_2026-10-23.md)。原批验证和 PR/CI 首次快照在 `D:/AgentGamePipeline/evidence/controlled-game-viewport-20261023/audit.json` / `delivery.json`，不能替代续修头。
- 三图实际候选游戏流程通过，含子视口原生 1280×720 重建后的点击/转向及恢复、外观/阵容重绑、死亡观战和上传期间切图取消，共 **27 PNG**。完整原生 **208**、Python **80**、GdUnit **2/2**、静态导入/资源合同通过，18 原模型哈希不变；规范脚本格式/lint 通过，五个旧脚本无新增 lint 问题。不是人工比赛或稳态 FPS 验收。
- #74 续修：旧头 `03ab625343246d3ad172936f0466c22af9be4ccf` 的 Tests `39920566997`、Windows export/smoke `39920566998` 已成功，但发现跨视口角色绑定审查项，不能据此合并。本批已修 `attach_character` 的现场边界，三图双视口拒绝前后材质身份不变、像素差 **0**；原角色/回退全回归，共 **579 PNG**。完整原生 **208**、Python **80**、GdUnit **2/2**、格式/lint/静态导入/资源合同通过，18 原模型哈希不变。新头提交/CI 首次快照见本机 `character-viewport-boundary-20261023/delivery.json`，不等待新 CI。该头当时未接游戏入口，后续进展见本文顶部；见 [续修记录](TASK_CHARACTER_VIEWPORT_BOUNDARY_2026-10-23.md)。
- **#73 已合入 main `8f2dc7e8181a231df1f286bce8e68510a994ad7d`**；精确头 `4504306af964811b338364e99894c4f5805978c4` 的 Tests `39914919499`、Windows export/smoke `39914919468` 全成功且 CLEAN。main push Tests `39916850404` 也已成功。本片从已合并基线继续，不等待新 CI。
- 当前片 `feat/character-runtime-inputs-20261023` 将三图原反射/LPV/SH/BRDF/对齐收据收敛为可重定位私有输入包，新增场景级输入拥有者，整组成功后才发布；错误地图/哈希、旧上传取消、视觉根移出和退出均撤销候选、恢复原材质。该片未改 Main/Actor 和根视口，后续显式入口见本文顶部；见 [本片记录](TASK_CHARACTER_RUNTIME_INPUTS_2026-10-23.md)。三包约 **1.1 GB**，不算加载性能优化，试玩包未更新。
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

1. #65–#74 已恢复三图原反射/SH/BRDF、全身候选、绑定级关闭、Godot 法线帧、SSAO/子视口生命周期和完整输入包；本片接显式候选游戏入口、地图/角色重建及菜单/购买/观战输入，见 [本片记录](TASK_CONTROLLED_GAME_VIEWPORT_2026-10-23.md)。下一片处理选卡零整图加载及开始只加载最终地图一次，并测冷启动/加载分段；候选仍需第一人称手臂环境效果、相机/画质/最小化边界与正式启用验收。Source 2 原切线/蒙皮、对象遮挡与真实 per-view、眼球时序、原雾/平均色及性能继续保留。C4/观战视觉与 AI 运动/难度顺序不变。
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
