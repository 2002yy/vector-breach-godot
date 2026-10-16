# 经典新图与换肤操作验证

基线 main `2123f615e45afa6293a3032e467fcd433ed3ffaf`；工作分支 `feature/skin-ui-new-classic-map-20261016`。开始时工作区干净。用户授权继续开发、提交、推送及合并。

## 当前执行范围

- 通过真实设置控件切换角色，验证保存及第一人称原生袖子/手套，不以直接改设置代替操作证明。
- 新增炼狱小镇 Inferno、荒漠迷城 Mirage 两张本机经典研究图；目标为选图、5v5、购买/就绪及双爆点。
- 参考来源为 `sliuhaob/mirage-utility-lab`，固定版本 `776f381d4a6e1b606190cbc9ab7430e68a03572f`。来源模型含原始地图几何、简化颜色，没有原始贴图；必须明确标为重建材质，不能称为官方完整材质版本。
- Valve 派生资源和坐标仅本机保存，不提交公开仓库。公开代码保留可复现转换、加载及验证工具。
- 碰撞和路网由关卡 JSON 显式授权并冻结哈希；不在运行时自动重写路线，不修改共享玩家移动规则来适配地图。

## 实现与来源边界

- 新增 `inferno-classic-local`、`mirage-classic-local` 两个游戏组入口。玩家加四名队友对五名敌人，购买、就绪、双爆点及现有回合/经济系统接通；缺少本机资源时不展示入口。公开 headless 测试继续只枚举随仓库提供的地图，实际本机地图用独立 Vulkan 探针验证。
- 两张视觉保留原有全部三角面：Inferno 5,432,159；Mirage 934,959。Draco 通过 Blender 解码，不对视觉几何减面，依据来源坐标变换换算为每 Hammer 单位 0.0254 米。来源没有原始贴图；使用已有 CC0 混凝土等材质的三平面重建，保留原材料颜色分类，未冒充官方完整美术。
- 最初把所有可见装饰当作碰撞并套用粗格路网，无法连通双爆点，该方案没有开放为可玩入口。最终物理来自 [Awpy 2000933](https://github.com/pnxenopoulos/awpy-data/releases/tag/2000933) 的地图 world physics 简化结果，下载包 SHA-256 `e1730a90200a2bacffe6d0d1984d31dc038c52faae91366564403a59b9e9e7f5`。它是近似物理，不能宣称逐面完全贴合视觉。转换使用视觉元数据同一坐标系，未凭空铺设整图地板。
- 两图显式离线 Recast 烘焙，保留凸多边形中心和共享门户，筛出双方出生点及双爆点所在的连通分量。冻结后分别为 9,841 / 9,837 个节点；关卡 JSON 与碰撞原始字节绑定哈希，运行时不重新生成路线。旧 Dust II 仍使用原有冻结基线。
- 真实设置控件可选择两方外观，第一人称装入相应两条原生蒙皮手臂；AI 沿用六套原生全身角色。设置页新增说明，不把下拉选择称为独立 3D 试衣间。
- 暂停菜单新增“结束当前对局，返回选图”。可继续比赛时锁定选图及开发地图开关；主动结束后恢复选图，下一张从新比赛开始。
- AI 共用碰撞检测抬步，最大 42 厘米，与玩家相同；高掩体、低顶及其他角色继续阻挡。密集路点从 JSON 读取 `arrivalRadius`，新门户为 22 厘米；旧路网默认半径保留。没有新增地图专属玩家移动分支。

## 验证与可玩边界

证据根目录：`D:/AgentGamePipeline/evidence/classic-maps-ui-20261016`。

- 实际输入事件点击设置按钮、两方外观下拉框、地图、阵营、开始与就绪；两张图均验证九名 AI、5v5、购买阶段、点击就绪和原生第一人称双手。`ui-verified/ui-receipt.json` 失败列表为空。后续 `observed-steps`、`inferno-full` 使用同一操作流程并附带自然局记录。
- 改造前 60 秒观察中，两图均无交火，单个 AI 最高脱困 24 次。修复后 Mirage 防守视角 60 秒累计 26 次 AI 出手并进入 Bomb Planted，最高脱困 1 次；Inferno 防守视角 110 秒累计 55 次出手并进入 Round End，最高脱困 4 次，未观察到安装。Inferno 玩家持包且原地不动的 60 秒记录不作为 AI 进攻安装证明。
- 原生 176 项：`RUN_ALL_OK`；GdUnit 2 项，无错误、失败或孤儿。新增回归覆盖具体台阶跨越与高掩体阻挡、密集门户不提前跳过、每图冻结清单选择及资源变更拒绝、暂停后真正返回选图。
- 资产分层、元数据、运行契约、9 个公开 GLB 验证通过；新 Python Ruff 检查与格式通过，新 GDScript 格式通过，Godot 实际解析/运行无新语法或类型错误。GDScript lint 保留基线同位置的 `enemy_team` 未使用参数诊断，比较基线与候选均为同一条；其他修改文件无 lint 问题。
- 聚合及单独 verbose 的 MainStateFlow 在 44 项通过后出现已记录的退出诊断：4 个音频对象 / 2 个资源仍占用。此次 verbose 定位到 `concrete_02.ogg` 的 Vorbis 播放对象；不宣称已修复，也不把它当作测试断言失败。Windows 实际 EXE 正常入口 smoke 退出 0；导出包的真实 Vulkan 操作结果及日志在本机证据中保存。
- 仍开放：原始贴图取得、专门的逐区正式美术与碰撞接触检查、全部路径/长局 AI、完整人工比赛和平衡。自动截图及短局不替代用户验收。

## 重建与交付

本机源：`D:/AgentGamePipeline/reference-assets/cs-maps-20261016`。保留固定来源、取得哈希、两图 `local-layout-hints.json` 和转换收据。原始坐标仅在该本机提示文件与被忽略的关卡 / 路网 JSON 中保存。

```powershell
python tools/acquire_local_classic_maps.py --output '<private-reference-root>'
& '<Blender>/blender.exe' -b --python tools/blender/convert_local_classic_map.py -- --source '<map-native.glb>' --output 'assets/local_reference/classic_maps/<map>/map.glb' --source-scale '<metadata sourceToWebScale>'
& '<Blender>/blender.exe' -b --python tools/blender/convert_local_classic_collision.py -- --physics '<de_map.mesh>' --metadata '<map-native.json>' --output 'assets/local_reference/classic_maps/<map>/collision.glb'
python tools/prepare_local_classic_map.py --map '<inferno or mirage>' --hints '<local-layout-hints.json>' --metadata '<map-native.json>' --output 'data/levels/<map>-classic-local.json'
& '<Godot>/Godot_console.exe' --headless --path . --import
& '<Godot>/Godot_console.exe' --headless --path . --script tools/author_classic_match.gd -- '<map>-classic-local'
& '<Godot>/Godot_console.exe' --path . --rendering-method forward_plus --rendering-driver vulkan res://scenes/tests/ClassicMapsUIProbe.tscn -- --observe --evidence-dir '<evidence>'
```

关卡与冻结文件工具拒绝覆盖已有基线，需先保留并审阅新输出。导出完整包必须额外带原始碰撞字节：既有 `assets/models/dustline/dustline_depths.glb`，以及两张新图的 `assets/local_reference/classic_maps/<map>/collision.glb`，保持冻结哈希校验。

私有完整包目标：`D:/AgentGamePipeline/builds/VectorBreach-classic-maps-20261016/VectorBreach.exe`，EXE / PCK / assets 必须一起保留。最终提交、PR、远端精确 SHA 的 CI、合并、打包校验和当前交付状态统一记入证据根目录 `delivery.json`。下一执行片是核对该收据、试玩两张图，并按实际反馈继续完善材质及剩余局部脱困。
