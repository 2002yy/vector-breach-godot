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
- `map-views-final/` 与 `pack-map-views/`：三图四个表面，各有原机位、不同距离、斜视和隐藏诊断，共各 20 张截图。隐藏仅用于确认底层，不是修复。Dust II 两个远/斜机位被门框挡住，不作为通过证据；另以 `pack-dust-clear/` 补采两个无遮挡距离/角度。三图局部污渍与边界结果已查看，局部通过，不代表全图逐区验收。
- 最终完整原生 193 项、Python 非 Blender 完整 23 项、GdUnit 2/2 通过，原生日志 `native-frozen-final.log` 含 `RUN_ALL_OK` 且无脚本/引擎错误。资产四项约束、Ruff、格式、两个新增 GDScript 模块 lint 通过；修改的旧模块 lint 基线/当前均为 90，新增类别/新增行错误均为 0。Godot 原生回归同时承担脚本解析/类型检查。
- 导出 PCK 的六套角色/双臂/装备动作/5v5 探针通过，共 39 张图，抽查全身及第一人称代表视角未见本批新增问题。实际资源加载器复查 82 条定义：80 条有效材质带完整源参数，另两条 C4 屏幕由动态显示覆盖，源参数仍在模型根契约/旁存清单。燃烧瓶持握/投掷调用截图与实际加色、透明非深度预写状态通过；完整原版点火、火焰动画仍未关项。
- 最终包位于 `D:/AgentGamePipeline/builds/VectorBreach-material-rules-20261020/`。原始三图碰撞字节由 `stage_frozen_match_sources.py --require-all` 校验并携带；EXE 在源码目录之外正常退出 0、无错误。必须保留整个构建目录。最终三图界面流程、精确提交/CI、包哈希和桌面入口备份在私有 `delivery.json`。
- 原网格、碰撞字节、冻结路网与炸弹/伤害/经济未改动；此前 AI 路线、整场人工试玩、平衡和 70% 帧率验收仍开放。

下一片：按源参数和当前运行时对照，先验证角色专用着色特性与地图高风险材质，再逐项实现；不把本批 32 个资源的静态扫描称为全图最终美术验收。

## 有意义的失败与修复

首次完整候选回归在头less dummy 渲染器中为预先复制的角色材质查询 Shader 时触发 `material is null`，即使测试断言通过也判失败。修复为 headless 逻辑保留完整根契约但不安装 GPU 材质覆盖，Vulkan 正常应用；定向 Bot 32 项及上述最终完整 193 项重新通过。`native-candidate-final.log` 是已拒绝的失败日志，不是最终通过证据。

私有资源探针最初在外部 SceneTree 脚本解析期 preload 依赖 autoload 的装备类，导致 RoundManager 尚未注册；改为 deferred 阶段动态加载。最终 `actual-asset-materials-final.log` 有 82 条实际加载结果且无错误。未为修复测试探针而改变游戏的自动加载规则。
