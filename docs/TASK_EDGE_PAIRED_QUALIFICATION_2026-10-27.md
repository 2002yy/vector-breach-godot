# Movement-4 并行分线：三图边缘配对控制和当前身体通道

基线 `ef5427cc37c8f7eed052115e5e1c3d23d329eca7`（#121），与本批主线并行实施。只改作者Python、观察runner、测试和本文档，不改玩家/Current/三方案参数、地图几何/原资产/UI，不合并、不发包。

## 本次关闭的缺口

R20/R21保留的三图边缘参考分别为Current `reverse_hold`、Legacy `reverse_010`、Modern `brake_2`。原先制动输入和R17向前走落不配对，Dust II/Inferno后来又换过起点，因此不能借旧通道给新参考补资格。

本次先冻结三图各三方案 × jump/no_jump/站立walk共27条时间线，再执行60/120Hz **54次实图回放**：jump逐事件保留原R18/R19输入；no_jump只删Space；站立walk删Space/Ctrl并加Shift。方向、制动/恢复时刻、原几何/容差/时长保持。新runner沿用正式玩家与原预排队采样，同时按当前实际起点/目标生成站姿1.8m、半径0.4m、四弧完整分段身体通道，不改碰撞。

- **18/18跳跃首落通过**，且全部完整物理/输入轨迹与R18/R19对应原记录逐值相同。
- **新配对控制22/36到达**：no_jump为18/18，站立walk为4/18。因此连新制动控制本身也不能支持“必须跳跃”结论。
- 三图双档共 **6份当前几何身体通道全部clear**；三个方案同一几何各自绑定报告。Dust II/Inferno新起点缺通道的缺口已关闭，Mirage也重算当前点。
- **9组三方案的`paired_input_route_status`和`geometry_role`均为`walk_only`**。这关闭证据缺口，不增加必须跳跃覆盖；动作13/15、跳跃通路7/15保持。

聚合器同时保留R17同一冻结几何双档的独立向前走落事实，另锁其清单/报告SHA。即使将来的制动控制失败，也不能把已验证可走的几何角色升级为必须跳跃。新增`paired_input_route_status`与`geometry_role`分开记录，不修改旧门闸或旧证据锁。

## 验证和一次启动失败

新增 **9项聚焦回归通过**，覆盖保留原输入、配对制动时刻、站立walk去Ctrl、错模式/错几何/重命名类别拒绝、旧走落事实不得被制动失败抹去、单档走落不能代双档。Ruff F/格式/编译、Pyright **0错误**；GDScript通过缓存gdtoolkit格式/lint。普通完整套件由本批主线统一执行，不重复跑。

Dust II两档按原headless路径完成。Mirage60首进程只输出引擎头即退出4294967295，无报告、无脚本错误；当时可用物理内存约0.6–1GB，但提交空间尚余约8GB，**不能定因为OOM**。保留失败日志，只对缺项换`--single-threaded-scene --rendering-method gl_compatibility`重试成功，其余缺项沿此路径完成；没有重复Dust II、没有关闭用户应用。三图六份报告均有完成标记且无脚本/引擎错误，实际物理基线逐值一致，因此没有把渲染/线程参数变化当作物理修复。

工具：`python tools/edge_paired_qualification.py freeze|verify <R20源配置> <新证据目录>`。新runner为`tools/authoring/audit_edge_paired.gd`，仅生成作者报告；冻结矩阵和独立向前走落context锁均拒绝不同内容覆盖。原坐标和54次完整记录在 `D:/AgentGamePipeline/evidence/edge-paired-qualification-20261027/`，仓库只存 [无绝对坐标摘要](evidence/edge-paired-qualification-20261027/summary.json)。

人工/原机、精确落点/稳定停住、完整出生路线、其他助跑类别、AI/18场/连续三图/70%FPS仍待完成。Movement-4未验收，Movement-5冻结，正式包不更新。主线继续定位Modern约14mm入射位置差并验证独立候选，本分线不改其文件或全局状态文档。
