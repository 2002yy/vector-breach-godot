# Inferno 性能第二片：密集路网查询

## 执行契约

用户继续要求优化 Inferno 34 FPS。前一片原材质、遮挡剔除与太阳级联已通过 PR #42 合入 main `1e7e9c82119b2b4f6411651f55e33dbb280942ac`。本片分支 `perf/classic-navigation-queue-20261017`，开始时工作区干净，保留全部原包、可玩包及私有证据。

前片正常速度 CT 样本中位 69–71 FPS、T 112 FPS；后续逐帧观察发现约 0.65 秒一批的 100 ms 长帧，还有 400–1000 ms 的间歇停顿。空闲复测和前台焦点记录否定了先前的打包负载解释。不能用中位 FPS 掩盖长帧，也不能把秒级停顿全部归因于寻路。

## 实现与根因证据

Inferno 的原生冻结图为 7619 点、8392 边，全体边只有 precise/arrivalRadius，实际寻路成本均为欧氏距离。九个 AI 的周期性 GDScript A* 查询和最近节点扫描会集中占用主线程。四条真实出生到爆点路径旧查询约 8–18 ms。

`BotNavigationModel` 仅在至少 256 点且所有边无 cover/danger/costMultiplier/crouch/ladder 加权时建立原生 AStar3D。普通查询和最近节点查询由引擎执行；存在实时危险事件时保留原战术加权搜索，特殊移动成本图也保留原算法。没有减少 AI、降低感知/刷新频率、删除危险区或改变碰撞、路网、武器、画质。

原生查询四条路径约 0.15–0.31 ms，比旧版快约 54–79 倍；本机四条节点序列逐项一致。一般等价成本路线上引擎可能选择另一条同成本路径，仍须通过实际连接和战术回归。初始 GDScript 二叉堆实验反而变慢（含 T→A 约 26 ms），已撤回，保留 `path-heap.log`，没有将其提交。

新增 400 点网格回归覆盖最短路、危险事件绕行及消失后的恢复、最近节点、非法目标、权重图回退与重新配置时丢弃旧拓扑。

## 验证和交付

证据根：`D:/AgentGamePipeline/evidence/inferno-performance-20261017/`。`path-before.json`、`path-native.json` 保存实际路线和耗时；`frames-focus.json`、`frames-native.json` 保存前台窗口逐帧耗时。后者属于固定 CT 视角自然 5v5，不能替代全图跑动和 G2 长局人工验收。

默认显示设置再次复测 `frames-native-default-repeat.json`：舍弃前 5 秒后平均 89.53 FPS、99 分位帧耗时 14.495 ms；对照 `frames-focus.json` 为 70.35 FPS / 82.686 ms。7 秒时读回并保存截图造成唯一约 383 ms 长帧，采样文件如实保留；周期 0.65 秒的约 100 ms 长帧未再出现。没有将无垂直同步的诊断成绩当默认成绩。

异常样本也保留：`frames-native.json` 曾出现持续约 1 FPS，其他旧样本有秒级停顿；关闭 AI 的对照也出现过。窗口焦点始终前台，未建立秒级异常的完整根因，不能仅凭后一次顺畅运行声称所有停顿都已修复。新包仍需原设置再次实际测量。

Bot 焦点 31 项已通过；完整生产候选再跑一次全套原生、GdUnit、GDScript lint、差异/资产策略检查，以及源码和导出包 Vulkan 复测。最终数字、精确 CI run/event/head、审阅、PR/main、包 SHA 与工作区状态写入 `D:/AgentGamePipeline/evidence/official-classic-maps-20261017/delivery.json`，避免将运行中状态误写为已交付。逐帧探针为证据根的 `frame_times.gd`，以 `--script <绝对路径> -- <输出json>` 运行，原命令无 `--disable-vsync`、无 `--max-fps` 覆盖；将截图移到观测期后可消除一次工具读回长帧。

当前边界：实时危险权重仍走脚本搜索；秒级长帧需要与原生查询收益分开判断。下一片聚焦剩余长帧的逐帧根因及双方多回合人工比赛。

## 已合并候选与三图统一采样

PR #43 候选 `48e7a3418592a21db5ea5caf6019b3cd7bd90172` 已合入 main `8a11e49e389585f29f871f5bafcb9cad23feba99`，两者树完全一致。完整原生 179 项 `RUN_ALL_OK`、Bot 31 项、GdUnit 2/2、增量 lint 均通过；PR 精确头 Tests run `39019667696` 与 Windows Export run `39019667802`（含实际 export/smoke）成功，自动代码审阅在该候选上 completed / 无发现。合并后 push CI 结果写入交付收据。

同一导出 PCK、RTX 5060 Laptop、Vulkan Forward+、1600×900、默认显示设置、CT 出生固定视角自然 5v5；每次采样 40 秒、剔除前 5 秒，截图在采样后保存，无超分/帧生成覆盖。以下均为实际逐帧耗时计算的平均 FPS，不能混用此前每秒 FPS 样本的中位数：

| 地图 | 平均 FPS | P99 帧耗时 | 最长帧 |
| --- | ---: | ---: | ---: |
| Dust II 原始材质 | 191.31 | 13.968 ms | 36.826 ms |
| Mirage 原始材质 | 107.72 | 17.398 ms | 44.980 ms |
| Inferno 原始材质 | 76.68 | 17.662 ms | 36.545 ms |

三次有效样本均全程前台，未见超过 50 ms 长帧。Dust II 第一次多数失焦的 236.56 FPS 样本保留，未用作表格成绩。Inferno 另一次同包平均 80.97 FPS / P99 20.009 ms，但焦点混合，也单独保留；不择优当统一成绩。证据 `three-map-performance.json` 与三个 `frames-*-comparable.json`，Dust II 使用 `frames-dust2-focused-repeat.json`。三次固定出生视角不代表全图移动、交火或长局最低帧。

### 原版性能参考和下一步

[PConline 自测](https://www.sohu.com/a/916461333_223764)在 RTX 5060 Laptop / R9 7845HX、1080p 最低画质的 CS2 创意工坊 fps Benchmark 得到平均 468.2、1% low 152.9 FPS；这是另一台 CPU/功耗、另一画质和场景，不是本机三张图的对照，且该段未逐项披露 FSR 状态，不能当作已确认的原生同条件目标。[HowManyFPS 的公开实机记录](https://howmanyfps.com/benchmarks/counter-strike-2/6a1a1ea4451a6fc4b8310a39)虽为 5060 Laptop、平均 180 FPS，却明确 FSR Quality，排除出原生比较。没有用 FPS 估算器数据代替实测。下一步应在本机原版 CS2 固定路线、相同分辨率、明确关闭 FSR 和帧生成后采样，才能计算可靠差距。

参考 Valve 的 [VVIS / PVS](https://developer.valvesoftware.com/wiki/VVIS?uselang=en) 与 [静态道具优化](https://developer.valvesoftware.com/w/index.php?title=Prop_Types_Overview&uselang=en)：先按空间分区减少不可见提交，再在区域内部合并相同材质、复用实例和 LOD，控制阴影提交。当前 glTF 原网格导出没有继承 Source 的完整可见性结构，已有遮挡剔除仅是第一步；当前 Inferno 仍有数千次绘制提交，继续优化空间明确。不能直接把 Source 1 PVS 数据当作 Source 2 关卡的可用分区，下一片须检查本次原包实际可见性数据、保留碰撞/路网，并做逐区无漏面与帧耗时对照。

仓库整理和原版人物/装备取得边界见 [资源与仓库整理记录](TASK_ORIGINAL_EQUIPMENT_CLEANUP_2026-10-17.md)。
