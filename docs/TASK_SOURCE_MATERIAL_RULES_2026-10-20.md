# 源材质规则恢复与原“无问题”资源复查

基线 `7361a1547c014098defc9bfbf76a1e6a8c49f45c`，分支 `fix/source-material-rules-20261020`。用户要求继续修复待修项，同时检查此前仅因纹理文件齐全而未发现问题的资源。原纹理、源材质、运行时实现和画面验收分别记录，不将保存源参数等同于还原全部源着色器。

## 修复范围

- 三种 `csgo_static_overlay.vfx / F_BLEND_MODE=3`：Dust II `dust_mudbrick_transition_overlay`，Mirage `stain01`（两处），Inferno `top_grime_2`。新独立 `source-modulate.json` 保存完整 VMAT、导出材质、输入哈希与明确渲染契约；不覆盖原 PNG、GLB/glTF 或已有模式 1/2 清单。
- Dust II 原 VTEX 通过固定 Steam depot 2347770 / manifest 2520908610273941189 定向取得，VPK CRC 验证通过；原生解码 Alpha 为 0–255。其余两种分别 0–207、0–235。三者解码 RGB 与旧 PNG 逐像素相同，使用旁存原生 RGBA。
- Mod2x 使用 `D * mix(1, 2 * RGB, alpha * opacity)`，编码 RGB 采样、线性 Alpha，保留导入的线性颜色因子、UV、沿法线偏移、剔除和优先级。深度测试开启、深度写入关闭、静态贴花不投影。普通透明和加色均不是该契约。
- 使用当前环境的距离/深度/高度雾衰减，将乘数淡向 1，避免对已受雾影响的底层再次加入雾色。未宣称复刻 Source 2 全部体积雾与原光照。
- 复查发现模式 1/2 静态贴花也必须隐含关闭投影，补齐该规则；其源 `F_LIT=1` 的正常照明保留。
- 燃烧瓶 `weapon_molotov_flame` 原 `F_ADDITIVE_BLEND=1`，运行时却为普通混合、透明深度预写；新资源契约将其改为加色、普通透明通道，保留原 PBR/发光和纹理。

可复核依据：ValveResourceFormat 提交 [`54279ec226cc3e1c561b10f11f0f5e879b981e6e`](https://github.com/ValveResourceFormat/ValveResourceFormat/tree/54279ec226cc3e1c561b10f11f0f5e879b981e6e) 的 `RenderMaterial.cs`（模式 3 的混合因子、贴花深度/阴影规则）、`complex.frag.slang`（编码 RGB 与中性 0.5/Alpha）、`common/fog.slang`（乘色贡献的中性衰减），及 Godot 渲染器/GLTF 导入的颜色与雾规则。这里是公开可复核实现依据，不宣称持有 Valve 的完整引擎源代码。

## 扩展复查与参数保存

`audit_source_material_contracts.py` 对三图、6 套角色全身/双臂及 11 个装备模型进行只读复查：32 个资源、2097 条材质记录。存档包含完整源 VMAT、导出材质、图像/纹理/采样器绑定、来源与运行资源哈希。运行时另检查 2215 个有效材质实例；实例数与材质定义数含义不同。

角色/装备 29 个 GLB 的 82 条材质定义在 Blender 重新导出后没有源 VMAT extras。已将完整参数另存可随包分发的 `source-materials.json`，实际加载器通过不修改原资源的覆盖材质附加参数元数据。源 Shader 的未实现特性写入 `source_features_pending`，保留明确的待修边界。

数据报告中的 813 条“专用特性需映射”和 432 条非默认颜色/UV 调整是复核线索，可能已由导出、UV 或运行时修复处理，不能作为新增缺陷数量。已确认待修的是角色布料高光、各向异性、皮肤次表面及距离对比度等专用效果的完整映射/视觉核验；基础颜色、法线、AO、金属/粗糙度贴图存在不能替代这部分验收。

## 验证与交付边界

私有证据：`D:/AgentGamePipeline/evidence/source-material-rules-20261020/`。

- `gpu-final.log`：零 Alpha、中性灰、压暗/提亮、部分 Alpha、明暗底色、重叠、顺序互换、深度遮挡、雾中性衰减均通过实际 Vulkan 像素检查；五个基础公式最大通道误差小于 0.003。
- `map-views-final/`：三图四个有效表面，各有原机位、远景、斜视和隐藏诊断，共 20 张截图。隐藏仅用于确认底层，不是修复。四个原机位已查看；其余视角及最终包复验结果以交付收据为准。
- 定向材质 22 项、Main 48 项、Python 非 Blender 完整 23 项、GdUnit 2/2 已通过。加入最终资源加载规则后，完整原生套件再次运行；最终结果、导出包、精确提交/CI 及截图签核写入 `delivery.json`，未完成前不以早期通过替代。
- 原网格、碰撞字节、冻结路网与炸弹/伤害/经济未改动；此前 AI 路线、整场人工试玩、平衡和 70% 帧率验收仍开放。

下一片：按源参数和当前运行时对照，先验证角色专用着色特性与地图高风险材质，再逐项实现；不把本批 32 个资源的静态扫描称为全图最终美术验收。
