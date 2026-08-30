from __future__ import annotations

from pathlib import Path


STATUS_PATH = Path("docs/PROJECT_STATUS.md")

REPLACEMENTS = {
    "- 6 个 Git tracked Blender canonical master 已集中在 `assets-source/blender/` 并由 Git LFS 管理；每个 master 都有相邻 `*.asset.json` sidecar 记录资产身份、canonical source path 与 tracked runtime outputs。Godot 运行时资产继续位于 `assets/`，源 `.blend` 不直接成为运行时权威。":
        "- 7 个 Git tracked Blender canonical master 已集中在 `assets-source/blender/` 并由 Git LFS 管理；新增第 7 个为 Step 16 的原创 C4 objective master。每个 master 都有相邻 `*.asset.json` sidecar 记录资产身份、canonical source path 与 tracked runtime outputs。Godot 运行时资产继续位于 `assets/`，源 `.blend` 不直接成为运行时权威。",
    "- Windows 与 Linux 聚合脚本统一运行十一套原生测试：关卡数据、武器、灰盒关卡、命中反馈、战术 Bot、爆破 AI、比赛生命周期、Gatehouse 场景集成、主状态流、音频资产和性能预算；当前基线为 135 项并出现 `RUN_ALL_OK`。":
        "- Windows 与 Linux 聚合脚本统一运行十二套原生测试：关卡数据、武器、灰盒关卡、命中反馈、战术 Bot、爆破 AI、比赛生命周期、Gatehouse 场景集成、主状态流、音频资产、C4 设备对象级回归和性能预算；当前基线为 140 项并出现 `RUN_ALL_OK`。",
    "- Required `Tests` 已在 Godot 之前执行 Asset Layer、Asset Metadata 与 Asset Runtime Contract policy：当前 canonical source master 为 6 个，metadata sidecar 覆盖 6/6、资产 ID 唯一；6 个 Blender producer 拥有 13 个 runtime outputs，其中 7 个 GLB 必须具有合法 runtime contract。sidecar 中 runtime outputs 必须是 `assets/` 下规范、去重且 Git tracked 的实存路径；mandatory source coverage 同时包含 Blender/Krita/PSD/FBX 等源资产与音频 master。":
        "- Required `Tests` 已在 Godot 之前执行 Asset Layer、Asset Metadata 与 Asset Runtime Contract policy：当前 canonical source master 为 7 个，metadata sidecar 覆盖 7/7、资产 ID 唯一；7 个 Blender producer 拥有 14 个 runtime outputs，其中 8 个 GLB 必须具有合法 runtime contract。sidecar 中 runtime outputs 必须是 `assets/` 下规范、去重且 Git tracked 的实存路径；mandatory source coverage 同时包含 Blender/Krita/PSD/FBX 等源资产与音频 master。",
    "- Step 13 已接入 Blender 5.2.1 LTS headless source gate：6/6 tracked Blender master 在真实 canonical path 上通过 naming safety、外部 FILE/SEQUENCE/MOVIE/TILED/UDIM 资源实存、geometry unit scale、finite/non-singular transform、metadata/source identity 与二进制/LFS preflight；正向 PR #18 随后继续通过 Godot import、GdUnit4 与 native suites。":
        "- Step 13 已接入 Blender 5.2.1 LTS headless source gate：7/7 tracked Blender master 在真实 canonical path 上通过 naming safety、外部 FILE/SEQUENCE/MOVIE/TILED/UDIM 资源实存、geometry unit scale、finite/non-singular transform、metadata/source identity 与二进制/LFS preflight；新增 C4 master 已在 Step 16 PR #27 的 fresh source gate 中通过。",
    "- **Godot 自动化：PASS。** Godot 4.7.1 headless import、GdUnit4、十一套 native suites 已进入 required `Tests`；native runner 现在会为每个场景打印 START/PASS/FAIL，并在首个失败场景产生 GitHub error annotation。":
        "- **Godot 自动化：PASS。** Godot 4.7.1 headless import、GdUnit4、十二套 native suites 已进入 required `Tests`；新增 `C4DeviceTestRunner` 覆盖 runtime GLB/stable nodes、carried/drop/pickup、planted/radar、urgency audio/light 与冻结 gameplay 常量。native runner 会为每个场景打印 START/PASS/FAIL，并在首个失败场景产生 GitHub error annotation。",
    "- **Asset Layers / LFS（Step 11）：FULL PASS。** 三层为 `assets-source/` canonical source、`assets-generated/` 可重建 staging、`assets/` reviewed runtime。6 个 Blender master 与 HDR 历史资产已完成真实 Git LFS pointer/对象迁移，CI checkout 使用 `lfs: true`；路径门禁已做正/负验收。":
        "- **Asset Layers / LFS（Step 11）：FULL PASS。** 三层为 `assets-source/` canonical source、`assets-generated/` 可重建 staging、`assets/` reviewed runtime。7 个 Blender master 与 HDR 历史资产由 Git LFS 管理；Step 16 C4 master 由 Blender 5.2.1 bootstrap 真生成并完成 1/1 LFS object upload。CI checkout 使用 `lfs: true`；路径门禁已做正/负验收。",
    "- **Asset Metadata（Step 12）：FULL PASS。** 6/6 canonical Blender master 具有相邻 `*.asset.json`；source identity、provenance/license/AI usage 状态、producer、runtime outputs 等由 CI 校验。历史未知信息保持显式 `unknown`，不伪造来源或许可证。":
        "- **Asset Metadata（Step 12）：FULL PASS。** 7/7 canonical Blender master 具有相邻 `*.asset.json`；source identity、provenance/license/AI usage 状态、producer、runtime outputs 等由 CI 校验。C4 sidecar 明确记录 `project-authored / project-owned / assisted` provenance，视觉人工批准前 review 状态保持 `draft`。历史未知信息仍保持显式 `unknown`。",
    "- **Blender Source Validation（Step 13）：FULL PASS。** Blender 5.2.1 LTS 在 CI 中直接打开 6/6 canonical zstd-compressed `.blend`，验证命名、外部纹理、scale、finite/non-singular transform、metadata identity 与 LFS/binary preflight。PR #19 的 unapplied-scale 负测证明坏 source 会在 Godot 之前 fail-fast。":
        "- **Blender Source Validation（Step 13）：FULL PASS。** Blender 5.2.1 LTS 在 CI 中直接打开 7/7 canonical `.blend`，验证命名、外部纹理、scale、finite/non-singular transform、metadata identity 与 LFS/binary preflight。PR #19 的 unapplied-scale 负测证明坏 source 会在 Godot 之前 fail-fast；Step 16 的新 C4 source 同样通过该 gate。",
    "- **Blender Publish/Rebuild（Step 14）：FULL PASS。** 6 个 canonical producer 通过 metadata 合同拥有 13 个 runtime outputs；Gate 会在 builder 前删除旧 declared outputs，要求 fresh 重建，拒绝未声明 asset-side effect，producer 间恢复工作树，然后让 runtime validator、Godot import、GdUnit4、native suites 消费 fresh runtime set。PR #20 已合并为 `bcb24be4a71b6863d558a73511e00d89e612a9fe`，合并后的 main `Tests` 与 `Godot Tests` push workflows 均 success。":
        "- **Blender Publish/Rebuild（Step 14）：FULL PASS。** 7 个 canonical producer 通过 metadata 合同拥有 14 个 runtime outputs；Gate 会在 builder 前删除旧 declared outputs，要求 fresh 重建，拒绝未声明 asset-side effect，producer 间恢复工作树，然后让 runtime validator、Godot import、GdUnit4、native suites 消费 fresh runtime set。Step 16 C4 producer 已作为第 7 个 producer 进入同一 required chain。",
    "- **Asset Runtime Gate（Step 15）：FULL PASS。** 6 个 sidecar 为 7 个 Blender-owned GLB 提供 asset-specific runtime contracts；cheap contract policy 在 Blender 安装前校验 schema，fresh rebuild 后 `tools/validate_runtime_assets.py` 校验 GLB/glTF container、引用/embedded resource、bufferView/accessor 边界、finite transform metadata、triangle primitives、结构/预算指标与 extension allowlist，再允许 Godot 消费。正向 required `Tests` run `33308981479` 全绿。":
        "- **Asset Runtime Gate（Step 15）：FULL PASS。** 7 个 sidecar 为 8 个 Blender-owned GLB 提供 asset-specific runtime contracts；cheap contract policy 在 Blender 安装前校验 schema，fresh rebuild 后 `tools/validate_runtime_assets.py` 校验 GLB/glTF container、引用/embedded resource、bufferView/accessor 边界、finite transform metadata、triangle primitives、结构/预算指标与 extension allowlist，再允许 Godot 消费。C4 fresh baseline 为 126,660 B / 1,480 triangles / 34 nodes / 6 materials，并以实测数据建立 asset-specific contract。",
}

STEP16_OLD = "### 工程管线下一步：Step 16 Visual / Real Feature Pressure Test\n\nStep 11–15 已把 source ownership、metadata、canonical Blender source、deterministic publish/rebuild 与 fresh GLB runtime structural/budget validation 串成 required `Tests` 的 fail-closed 链。下一步不再优先安装更多工具，而是验证这套管线能否支撑**真实生产变化**。"
STEP16_NEW = "### 工程管线当前：Step 16 Visual / Real Feature Pressure Test\n\nStep 16 首个真实 Feature 已锁定为 **C4 设备生产资产化 + 状态可读性集成**。PR #27 已用 Blender 5.2.1 生成真实 Git LFS canonical `.blend` 与 fresh GLB，并通过 Asset Layer / Metadata / Runtime Contract / Blender Source / fresh Publish-Rebuild / Runtime Gate / Godot import。专用 `C4DeviceTestRunner` 已接入 Windows/Linux native 聚合器；Forward+ visual probe 可生成 dropped / planted / urgent 三张 PNG 与 JSON 快照。**视觉人工审图和必要的性能证据仍为 OPEN，因此不得把结构/自动化 PASS 冒充最终视觉 PASS。**"


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new)


def main() -> None:
    text = STATUS_PATH.read_text(encoding="utf-8")
    for index, (old, new) in enumerate(REPLACEMENTS.items(), start=1):
        text = replace_exact(text, old, new, f"replacement-{index}")
    text = replace_exact(text, STEP16_OLD, STEP16_NEW, "step16-heading")
    STATUS_PATH.write_text(text, encoding="utf-8", newline="\n")
    print("STEP16_PROJECT_STATUS_SYNC=PASS")
    print(f"replacements={len(REPLACEMENTS) + 1}")


if __name__ == "__main__":
    main()
