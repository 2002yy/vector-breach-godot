# Vector Breach Project Status

Updated: 2026-08-31

本文档是仓库唯一的状态、边界与优先级来源。README 和各地图设计记录只保留入口说明或设计约束；如与本文冲突，以当前检出、自动测试和本文为准。

当前 Step 16 功能候选分支为 `feature/step16-c4-device`，以 `main@99f05064ef6db592217a4cc898b2642ab6162a1f` 为基线。当前 runtime/workflow 功能证据基线为 `69d2a3395d2cb7799f923868a1d07adb5fe34e96`：required `Tests #93`（`33326528374`）、legacy `Godot Tests #122`（`33326528372`）与 `Windows Export #14`（`33326528381`）均 success。docs-only 增量门禁验收 head `8d22af07f69a398a6d9d8ea22fecaf80326c4f13` 的 required `Tests #94`（`33327150987`）、legacy `Godot Tests #123`（`33327150981`）与 `Windows Export #15`（`33327150974`）也均 success，其中 #15 明确判定 `should_export=false / synchronize-nonruntime-only`，重型 `export-windows` 与 `smoke-windows` 均 skipped。后续状态/文档提交仍必须以各自新 head 的 required `Tests` 为准；docs-only 后继提交可明确引用直接父 runtime/workflow head 的 Windows Export 证据，但不得称为新 head 自己执行过被跳过的重型导出。

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

- Windows 与 Linux 聚合脚本统一运行十一套原生测试：关卡数据、武器、灰盒关卡、命中反馈、战术 Bot、爆破 AI、比赛生命周期、Gatehouse 场景集成、主状态流、音频资产和性能预算。Step 16 runtime/workflow 证据 head `69d2a3395d2cb7799f923868a1d07adb5fe34e96` 的 required `Tests #93` 与 legacy `Godot Tests #122` 双路径 native 回归均通过；docs-only 增量门禁验收 head `8d22af07f69a398a6d9d8ea22fecaf80326c4f13` 的 required `Tests #94` 与 legacy `Godot Tests #123` 也均通过。C4Device runner 含 6 项对象级回归。当前不在权威状态中写入无法从现有日志稳定复核的聚合测试总数。
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

### Step 16：C4 Device Real Feature Pressure Test（进行中）

Step 16 已选定 C4 Device 作为第一项真实 asset-driven feature pressure test，而不是继续预装更多工具。它验证 Step 11–15 的 source ownership、metadata、canonical Blender source、deterministic publish/rebuild 与 fresh GLB runtime gate 是否能支撑真实玩家可见功能变化。

当前已完成：

1. **Feature / Asset Impact Audit。** C4 生产资产、运行时集成、对象状态与测试边界已经进入审计；爆炸半径、致死半径、拾取/交互距离和伤害公式等冻结玩法数值未改。
2. **完整 Source → Runtime 正向链。** C4 canonical `.blend`、sidecar、producer、runtime contract、fresh GLB rebuild、Godot scene/runtime integration 已由 runtime/workflow 证据 head `69d2a3395d2cb7799f923868a1d07adb5fe34e96` 的 required `Tests #93`（`33326528374`）全链验证通过。
3. **Fail-closed 负向证据。** PR #28 只降低 C4 triangle budget，精确在 Asset Runtime Gate 失败且阻断全部 Godot 后续阶段；PR 已关闭未合并。
4. **状态回归补强。** 已修复 armed C4 在跨状态/跨回合时可能残留高亮、beep pitch/播放状态和 site label 的泄漏；C4Device runner 现含 6 项对象级回归，`69d2a339` 的 required `Tests #93` 与 legacy `Godot Tests #122` 双路径 native 均通过，docs-only `8d22af07` 的 #94/#123 又复验同一 runtime tree。
5. **发布门禁压力测试闭环。** Step 16 暴露并修复了两层 Windows 发布问题：首先让 `assets/**`、`data/**`、`scenes/**`、`scripts/**` 的正常 runtime feature 自动进入发布验证；随后用 previous-head → new-head 增量 detector 阻止同一 PR 后续 docs-only synchronize 重复烧重型构建。`Windows Export #14` 在 `69d2a339` 证明 `should_export=true` 时完整 EXE/PCK + Windows smoke 全绿；`Windows Export #15` 在 `8d22af07` 证明 `should_export=false` 时重型 export/smoke 均正确 skipped；不可验证 previous head 时 fail-open。
6. **云端审查闭环。** PR #27 两条 P1 finding 均已修复并 resolved，review submissions 无 `REQUEST_CHANGES`；负测 PR #28 已关闭未合并。当前没有可在 GitHub/CI 侧继续完成的 Step 16 review blocker。
7. **本机视觉/性能探针已就绪。** `run-c4-visual-probe.cmd` 会先删除旧证据，再在真实 `Main.tscn` Gatehouse 场景采样 hidden baseline / dropped / planted calm / planted urgent，输出 `reports/step16-c4-evidence.json` 与 dropped/planted/urgent 三张 PNG；探针主动退出属于正常完成行为。

**云端 / CI / Review 侧已无未完成项。以下项目必须依赖用户本机可见/可听/可交互证据，或依赖这些证据后的人工审批，不能由云端自动化替代：**

- **本机 RTX 5060 Forward+/Vulkan visual/performance evidence：OPEN。** 尚未在本对话取得 fresh JSON 与三张截图，因此不能宣称比例、接地、材质可读性、灯光位置、遮挡/HUD 或 avg/p95 delta 已人工通过。
- **非颜色单一依赖的紧迫感检查：OPEN。** 必须人工确认 planted/urgent 状态除颜色外还能由闪烁/声音等线索可靠区分。
- **Windows input/audio smoke：OPEN。** 必须在用户本机确认实际输入、拾取/安装/拆除、beep 与状态切换无异常。
- **Asset review：OPEN。** C4 sidecar 的 `review.status = draft` 是合法且刻意保留的未审状态；只有本机视觉/资产人工审阅通过后才能晋级，不得由 CI 或状态文档擅自改为 `approved`。
- **L3：OPEN。** 需在上述本机证据完成并复核后取得明确 L3/`APPROVED`；当前不得合并 PR #27。

**GATE = PARTIAL / DO NOT MERGE。** 所有不依赖本机的 Step 16 工作已经闭环；当前剩余项仅为本机 Vulkan 视觉/性能、非颜色紧迫感、输入/声音、由这些证据决定的人工资产审阅，以及其后的显式 L3。Step 16 未闭环前不启动 Step 17。

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

第 1 步的自动化与状态正确性已完成并通过 G1。当前只准备并执行 G2 十场人工完整比赛及其只读证据汇总；G2 通过前不进入 AI 行为质量扩展。

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