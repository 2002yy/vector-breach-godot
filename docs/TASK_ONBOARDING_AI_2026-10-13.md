# 2026-10-13 游戏入口、操作、地图与 AI 修复

## TASK

用户明确授权：记录游戏位置，改造手枪开局的说明与操作提示，清理地图呈现、查询历史和中文化，调查并修复 AI 队友表现问题。后续用户补充：区分测试和游玩地图，让经典 CS 复刻研究图可玩。
本次授权允许处理此前 G2 前冻结的具体 AI 缺陷；不扩大到新战术树或调整枪械伤害，不把局部验证记成 G2 / G3 整体通过。

## 起点与范围

- 仓库：`D:\AgentGamePipeline\repos\VectorBreach-godot`。
- 起点：`main` / `99f0506`，工作树干净。
- 工作分支：`fix/onboarding-maps-ai-20261013`；用户后续明确授权本次修复提交并推送。基线 HEAD `99f05064ef6db592217a4cc898b2642ab6162a1f`。
- CHANGES / FILES：`scripts/Main.gd`、`scripts/ui/{StartMenu,CombatHud,PlayerGuide}.gd`、`scenes/ui/{StartMenu,CombatHud}.tscn`、`scripts/autoload/GameState.gd`、`scripts/ai/TacticalBotBrain.gd`、`scripts/combat/CombatSandbox.gd`、相关 Bot / Main / Weapon / Gatehouse 测试及 UI 视觉探针、新增 `LocalResearchPlaytestProbe` 脚本与场景、README、中文指南与状态文档。
- 额外入口说明：桌面 `3Dgame\游戏在哪里.md`；不属于 Git 仓库。

## Feature / Asset Impact Audit

| 项目 | Impact 或 N/A + 原因 |
|---|---|
| gameplay | 实际 AI 武器与显示装备一致；可见目标选择修复；练习 / 经典图开局真实拥有两把枪 |
| economy | 三人队伍资金统计；AI 真实付费买步枪，优先于装备 |
| AI | 敌我共用武器 / 购买 / 视线修复；未改伤害、时延或地图图结构 |
| level | 仅菜单分组与说明；碰撞、路线与地图文件不改 |
| UI | 比赛 / 练习 / 经典研究入口区分、历史开关、常驻提示与 F1 帮助 |
| tutorial | 手枪局、步枪价格、购买限制及爆破操作说明 |
| input | F1 帮助；现有输入与购买数字键保持 |
| accessibility | 中文说明与按键提示；没有新增完整无障碍功能 |
| save | 武器沿用既有回合保存；不改设置或记录格式 |
| network | N/A：单机，无网络变更 |
| animation | N/A：没有修改动画资产 |
| VFX | N/A：没有修改特效 |
| audio | N/A：没有修改音频 |
| art | N/A：没有修改 canonical source 或 runtime 美术资产 |
| performance | 目标选择多做候选视线检查；人数仍固定，需视觉运行验证 |
| localization | 主菜单、计分板武器、阵营与购买项中文化；稳定 ID 保留 |
| analytics | N/A：沿用比赛记录，无新遥测格式 |
| tests | 补实际武器、购买 / 不超支 / 幂等、视线选择、三人资金与 F1 回归 |
| build | 新 GDScript 与 UI 引用由 Godot import 验证；无需重建 GLB |
| release | 本机源码入口交付；无远程发布 |
| legal | 沙线第三方参考保持本机与公开排除规则 |

## TESTS / RESULTS / EVIDENCE / REGRESSION

最终候选验证完成（证据均在 `D:\AgentGamePipeline\evidence`）：

- **原生全套 PASS：11 套 / 138 项，`RUN_ALL_OK`。** 日志 `onboarding-ai-20261013-full-native-sealed.log`；包含真实门厅区双方开局、半场 / 加时武器重置、购买 / 不超支 / 幂等、遮挡目标选择、三人资金、过滤菜单与 F1。
- **GdUnit4 PASS：2 / 2，0 errors / failures。** `onboarding-ai-20261013-gdunit.log`。
- **Godot import / 解析与类型检查 PASS。** 最终聚合导入和两种 Vulkan 探针均未报 Script / Parse 错误。
- **美术只读策略 PASS：** Asset Layer、Metadata、Runtime Contract、Runtime Validation；6 / 6 master sidecar，7 / 7 GLB。没有 source / runtime 美术资产改动，因此不执行无关 Blender 重建。
- **Lint 增量检查：无新增功能诊断。** `onboarding-ai-20261013-lint-{baseline,candidate}.log` 都只剩原有 `enemy_team` unused argument；为避免无关大规模重排，任务专用配置排除已有的行长、文件行数、方法 / 返回数和声明顺序规则。原始严格 gdlint 仍有风格债务，不能称整仓严格 lint 全绿。
- **Formatter PASS：** 新增 `PlayerGuide.gd`、`LocalResearchPlaytestProbe.gd` 经 `gdformat --check`；已有文件仅局部编辑，不批量重排。
- **Vulkan UI：RTX 5060 Laptop / Forward+ / 1600×900。** 主菜单、默认四个游玩入口、练习菜单、历史列表、真实手枪开局、F1、购买、计分板、战斗提示与结算截图已检查；本次新增文字可读、按钮在画面内。证据 `onboarding-ai-20261013-ui-vulkan-delivery.log` 与 `onboarding-ai-20261013-verified\` 截图归档。全套后最后修改仅为经典图说明文字排版与视觉探针取景，没有再次改动玩法。
- **经典 CS 两版本功能 PASS：** `onboarding-ai-20261013-classic-playtest-sealed.log`；均落地、移动约 2.26 m、真实持有步枪 / 手枪、切枪、靶子掉血，步枪一发消耗 `30 → 29`。探针明确标记 `controlled_practice_not_bomb_match`，没有冒充完整爆破或自然比赛。
- **经典原始材质视觉 NO-GO：** 植物 / 遮阳篷有明显材质异常；当前原始材质版只作为可玩本机研究入口，不宣称视觉完工。
- **Git：** 无提交 / 推送 / PR / CI；HEAD 仍为 `99f0506`，当前工作树是本次有意保留的改动。`git diff --check` 通过，源地图和美术文件没有改动。

有意义的失败与修复：

1. 新购买回归发现 `weapon=pistol` 未传递到 `aiPrimaryWeapon`，内部仍初始化免费步枪；修复真实武器初始化。
2. 全套测试的旧 HUD 断言仍要求 `CT / T` 英文，更新为中文阵营后通过。
3. 首版菜单截图暴露高度溢出和不相关的庭院缩略图；缩小布局并取消误导性占位预览。
4. 经典图实机探针发现所有地图都调用竞技装备配置，步枪实际未拥有；改为仅门厅区采用竞技手枪局，两种经典图随后通过真实枪械验证。

## KNOWN ISSUES / NEXT / GATE

**GATE：本机操作 / 规则 / AI 缺陷、入口减负与材质故障修复 GO；最终平衡、经典图完整 5 对 5 仍未实现。**

G2 十场人工连续比赛、G3 完整战术与最终平衡仍未关闭。经典图现有配置是练习靶，缺少正式阵营出生、爆点与可通行 AI 路线；“可玩练习”不等于“完整爆破”。用户询问 CS 人数及 5 对 5 范围；指南记录十人单机爆破建议，尚未把问题当成完整十人扩容的验收。

邻接问题保留：AI 拾枪升级分支在赋值 owned 后检查同一武器未拥有，条件不可达；另开真实拾枪 / 切换回归，不混入本次已验证修复。

下一执行片：建立经典地图 5 对 5 爆破的出生 / 爆点 / AI 路线合同与自然比赛验收；当前门厅区仍保持 3 对 3。

## 后续授权：材质修复、地图分组、开局 UI、提交推送

用户明确要求修复部分贴图异常、解释冻结历史版并区分游戏 / 测试，以及提交推送和减少开局左侧密度。

- 新增 scope：`scripts/level/GrayboxLevel.gd` 与 `scripts/tests/GrayboxLevelTestRunner.gd`；总计 24 个任务文件。没有修改任何地图 JSON / GLB / 第三方贴图。美术影响为局部运行时视觉材质覆盖，不需要重建源模型。
- 根因证据：原始 GLB 的 `csgo_foliage.vfx` / 布篷使用 `COLOR_0` 存放动画属性，Godot 导入材质启用了 `vertex_color_use_as_albedo`。仅沙线原始材质入口、已确认受影响材料名，复制材质后关闭这个开关；保持贴图、透明阈值和原资源。新增回归检查共享资源不变、透明裁切不变及非目标材质不变。
- 普通游戏组与三张开发回归图互斥；开关切换会同步当前地图，代码选图也同步开关。三个开发图仍有有效测试依赖，没有“无用地图”可安全删除。
- UI：移除重复缩略图和长路线段落，设置另面板按需打开；匹配组才显示阵营，隐藏人工验收序号。经典图 HUD 使用练习标签，避免虚假安装提示。
- 新验证证据：`D:\AgentGamePipeline\evidence\onboarding-ui-material-{native-final,classic,ui,import}.log`。材质实机截图中植物、布篷恢复自然颜色；只对已观察缺陷作 PASS，不宣称全图材质穷尽验收。最终自动回归结果与提交记录由交付节补充。
- 旧节中的 138 项、原始材质 NO-GO、未推送是第一轮快照；以上后续授权和新证据取代这些结论。第三方本机参考资产继续保持 Git 排除。

### 本次交付验证

- 原生全套：11 套 / **139 项 PASS，RUN_ALL_OK**，包括真实装备 / 经济 / 视线、菜单组隔离与设置面板、材质共享资源和透明裁切回归。
- GdUnit4：2 / 2 PASS；新增材质代码 / 测试 lint PASS；原有其他改动的增量 lint 仍只有基线 `enemy_team` unused argument，无新增诊断。新增文件 formatter 检查通过。
- 两种经典图 Vulkan 受控操作 PASS；开局 / 游戏列表 / 开发列表 / 设置面板与原始材质修复截图已人工检查。渲染设备 RTX 5060 Laptop，1600 × 900。
- 最终证据目录：`D:\AgentGamePipeline\evidence\onboarding-ui-material-verified`，包含日志、截图和带 SHA-256 的范围 / HEAD 清单。`git diff --check` 通过；24 个文件均属于本次任务，第三方 local-only 资产没有加入提交。
- 发布方式：提交 `fix/onboarding-maps-ai-20261013` 并推送同名 origin 分支；未合入 main。仓库 push CI 只监听 main，该修复分支推送不会自动触发；远端 SHA 与当前头的 CI 查询结果写入证据清单，不把本地 PASS 当成远端 CI PASS。
