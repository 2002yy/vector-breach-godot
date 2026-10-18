# 三图广泛材质排查、实时帧率与开局界面

用户新增 Inferno 教堂附近橙红色重叠矩形截图，随后明确要求三张经典图都广泛排查，并增加合理位置实时 FPS、核对经典 CS 按键、优化开局 UI。该片接在 main `92f6780`（PR #48）之后，当前分支 `perf/classic-native-draw-batching-20261018`；本地 `33a3fb4` 是静态分组候选，后续材质/UI 仍在工作区，尚未交付新包或推送。桌面入口继续指向已验证的 C 盘悬空贴花修复包。

## 数据排查与已定位问题

证据目录 `D:/AgentGamePipeline/evidence/inferno-orange-decals-20261018/`，用户原图在 `user-report/`。扫描 Dust II 713、Mirage 379、Inferno 923 个材质，共 2015 个；未发现引用的外部 PNG 文件缺失。初轮候选为 14 / 6 / 27，排除工具道具误判后 Inferno 为 26；这些是语义排查线索，不是已证实缺陷总数。原 VMAT、纹理、透明模式及来源逐项保存在 `three-map-material-audit.json`。

原导出器未将 `csgo_static_overlay.vfx` 的 `F_BLEND_MODE` 映射至 glTF 透明模式。依据 [20.1 RenderMaterial](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/20.1/Renderer/Renderer/Materials/RenderMaterial.cs)，1 为透明、2 为 alpha-test、3 为 Mod2x，不能一律当作透明、加色或删除。Inferno 箭头/笔画等颜色 PNG 为 RGB，原 VTEX Alpha 则有大面积为 0；例如笔画纹理约 75.65% 为全透明。PNG 查看器显示 RGB 不能代替运行时透明验证。

原生解码后，Mirage 两份、Inferno 二十四个材质实例的 RGB 均逐像素匹配当前图；模式 1/2 实际安装为 Dust II 1、Mirage 2、Inferno 19 个唯一材质条目，原文件均保留。Mirage 2、Inferno 18 张新增 PNG 是原 VTEX 解码成品，旁置 `source-decals/`；Dust II 使用既有非恒定 Alpha 的 RGBA PNG，**本轮没有重新取得它的旧 VTEX**。`prepare_source_decals.py` 校验指定视觉哈希、解码收据、RGB 一致、非恒定 Alpha 和同名材质一致性，拒绝冲突后再安装，不绘制/重建贴图。新 PNG 的 20 份导入使用 BC7/mipmap，备份和清单保留。

运行时 `SourceDecalMaterials.gd` 在原偏移修复后按实例复制原材质，保留 PBR、UV、法线和 grow，仅恢复原透明/裁切、opacity 与明确 no-shadow 标记。支持已有 material_override，重复执行不再次乘 opacity；独立碰撞和原网格不变。模式 3 的泥砖过渡、污渍及污垢仍需验证 Mod2x，不能因模式 1/2 安装成功就关项。

Mirage A 点黄黑秒表条带定位到 `materials/tools/wrongway_timer.vmat`。`SourceVisualHelpers.gd` 仅处理精确已核实的 `wrongway_timer`、`toolssolidblocklight`、`toolsblocklight`；不把 bucket_tools / gardening_tools 等真实道具当辅助面。单独工具叶节点隐藏，混合表面/含真实子节点则只屏蔽工具表面；原材质与几何保留。遮挡生成也排除这三个工具材质，Inferno 遮挡需按新规则重建并对照；Mirage 当前未启用 occluder，不能凭图形隐藏声称其物理查询已改变。

## HUD 与开局操作

候选 HUD 在右上金钱下方新增实时 FPS / ms，每 250 ms 用真实墙钟采样刷新，击杀/无线电信息下移，避免重叠。开局大操作面板默认收起，F1 可在菜单和对局中打开；关闭设置不自动弹出整页帮助。减少左栏纵向间距，经典图增加手枪 $800 开局、购买后点就绪即可开战的说明。尚需实际截图、真实按钮和最终包验证。

按键核对：WASD、Shift、Ctrl、空格、R、E、G、B、Tab 和 1–5 装备槽沿用常见 CS 布局；全屏已从 F 改为 F11，指南同步。仍有额外 C 蹲伏、P 暂停、F1 帮助，Q 上一把及鼠标滚轮切换尚未接入。未宣称与 CS 1.6 / CS:GO 全部默认绑定一致；购买分类、F1 自动购买及检视等仍有差异。

## 验证断点与边界

`33a3fb4` 的正式分组最终性能样本为 `formal-final-*.json`，已有完整原生 183 项无脚本错误；后续材质/UI 变化会使这份全套不能替代新候选验收。GdUnit 包装脚本因 PowerShell Stop 将插件既有 owner 参数遮蔽警告当作异常，未进入导出；需修正包装方式、只对真实退出/错误失败，最终新候选再跑必要检查。

新增材质/辅助面聚焦 22 项已通过。保留失败：辅助面脚本一次 Variant 类型推断错误；切割测试暴露 material_override 优先于 surface override，现按实际优先级设置；不能只看 Godot 的退出 0 或 PASS 标记。新增 Python 三项通过，涵盖 RGB 与原文件保留、冲突拒绝、既有 RGBA 来源说明。

初版特写探针只输出 Dust II 三张，因为开始对局后未先返回选图，后两图的选择被运行时正确拒绝；同时原网格材质不一定等于实例 active material。`decal-before/` 与 `decal-before-active/` 及日志保留为无效三图证据。修正为每图先返回选图、断言实际关卡 ID、查 active material；新前后视角输出到 `C:/Users/Zhang/Documents/VectorBreach-builds/QA-20261018/`，减少 D 盘占用。

下一执行：完成有效三图特写与路线对照、重建/验证 Inferno 遮挡、核查 Mod2x 和工具面；验证 FPS/开局帮助实机界面，固定候选后跑完整原生、GdUnit、Python、lint/format/资产约束、实际 Vulkan/PCK 和 EXE；最终提交推送、当前头 CI/复审、合并与桌面入口更新。全图逐区美术、严格全图 70% 帧率、AI/经济/观战与 18 场完整比赛依旧开放。

## 2026-10-19 续接验证

已逐项复核有效的 43 组前后视角（Dust II 3、Mirage 8、Inferno 32）。Inferno 橙红矩形、落叶与涂鸦的透明边缘恢复，Mirage 黄色秒表带消失。三种 Mod2x 材质仍开放：`dust_mudbrick_transition_overlay`、`stain01`、`top_grime_2`；Mirage 污渍仍见矩形底色，不能把模式 1/2 的修复算作全部混合模式正确。前后图、分图联系表和坐标位于 `C:/Users/Zhang/Documents/VectorBreach-builds/QA-20261018/`。

Inferno 遮挡按工具面过滤规则重建，旧资源旁置备份 `render_occluder.res.before-helper-filter-20261019`；新资源 SHA256 `5c1f48280f74dea68a47d07f7c95b9655bd71fac4b61fc226ef220c6ea9d30d2`，58009 个三角形。生成器回归验证真实墙体、bucket_tools 和 gardening_tools 保留，三个精确工具材质、特效和贴花不进入结构遮挡，输入几何字节不变。

导出包资源通过三图 54 个路线视角和 Inferno 18 组遮挡开关对照，目视未见旧灰面复发或明显结构缺失。10 组对照逐像素相同，8 组存在像素差异；这是有限视角的目视与数据检查，不声称全图遮挡逐像素等价。路径相机以既有固定路线为基准，不能替代玩家走图或 AI 导航验收。

实际鼠标点击开始、购买页就绪，以及 F1 帮助开关、F11 绑定、实时 FPS 和提示互斥在 PCK 上通过。EXE 以独显 Vulkan 启动并自动退出 0。首次向发布版 EXE 传入外部 `--script` 未产生探针收据，只进入正常游戏；已关闭该测试进程，改用编辑器引擎加载实际 PCK 执行脚本。该失败运行不算 54 视角证据。另修复了 FPS 标签插入时遗漏金钱右对齐的问题。

完整原生 **185 项**、`RUN_ALL_OK`，无 `SCRIPT ERROR` / `ERROR:`；GdUnit **2/2**；Python **10 项**；Blender morph/arm 导出回归通过。资产层级、元数据、运行时合同、9 个 GLB 验证和资产预算通过（既有 Dustline 49.52 MiB 模型预算债保留）。首次 Python 全目录 discover 因 `bpy` 需要 Blender 失败，已按普通 Python 与 Blender 实际运行环境分别执行。开局帮助旧断言失败后，改为验证默认收起、F1 往返和退出设置不自动展开，并完成新全套。lint/格式检查同时保留基线已有问题，检查本片不新增；材质测试夹具独立存放，避免继续扩大旧 runner。

候选包目录为 `C:/Users/Zhang/Documents/VectorBreach-builds/VectorBreach-performance-20261018/`。最终包哈希、逐图帧率、提交与远端状态以私有证据目录 `D:/AgentGamePipeline/evidence/inferno-orange-decals-20261018/` 的收据为准；本段不表示已完成 CI、复审、合并或切换桌面入口。

包级探索采样（各 40 秒，统计末 35 秒，实际纹理/PNG 均 2560×1600，原生 scale 1.0、MSAA 2×、VSync 关闭、插电、全程聚焦、AI 继续运行）：Dust II 防守/进攻平均 238.82 / 242.92 FPS，Mirage 133.01 / 75.95，Inferno 60.86 / 144.28。Mirage 进攻、Inferno 防守未达临时 105 FPS。Dust II 末帧仅剩 7 个 AI，其余样本为 9 个；不是全员存活的统一压力测试。旧 `formal-final-inferno-CT.png` 朝向教堂墙面，新样本朝向庭院，不能将两份平均直接作为修复前后性能回归结论。为消除鼠标输入和方向差异，后续收据改为锁定玩家朝向、阻止鼠标改变相机并记录相机起止变换，输出 `locked-*.json` 与 `locked-performance-summary.json`；这些仍只证明出生视角抽样，不能关闭全图/整场性能项。

本片允许继续制作可审查候选与草稿 PR；只有当前头 CI、干净复审和最终包验证闭环后才更新桌面入口。后续最小执行片：先核对锁定相机样本与慢区 CPU/GPU 数据，再处理 Mod2x；完整资源缺口、AI 协同/残局、更多武器与经济、死亡观战、18 场自动完整比赛和三图连续试玩继续按完整比赛契约推进。
