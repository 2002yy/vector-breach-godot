# 地图视觉资源后台读取

基线 `1c7be484198c8dd24706f9d64387064cdc658ce7`（#82），分支 `feature/threaded-map-visual-read`。前头 Tests 40077149926、Windows 40077149929 全成功。当前 PR 目标 main，包含前序已提交加载优化，不等待新 CI。已验收试玩包仍为 main 598cde1，本片不覆盖。

上一批三图主视觉资源读取约 8–12 秒，实例化约 17–31 ms。参考 [Godot 官方后台读取说明](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)，SceneReader 使用后台请求，逐帧查状态，进入终态后取回结果。实机 Godot 4.7.1；串行处理、禁用额外子线程，同路径合并，返回各自收据。任务完成后移出队列，不保留常驻资源；等待者或关卡销毁仍排空原生请求。

Main 仅开始后调用新 load_level_async，旧 load_level 仍同步。先执行原碰撞构建并释放其网格，再读取主视觉，避免同时预载碰撞与视觉。实例化、材质修复、批处理、覆盖层和角色继续在主线程。等待窗口 game_started=false、RoundManager Warmup，避免旧对局倒计时继续推进。代次变更或退出后丢弃旧结果，不附加旧节点、不发布就绪、不覆盖新统计。选图不提交后台请求。

scene_layers.LevelVisual 的 resource_ms 为共享作业排队到取回的墙钟时间，合并请求沿用该作业计时；level_ms/visual_ms 则是关卡调用本身的墙钟。request_ms/get_ms 单列，thread_wait_frames/thread_wait_max_gap_ms 记录作业等待期间 process_frame 的次数和最大间隔。这不是 GPU 帧时间，不覆盖碰撞、材质或候选上传；嵌套时长不能重复累加，统计不保存 Resource 指针。

本次普通入口：Dust II 等待 2018 帧、最大采样间隔 59 ms；Mirage 1850 帧、16 ms；Inferno 2733 帧、69 ms。请求和最终取回均小于 0.3 ms，资源墙钟仍约 7.8–11.7 秒。只说明该段读取期间主线程能继续运行，不宣称整体提速或最长帧达标。

聚焦覆盖请求合并、多路径排队、缓存命中、独立收据、等待者销毁、无常驻资源、缺路径、过期结果拒绝及关卡销毁后排空。Main 覆盖选图零请求、开始一次、Warmup 窗口、分帧角色和失败重试。初稿类型推断错误、把 Gatehouse 正常视觉误判为旧视觉的断言失败日志保留，修正后聚焦通过；严格扫描 SCRIPT ERROR，不能只看 PASS。

失败路径复核发现 FAILED 也持有原生用户令牌，必须调用 get 释放；[Godot 实现](https://github.com/godotengine/godot/blob/master/core/io/resource_loader.cpp) 和本机状态探针均确认。初稿失败后状态停在 FAILED，修复后为 INVALID，损坏的原生 .tscn 修正后同路径重试成功且退出无泄漏。失败收尾是运行时代码修复，因此重新跑最终完整原生；旧日志保留为 native-before-failed-token-fix.log。六次 Vulkan 成功路径的 get 条件在前后均为真，成功路径无变化，复用已通过的画面证据；另加永久的失败令牌/重试聚焦回归。已知损坏文件的原生错误仅在该孤立用例读取时暂时屏蔽，随后立即恢复，再作断言。

最终完整原生 **214**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；三图双入口 **6 次 Vulkan、126 PNG** 通过，Mirage 购买页已检查。失败清理修复后的原生损坏文件/同路径重试及永久聚焦回归通过，正常视觉成功路径复用已通过收据。

证据：`D:/AgentGamePipeline/evidence/threaded-map-visual-read-20261024/`。结果见 audit.json，提交和 CI 首次快照见 delivery.json。原资源、碰撞、四个脏导入和用户设置保留。最新头 18 场、人工连续三图与 70% FPS 待验。下一片优先剩余碰撞长帧/候选上传，再推进 C4/观战和 AI。
