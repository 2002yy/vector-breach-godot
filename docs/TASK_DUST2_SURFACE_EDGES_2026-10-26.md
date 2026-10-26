# Movement-4 R13：Dust II 表面种子与走落

基线 `8f62f4621f2e3e4f59bf1c3c0ecc392db883a964`（#108），分支 `audit/dust2-surface-edge-seeds`。仅作者GDScript/Python、测试和证据，原几何/资产/正式移动/UI不改。

## 新几何采样及结果

`survey_surface_edges.gd` 只读构建原碰撞，先按布局目标点，再按旧平地/落差调查点生成锚点。每锚点在XZ的-2/-1/0/1/2m固定格点投射线，列上界1024、不同表面/方向候选上界8；使用原站立半径0.4m、高1.8m和0.04m净空，水平身体通道必须清空。

同时，目标射线从当前表面上方0.15m向下投射，避免采用原 `floor_at` 向上2.5m的起点再次命中高处面。只接受低0.5–2.0m、有站立空间的落面。**本轮同时改变采样种子和射线口径，没有做因素隔离，不能将结果归因于其中一个变化。** 原R12零候选调查保持，不回写。

实际20列采样，4个有站立空间的表面、8个低处目标/水平通道通过，生成8条几何候选；按固定顺序冻结，未参考移动成绩。这里只核实站立/走落几何，表面具体道具身份和正常登台路线均未证明。

## 独立探索、选择与保留样本

- Current/60Hz下三模式（跳跃、不跳、静步）共 **24次探索**，8条均实际起跳且配对不跳身体走落。按原顺序选第一条`drop_00`，未调整起跳时间或容差。
- 在运行120Hz前冻结选择锁与源报告SHA，再执行三方案/60、120Hz三个模式 **18次回放**；**6/6动作与走落上下文成立**。
- Current/60的三个模式完整物理/输入轨迹与探索逐值一致。实际引擎循环计数、控制污染和输入/资源身份检查沿用R12。
- 角色从候选表面放置开始。`surface_accessibility=unproven`、`input_surface=placed_not_approach_verified` 始终保留；表面锚点不伪装成导航节点。原通路资格仍`not_requalified`，`edge_lip_timing_accepted`、`formal_release_ready`、`human_acceptance`和精度等价标记均为false。

## 验证和复现

普通Python **247项通过**（新增7），覆盖源/探针漂移、调查范围和策略、身体尺寸/阻断、锚点语义和保持、伪造可达性等拒绝；Python/GDScript格式、Ruff F/gdlint/编译、新文件Pyright **0错误**通过。修改R12网格构建器仅增加可选记录参数，默认行为重新验证：旧探索42+回放18的摘要除源码SHA外逐值一致。四个脏导入、用户设置、原清单/报告保持。

没有生产行为/地图/渲染改动，未重复完整原生、Blender、比赛或Vulkan；固定循环率是受控输入条件，不是GPU帧率测量。共42次新动作试验，另有一次原图几何调查，不是人工试玩。

- [无坐标汇总](evidence/dust2-surface-edge-seeds-20261026/summary.json)绑定调查、源清单、探索/选择锁/回放SHA。
- 完整原始证据/运行日志与最终头、PR、CI首查：`D:/AgentGamePipeline/evidence/dust2-surface-edge-seeds-20261026/` 的 `delivery.json` 等文件。
- 入口：`python tools/surface_edge_study.py freeze|select|verify <新证据目录> <原Dust II清单>`，verify另传新输出路径。先运行表面几何探针，冻结探索，运行Current/60原生前置队列，锁定选择后才执行三方案双档回放。

**Movement-4未验收、Movement-5冻结；不等CI、不合并、不发包。** 下一片从邻近真实地面冻结登台路线、身体通道和原生输入；能正常到达表面后再判断三图台沿时机窗口。原机/人工、精度门槛、最新头18场、连续三图和逐图70%FPS继续待验。
