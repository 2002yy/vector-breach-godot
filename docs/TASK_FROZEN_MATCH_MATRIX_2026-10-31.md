# R50 冻结比赛矩阵与采样风险审计

生产基线09592b70e33b452684d58f0559960698a6adc249，分支test/frozen-match-matrix，基于R49/#146。只增加作者工具、测试及审计文档；正式Current、原版地图、导航、资源和生产行为保持。当前桌面试玩包仍为20261031预览，runtime0a2968a，不重复导出大PCK。

## 执行与冻结边界

矩阵是Dust II、Mirage、Inferno × 初始T/CT × 1701/1702/1703。运行既有run_match_acceptance.gd：60Hz固定物理步、原赛制/回合钟、9个实际AI加静止人类，玩家每回合就绪，持弹时通过真实丢弃输入放下C4，检查暂停恢复、换边/加时、结算和观战清理。没有缩短比赛、改图、加速规则或以历史混版结果填数。Godot比赛串行，其他CPU审查并行；无前台抢焦点或用户应用终止。

审查发现旧run_bounded_full_match的fingerprint只枚举Git跟踪文件，遗漏被Git忽略的原图JSON、match-local导航/出生点清单及碰撞资产。原source_before/source_after只能证明跟踪源码不变。新增snapshot_match_dependencies.py补齐三图21文件：每图level JSON、match manifest、碰撞raw、import、compiled场景、碰撞cache资源及cache收据。严格检查原图/原碰撞SHA、导航/出生点/目标、cache身份与路径边界。缓存是实际物理输入，不能只哈希原raw。视觉纹理不属于本headless玩法快照。

第一次完整依赖快照在2026-10-31 06:50:16 UTC，此时最初六个Dust场次已启动。因此六场均保留为探索观察，不能事后补记开局前已冻结。后十二场Mirage/Inferno沿用完整快照并逐场采集结束快照；Dust另用-qualified目录补跑六场，采集真实前后快照。总计计划24个执行观察，权威矩阵仅18个唯一组合。matrix-frozen.json、初始原始run/trace不追写，最后另生成matrix-authoritative.json选择权威场次。

证据根目录D:/AgentGamePipeline/evidence/r50-20261031/matches。execution-environment.json及补充记录分别绑定console启动器和实际win64引擎。R49历史level/manifest/raw九项SHA与当前匹配，只是历史与当前字节一致，不证明早期场次没有瞬态变化。种子在每回合FREEZE检测后逐AI重设，属于固定种子策略样本，不是已证明的确定性输入回放。

## 独立结果资格与分析

analyze_match_matrix.py重新核验实际进程退出、错误日志、完成marker、完整规则结果、地图/初始阵营/种子及跟踪源码；完整18场资格还要求完整21文件依赖快照和启动前/结束后时间边界。不会仅相信qualified_complete或complete字段。支持显式--manifest matrix-authoritative.json，不覆盖最初清单。

快照observed_utc是哈希完成时间。after字段晚于完成收据只独立证明观察完成较晚，不能单凭这一字段断言哈希开始也晚于退出；after调用确在run返回之后由串行orchestrator及监控流程记录佐证，不追写较早快照的时序含义。

比赛完成、轨迹覆盖与人工验收分别输出。轨迹另查首/末采样、回合集合、递增帧、采样间隔、回合结束事件和结果逐条一致；原采样间隙保留位置及两端状态，不填造中间内容。最长掉弹和死亡活动区间按实际相邻60帧、同round serial拆段，N个连续秒级样本只表示N-1秒观测跨度。掉弹仍有活T不等于无人行动或通道可达；route_stalled_seconds不是卡路实证。

资金按实际当前阵营与人数输出首/末采样均值，明确静止人类不在AI资金中、死亡角色移除有幸存者偏差、采样不与购买/奖励同步。连胜按player/opponent squad统计，换边不改变squad身份；连胜或合法金额范围不能单独证明经济滚雪球有无。headless process FPS不作为Vulkan帧率。

extract_match_risk_window.py进一步按原serial/帧范围提取最近三个活T、C4状态、可见/受伤年龄、导航状态和相邻下一采样，绑定完整trace SHA。标准trace没有回收租约字段，最近者和残留bomb_carrier标记不能冒充租约所有者。见TASK_MATCH_RISK_WINDOW_2026-10-31.md。

## 结论与后续

本文件为执行合同，最终计数、聚合结果、未闭环风险、验证、精确提交/PR/CI及脏状态以本批delivery.json和PROJECT_STATUS最新段补齐。原生全套在无生产变化时沿用R49证据，新增作者工具运行聚焦及最终Python全套/静态检查。

本批同时确认了就绪按钮同帧输入重叠机制和雷达敌情/观战/北向朝向数据流缺口，见相应审计文档。它们尚未修复，不在冻结比赛期间修改生产。下一修复应先有真实产品失败复现，再独立改输入门闸和最后合法可见位置，按实际行为变化决定重验范围。

即使18场完成，也不是连续人工三图、Movement-4/5、AI分级、原引擎画质等价或逐图70%FPS放行。M4未验收/M5冻结保持，不等CI、不合并。

最终：权威18/18、182回合完成，总24原始场保留。三处跨回合单秒采样缺口使完整轨迹资格仍false；未宣布平衡、人工或性能通过。每图统计、缺陷、验证及精确提交/PR/CI见PROJECT_STATUS和本批delivery.json。
