# Step 16 C4 Device Feature Impact Audit

Status: ACTIVE / implementation gate
Base: `main@99f05064ef6db592217a4cc898b2642ab6162a1f`
Feature branch: `feature/step16-c4-device`

## 1. Feature decision

Step 16 的首个真实全链压力测试锁定为：**C4 设备生产资产化 + 状态可读性集成**。

当前 `scenes/objective/C4Device.tscn` 只使用一个 `BoxMesh(0.42, 0.18, 0.28)`、单一材质和 `OmniLight3D`；而 `scripts/objective/C4Device.gd` 已经拥有 carried / dropped / planted 生命周期、拾取与交互距离、爆炸伤害、雷达记录、蜂鸣与倒计时紧迫度逻辑。仓库当前没有 C4 专用 canonical Blender master 或 runtime GLB。

因此该 Feature 不是为了管线而造的夹具，而是把一个已经参与正式爆破玩法的玩家可见占位物体升级为真实生产资产，并用它压力测试 Step 11–15 建立的 Source → Runtime fail-closed 链。

## 2. Hypothesis

如果现有主控管线已经达到可生产状态，那么新增一个真正的 C4 资产时，应能从新的 canonical Blender source 出发，经 metadata、source validation、deterministic publish/rebuild、runtime GLB contract、Godot import、对象级状态回归、既有比赛回归和视觉/性能证据完整闭环，而不需要手改生成结果或绕过 required `Tests`。

若该流程暴露缺口，只修复被真实 Feature 证明存在的缺口，不预装新的复杂制作系统。

## 3. Scope

### In scope

- 新增原创 C4 canonical Blender master，目标位置：`assets-source/blender/objectives/c4_device_source.blend`。
- 新增相邻 metadata sidecar，记录 identity、provenance/license/AI usage、build script、runtime outputs 与 runtime contract。
- 新增确定性 Blender builder/publisher，输出 reviewed runtime GLB（目标：`assets/models/objectives/c4_device.glb`）和必要的 preview/evidence 输出。
- `C4Device.tscn` 从内置 BoxMesh 切换为 runtime GLB 实例，同时保留 Godot 侧 `StatusLight` / beep 状态控制。
- dropped 与 planted 必须具有可辨识的实体轮廓；planted/armed 状态的紧迫度仍由现有 beep + light 驱动。
- 可读性不能只依赖颜色：至少同时存在几何/明暗或闪烁节奏等非纯色线索。
- 新增 C4 对象级自动回归，并重新运行现有比赛生命周期/爆破 AI/Gatehouse 集成等相关回归。
- 玩家可见变化需要 Vulkan 截图/录屏或等价视觉证据，并记录性能影响。

### Explicit non-goals

- 不改变 `explosion_radius = 22.0`、`lethal_radius = 5.5` 或爆炸伤害公式。
- 不改变安装、拆除、爆炸倒计时、拾取距离、交互距离、经济奖励或胜负规则。
- 不重写 Bomb AI、路径系统、RoundManager 或 C4 所有权协议。
- 不新增联网/复制/服务器权威逻辑。
- 不把结构/runtime Gate 冒充视觉、GPU、输入或声音人工验收。
- 不顺带重做 HE/闪光/烟雾/刀等其他装备资产。

## 4. Feature Impact Audit

所有域必须为 `Impact` 或 `N/A + reason`，不得留空。

| Domain | Decision | Required handling |
| --- | --- | --- |
| Gameplay | **Impact** | C4 场景资源和状态可见性会变化；行为数值冻结，必须证明 carried/dropped/planted/pickup/plant/defuse/explode 回归无变化。 |
| Economy | **N/A** | 不改购买、奖励、失败/连败经济或装备价格。 |
| AI | **Impact** | Bot 已依赖 C4 carry/drop/plant/defuse 生命周期；不改决策逻辑，但相关爆破 AI 回归必须重跑，防止场景节点/资源替换破坏引用。 |
| Level | **N/A** | 不改 level JSON、爆点、碰撞拓扑、路线或接触时序。C4 视觉不得成为关卡碰撞权威。 |
| UI | **Impact** | HUD/C4 交互文本逻辑不改，但世界内 planted/dropped 可读性属于玩家信息层，需验证现有 HUD 与新世界表现不冲突。 |
| Tutorial | **N/A** | 不新增教程步骤或训练说明。 |
| Input | **N/A** | 不改按键、交互持续时间或输入映射。 |
| Accessibility | **Impact** | armed/readability 不能只依赖红/绿颜色；蜂鸣节奏 + 亮度/闪烁 + 设备轮廓至少提供两种线索。 |
| Save / State | **Impact** | 不新增持久化 schema，但必须验证新视觉节点不改变 `device_state`, `carrier_team`, `site_label` 和新比赛/回合重置边界。 |
| Network | **N/A** | 当前产品为单机，本 Feature 不引入网络状态。 |
| Animation | **Impact** | 若 runtime GLB 使用机械/显示动画，必须显式进入合同；v1 可无骨骼动画，但 armed 状态闪烁/脉冲仍需由可测试的 Godot 状态驱动。 |
| VFX | **Impact** | 现有 StatusLight 保留；允许调整挂点/范围以匹配新模型，但不得改变 gameplay 爆炸判定。 |
| Audio | **Impact** | beep 行为和生成方式冻结，但必须确认新场景资源替换后 AudioStreamPlayer3D、pitch/urgency 逻辑继续工作。 |
| Art | **Impact** | 新原创 C4 生产资产、canonical `.blend`、GLB、材质与 preview；尺寸需保持约 0.42 × 0.18 × 0.28 m 的现有 gameplay/readability footprint。 |
| Performance | **Impact** | 新 GLB 必须有 asset-specific runtime budget；记录 triangles/materials/textures/file size，并做至少一项 runtime/visual probe 性能对比。 |
| Localization | **N/A** | 不新增玩家可见文本；如后续加入屏显文字，必须另开影响项，不在本 Feature 偷渡。 |
| Analytics / Telemetry | **N/A** | 不新增埋点；现有比赛记录/雷达记录保持原 schema。 |
| Tests | **Impact** | 新增 C4 资源/状态合同测试；重跑 required `Tests`、GdUnit4、native suites；做一条独立 do-not-merge 负向验收。 |
| Build / Release | **Impact** | 新 `.blend` 必须真实 Git LFS；metadata producer、fresh rebuild、runtime Gate、Godot import、Windows build 路径均需可消费新资产。 |
| Legal / Provenance | **Impact** | C4 设计必须为项目原创或明确许可来源；sidecar 记录 provenance/license/AI usage。未知信息不得伪造为已知。 |

## 5. Asset and integration contract

### Canonical source

Target:

```text
assets-source/blender/objectives/c4_device_source.blend
assets-source/blender/objectives/c4_device_source.blend.asset.json
```

The `.blend` must be a real Blender binary tracked through Git LFS. **A textual LFS pointer created through a text-only API is not acceptable evidence.** The feature remains blocked at the DCC binary gate until the actual LFS object is uploaded and CI checks it out successfully.

### Deterministic producer

Target builder:

```text
tools/blender/build_c4_device.py
```

Target runtime output:

```text
assets/models/objectives/c4_device.glb
```

Optional preview/evidence output may be added only if declared by the producer metadata. Undeclared asset-side effects remain forbidden.

### Godot integration

`scenes/objective/C4Device.tscn` keeps the existing script contract and node-level control surface needed by `C4Device.gd`. The model may sit below `MeshRoot`, but these stable responsibilities must remain available:

- `MeshRoot` visibility controlled by carried/dropped/planted state;
- `StatusLight` controlled by planted urgency;
- `BeepPlayer` controlled by existing audio logic;
- world transform remains the gameplay interaction/explosion origin.

The GLB is visual authority only. Interaction range and explosion damage remain code authority.

## 6. Automated acceptance

### Positive path

1. Asset Layer / LFS policy passes with the new canonical source.
2. Asset Metadata and Runtime Contract policy discover the new sidecar/output.
3. Blender 5.2.1 opens the real canonical source and source validation passes.
4. Publish/Rebuild deletes the tracked C4 runtime GLB, invokes the C4 producer, and recreates it fresh.
5. Asset Runtime Gate validates the fresh C4 GLB against its own contract.
6. Godot import succeeds.
7. New C4 object-level tests prove:
   - initial carried state hides `MeshRoot`;
   - drop exposes model and preserves pickup rules;
   - plant exposes model and preserves site label/state;
   - pickup returns to carried/hidden;
   - required stable nodes/resources exist;
   - no gameplay constants changed from the frozen baseline.
8. Existing GdUnit4 and native suites reach `RUN_ALL_OK`.
9. Windows export/runtime smoke remains compatible when the changed paths trigger that workflow.

### Negative path

Use a separate **DO NOT MERGE** PR with one controlled fault after the positive baseline is green. Preferred fault: tighten the C4 runtime contract below the measured fresh triangle/file-size baseline or remove one required runtime expectation. Required result:

```text
Asset Layer                 PASS
Asset Metadata              PASS
Runtime Contract Policy     PASS
Blender Source              PASS
Publish/Rebuild             PASS
Asset Runtime Gate          FAIL (exact C4 reason)
Godot import                SKIPPED
GdUnit4                     SKIPPED
Native suites               SKIPPED
```

The negative PR must be closed unmerged and the branch reset/removed.

## 7. Visual and performance acceptance

Structural CI is not enough. Before Step 16 can be FULL PASS:

- capture dropped C4 and planted/armed C4 in a real gameplay scene under Forward+/Vulkan where available;
- visually inspect silhouette, scale, ground contact, material readability, light placement, occlusion, and HUD overlap;
- confirm armed urgency remains perceivable without relying on color alone;
- record asset metrics from Runtime Gate and compare a relevant scene/probe performance baseline; no unexplained hard regression;
- human local Windows graphics/input/audio smoke remains a separate manual item if the current environment cannot provide it.

## 8. Rollback / compatibility acceptance

- Reverting the C4 scene to the previous BoxMesh must not require state/schema migration.
- No save/network migration exists.
- Existing radar record keys (`kind`, `state`, `x`, `z`, `site`) stay unchanged.
- Existing C4 gameplay constants and public methods remain source-compatible unless a later explicit design decision changes them.

## 9. Definition of Done

Step 16 C4 is FULL PASS only when the completion report contains:

- **TASK** — exact production objective;
- **CHANGES** — source/runtime/Godot/test changes;
- **FILES** — canonical source, metadata, producer, runtime output, scene/script/tests/docs;
- **TESTS** — positive CI, object-level regression, full suites, negative gate;
- **RESULTS** — exact PASS/FAIL evidence;
- **EVIDENCE** — CI run IDs, runtime metrics, visual/performance evidence;
- **REGRESSION** — existing C4/bomb/match behavior proven unchanged;
- **KNOWN ISSUES** — especially manual visual/audio/input items not automated;
- **NEXT** — only after evidence;
- **GATE** — PASS / PARTIAL / FAIL.

No merge to `main` without the normal protected-branch gate and explicit L3 approval.
