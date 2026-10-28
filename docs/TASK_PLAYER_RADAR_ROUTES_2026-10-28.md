# R37 完整Player与雷达楼层记录

基线 `f8cda2d`。新增作者入口 `tools/authoring/probe_player_radar_routes.gd`，读取本机 `movement-current-observation-20261028/v1/*-current.json`，每图仅回放冻结清单首个点的既有输入，不搜索或修改路线。使用完整Player.tscn与Current，原碰撞由GrayboxLevel的既有运行时碰撞构建器创建；不加载地图视觉或比赛AI。雷达层号调用生产nearest_layer/floor_sample，未验证异步纹理展示。

实际三图各180个movement_step，共540帧，delta全部1/60秒；每图一次起跳，结束时均着地。记录胶囊真实脚底、接地、位置、层号、原输入时间线、目标及最终水平距离，绑定清单哈希、原碰撞和Player等清单已有runtime哈希。创建Player前等待3个物理tick，输入在更早physics priority消费。

| 图 | 楼层范围 | 末尾水平目标距离 | 首/末脚底高度 |
|---|---|---|---|
| Dust II | 2–3 | 1.147m | 0.270→0.690m |
| Mirage | 4–5 | 0.450m | -0.203→1.242m |
| Inferno | 5–6 | 1.274m | 4.103→4.681m |

以上有真实高度与楼层变化，不能将末尾距离或“脚底变化”当作冻结跳点到达验收。该入口以Input.action_press注入既有时间线，未复用原精确事件回放器/首次落点资格判定；没有执行60/120成对测试。此次明确只提供完整Player楼层诊断，不能覆盖先前Movement-4资格、人工操作感、整图可达性或三图人工试玩。

证据位于 `D:/AgentGamePipeline/evidence/radar-player-package-20261028/routes/`：最终routes.json含540帧，run.log含PLAYER_RADAR_ROUTES_OK。首次解析类型推断错误保留parse-failure.log；第一次运行忘记启用Player控制，产生空轨迹，保留disabled-controls.json/log，修复后增加非空断言并重新采样。最终gdformat/gdlint通过；没有修改Player、原图几何或既有工具。

本机运行使用外部Node场景绑定新脚本（避免SceneTree直接预加载autoload编译问题），`--headless --fixed-fps 60 --scene <外部probe.tscn> -- <冻结清单目录> <新的输出json>`。入口拒绝覆盖输出。后续应复用原事件回放与首落点判定来复核这些参考动作的达标证据，并在实际纹理与完整比赛场景里核对楼层可读性；这次不据此放行Movement-4/M5。
