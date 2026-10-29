# R43 完整比赛自动化与有界运行

基线19291ac。既有18场整场证据在`match-systems-20261019/full-match-rollup.json`：191回合，来自v5/v6混合历史版本，不能充当当前生产树18场通过。原合同仍要求三图×双方×三个种子，不改变真实赛制和回合时钟。

本批实际运行当前源码`tools/run_match_acceptance.gd`：Dust II、T、seed1701、headless、固定60Hz，九个真实AI与静止人类，真实准备/丢C4/暂停恢复/结算流程，wall预算120秒。到预算主动结束自有进程，结果严格为`wall_timeout_incomplete`，qualified_complete=false，没有result.json，不能计为完整比赛。日志记录6回合结束（5歼灭、1超时）；逐秒trace完整保留到31380物理帧（523模拟秒），末尾未刷出的日志/trace差异不补造。未证明完整半场/换边/加时、结算或长期经济平衡，也不是人工试玩。

证据：`D:/AgentGamePipeline/evidence/dust-release-audit-20261029/matches/dust-T-1701/{run.json,process.log,trace.jsonl}`。执行前后脚本/数据/场景源文件sha一致，用户settings.cfg哈希一致，未恢复或覆盖设置。该样本是来源指纹观测，非正式包/最终HEAD18场；本批未改生产AI或游戏规则。

新增`tools/authoring/run_bounded_full_match.py`，要求全新输出目录，记录HEAD、命令、源文件前后sha、wall预算、退出码、设置前后sha。最终版本还将实际执行的`tools/run_match_acceptance.gd`纳入指纹，并核对结果level_id/initial_player_team/seed与请求一致；本次120秒原样本早于这两项加固，其run.json不追写伪造身份。未来只有正常退出、无引擎错误、来源不变、完成marker、结果存在且规则检查完整才计complete；timeout永远incomplete。仍不把此作者工具当作完整结果真实性或人工可玩验收。

聚焦3项资格门闸测试覆盖超时旧结果、零退出引擎错误、缺少规则证据、源变化及请求身份不符。Ruff F/格式与Pyright通过。无生产变更，无需重复原生全套。下一步在冻结的生产树对三图双方种子串行安排足够wall预算；保留每场原始trace并分析卡路、无人处理C4、经济与死亡等待，不以快速短局或仅完整计数代替诊断。

## 完整样本追加

最终加固wrapper另以480秒wall预算运行Dust II / T / seed1701，实际186.676秒正常结束，942.25模拟秒，12回合、换边、最终5:7，暂停恢复/结算菜单/主场景检查通过。10回合歼灭、1拆弹、1爆炸，钱范围0–14200。运行前后源文件与实际harness指纹一致，设置字节未变。日志有两条观战Camera3D物理插值warning，单列后续观察；非引擎ERROR。证据`matches/dust-T-1701-full/{run.json,result.json,trace.jsonl,summary.json}`。

这才计一场完整自动样本，仍不覆盖三图×双方×三个种子的18场矩阵。静止玩家的死亡等待、实际卡路和经济平衡必须另看trace，钱范围合法不证明无滚雪球；headless进程FPS不代表Vulkan帧率。最终资格函数额外核对phase=complete、team_size=5及回合记录数等于regulation_rounds+overtime_rounds，可直接重验真实结果，无须为此重跑Dust。

后续串行扩展已完成，未改回合时钟或生产逻辑：

|地图/初始阵营/种子|wall秒|回合/比分|结束原因|
|---|---:|---|---|
|Dust II / T / 1701|186.676|12 / 5:7|10歼灭、1拆弹、1爆炸|
|Mirage / CT / 1702|322.618|14 / 6:8，含2加时|6超时、1拆弹、7爆炸|
|Inferno / T / 1703|286.335|8 / 1:7|6超时、1拆弹、1爆炸|

三份真实结果均qualified_complete=true，实际harness/源文件指纹稳定、设置不变，覆盖换边及Mirage加时。三图各一个完整自动样本，不等于已完成既定双方三种子的18场矩阵；本批种子需在后续矩阵清单中明确，不将历史混版样本填入。机器预算终止的早期短样本仍不计完整场数。汇总位于`matches/complete-summary.json`。

**P1待复现候选：Mirage第3回合掉弹无人回收。** 最长71个连续一秒采样处于Live，C4固定(12.85581,0.698246,22.95485)，剩余74.18到4.18秒；T存活4→3人，所有存活AI均非携弹者，中段持续报告“跟随携弹队友协同进点”。末最近T距C4约2.38m，另6.07/11.67m，route_points均0，部分原因变为“当前无可达路线”或“局部往返未推进”，最终CT TIME。排除全灭与回合间隙，但欧氏距离不能证明实际可达，因此下一步复现掉弹角色重分配与导航资格，不能立即归因为某个算法缺陷。证据`mirage-CT-1702-full/longest-drop.json`绑定前中后帧及回合结局。

三图最长“玩家已死且回合仍活动（Live/Bomb Planted）”连续采样为48/32/0秒；AI资金范围分别0–14200、0–10850、50–12850。route_stalled_seconds峰值3.57/5.00/4.98秒只是重寻路诊断值，不足以断言卡死。Inferno6个超时回合与1:7比分同样值得后续路线/目标处理调查，不用资金范围或完整结束掩盖问题。此批先交付真实复现线索，未宣称无经济滚雪球、无死亡等待或平衡通过。
