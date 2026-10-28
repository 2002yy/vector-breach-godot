# R36 三图真实碰撞与楼层采样

基线a1d090d。新增独立 `tools/authoring/probe_radar_floor_routes.gd`，从原始碰撞GLB完整层级生成trimesh，保持世界变换；不修改原版几何、Player或派生PNG。每图只在冻结spawnHints周围±4m网格射线取样，选择最多2条相邻高差边；无高差时明确使用平地对照。真实1.8m×0.3m胶囊每条走90物理帧，保存实际脚底、接地和雷达层号，绑定原碰撞/关卡SHA256。

本机证据：`D:/AgentGamePipeline/evidence/radar-layer-streaming-20261028/floors/routes-v2.json`；首轮`routes.json`保留。三图串行原生运行成功，`RADAR_FLOOR_ROUTES_OK maps=3`，格式/lint通过。初次类型推断错误已修复为显式String，未产生运动结果。

- Dust II：限定采样区没有合格高差边，也没有可用平地对照，0条实际轨迹，保留为空结果，不算该图楼层验收。
- Mirage：50条高差候选中选2条；实际脚底变化约0.53m/0.47m，第一条雷达层4→5，第二条保持4，最终距目标约0.009m/0.018m。
- Inferno：40条高差候选中选2条；剩余距离约1.112m/0.324m，脚底仅变化约2cm，层2保持。原始阻挡/部分通过保留，路线仍未证明。

此胶囊夹具没有Player台阶、输入、急停、跳跃和完整碰撞处理，Inferno阻挡不能归因为玩家移动缺陷；未证明完整地图可达性。仅调用雷达纯楼层选择/空中采样规则，不验证异步纹理显示。仍需真实Player冻结路线、上下楼边界与人工三图实走。不是人工试玩、不是18场比赛或70%FPS验收。

复跑：Godot `--headless --path <工程> --script res://tools/authoring/probe_radar_floor_routes.gd -- <新的外部JSON路径>`，禁止覆盖旧结果。
