# R27：独立Modern垂直积分作者候选

基线 `3caa475eb6a95f644ea8eb19447f04182d1faa02`，正式Current/Modern、原地图和R25/R26探针不修改。候选仅通过 `audit_modern_vertical_quadrature.gd` 启用，不增加正式设置或试玩菜单。此前三图残差指向垂直积分/贴地采样，但该归因不是原版客户端手感或精度验收。

## 冻结实现合同

沿用V2水平积分，新增独立 `ModernVerticalQuadraturePlayer.gd`。仅 `vertical_enabled=true`、Modern、允许移动、无梯子/水体时采用恒定重力的kick/drift/kick：

- 起跳物理区间使用 `J−gΔt/2` 作为运动速度，完整结束速度为 `J−gΔt`。
- 后续无碰撞空中区间使用 `v−gΔt/2` 位移，结束速度为 `v−gΔt`。
- 通过覆盖作者采样器在原生产流程施加重力前预加半步，再在移动信号内部收尾。角色自身的信号处理器于ready先连接，因此外部观察器读取前已完成后半步，且事件字典velocity已改为真实持久结束速度。
- 地面/贴地或天花板改变垂直速度时，保留实际碰撞结果，不回接预测结束速度。没有垂直隐藏缓存，开关、切方案等不依赖缓存恢复。
- 关闭候选、Current/Legacy、禁止控制/移动、梯子、水体均执行原流程。环境资格在生产环境刷新后的输入采样阶段判定。

`vertical_sample`记录开关、阶段、Δt、重力、持久输入速度、运动速度、结束速度及跳跃冲量。生产velocity_before字段在采样后捕获，候选中其Y可能包含预加半步，故追溯持久输入用 `vertical.start_velocity_y`，不能误用该字段归因。外部事件velocity和真实角色velocity保持一致。

## 已知边界

这不是完整物理子步，也不宣称CS原客户端实现。原地面走离边缘的首帧保持原流程；没有预知何时失去支撑。台阶、贴地阈值、浮点碰撞及离散最高点仍会产生误差。落地伤害的impact_speed和相机更新仍发生在收尾前，使用实际漂移速度，不将其称为完整垂直玩法等价。水体/梯子排除是范围隔离，未改进这些机制。原生夹具的0.1mm数值容差仅用于简化自由飞行，不是地图精度放行门槛。

## 实际管线验证

新增无地图原生夹具 `test_modern_vertical_quadrature.gd`，实际实例化胶囊角色并调用父级生产物理流程，**26断言通过**：

- 60/120Hz自由飞行位置与结束速度符合恒定重力解析解；相同1/3秒结束位置一致。
- 外部信号观察器读取的结束速度与真实角色一致。
- 关闭开关、切Current、禁用移动/控制排除候选。
- 真实地板支撑后输入跳跃，起跳当帧两半步执行；真实天花板阻挡，接触后不恢复向上速度，真实落地归零。
- 真实Area传感器检测水体/梯子，保留原垂直规则。

Python原生包装 **1/1通过**，进入现有 `test_m*.py` CI发现路径。GDScript格式/lint及Python格式/F、Pyright通过。初次夹具因Variant推断duration失败，修为显式float；失败日志保留，新夹具通过后不重跑无关完整原生套件。

完整地图对照由[垂直候选地图工具](../tools/vertical_candidate_map_audit.py)分别冻结水平ON+垂直OFF与水平ON+垂直ON，避免把水平修复混入垂直效果。原始报告、首落差、失败与放行边界由整合主线另记。Movement-4未验收、Movement-5冻结。

复核：`python -m unittest tools.tests.test_movement_vertical_candidate`。最终26断言独立日志 `D:/AgentGamePipeline/evidence/vertical-candidate-fixture-v3.log`；初始失败及20断言阶段日志保留，未覆盖。整合完整Python日志再次记录包装测试结果。
