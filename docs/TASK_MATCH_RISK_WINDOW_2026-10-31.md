# R50 比赛风险片段证据提取

新增extract_match_risk_window.py，逐行读取标准trace并同时计算整文件SHA，不加载整场到内存、不改源trace。按serial和闭区间frame_start/end选取，保留原帧/回合、C4状态/位置、死亡/观战、最近三个活T的实际位置/距离/状态/原因/导航节点/阻塞/停滞/可见与受伤年龄。最近者不是租约持有人；标准trace没有lease字段，工具不会推测。carriers原样取ai.bomb_carrier，不因掉弹或死亡修饰数据，不能仅凭残留标记认定物理携带。下一行采样独立保留serial，可能已换回合。

参数错误、无匹配样本、帧顺序重复/倒退会拒绝；仅跳过标准round_ended事件行。输出使用独占创建，拒绝覆盖已有证据。三个定向测试覆盖最近者与carrier不同、死T/CT排除、跨回合下一样本、空窗口/错误区间/乱序拒绝、EOF不伪造下一样本、SHA绑定。

真实演示dust-T-1701，serial7、33300–34800：26样本、25秒跨度；原trace SHA为4326a82f4513061fdaa6469fa0652594d0d35f1e2a29e4725ac8f2b1551bd960。最近活T距弹50.416→5.189m，下一34860帧carried、ai.bomb_carrier为防守队员4（换边后实际T）。整个窗口玩家死亡且观战active；不能叫25秒静止等待。首样本掉弹状态下仍有旧actor的carrier标记，工具保留这种不一致而不推断所有权；分析以实际c4_state与邻接采样为准。

证据D:/AgentGamePipeline/evidence/r50-20261031/input/dust-T-1701-risk33300-34800.json。这里只是该首场风险窗口，不替代18场总验收，也不证明路线必要性、连续碰撞、精确拾取瞬间或观战视觉。未运行Godot、未改生产/原资产/参数。

## Mirage 携弹超时定向窗口

权威Mirage已完成场逐场提取最长掉弹/死亡活动片段和TIME最后10秒，索引在r50-20261031/risk-windows/completed-risk-index.json。文件流式绑定各场SHA；索引只覆盖运行脚本时已完成的场次，不是最终矩阵。

额外选择Mirage-T-1702第3回合，全Live每五个采样（约5秒）加目标切换/最后采样，保留position/site/target/nav/state/reason/remaining，文件mirage-T-1702-round3-carrier-5s.json。唯一观察到的目标切换为16860帧、余64.6秒、A→B，携弹者始终进攻队员1；此后65样本均OBJECTIVE，采样移动下界110.316m，无相邻位移<0.05m，导航节点357→272。20700帧余0.6秒仍carried、位置(-0.526,0.393,35.440)，目标(-32.154,1.045,-29.133)。没有证据称该段静止、无路或无限反复转点。

静态交叉：TacticalBotBrain._tick_t_side_objective以_rotated_site限制一次转点、要求剩余>40秒，敌情距原目标<10m且actor距目标>12m；局部受阻分支剩余>20秒可改点，但同样受_rotated_site限制。没有以实际路线成本、合理预计时间及安装余量评估转点。下一修复候选是携弹转点的路线/时间预算与执行进度策略；先冻结实际触发报告、目标与导航图成本作定向反例，不能仅凭最终节点数或自动超时比例断言根因。未修改生产策略。
