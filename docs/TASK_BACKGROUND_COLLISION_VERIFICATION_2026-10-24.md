# 碰撞文件后台校验与 Jolt 定位

基线 `5ef3d32d72b07df05496dea107aea05788effc44`（#84），分支 `feature/background-collision-verification`。前头 Tests 40092648783、Windows 40092648780 全成功。PR 目标 main，组合包含前序已提交加载优化，不等待 CI。已验收试玩包仍为 main 598cde1，本片不覆盖。

Inferno 分段探针定位：大 wood 网格约 2.2 秒在 CollisionShape3D 接入已在树内的 StaticBody3D；shape 赋值约 43 ms，其他步骤很小。先树外组装后整体入树仍约 2.1 秒，耗时转移到 body 入树，没有消除 Jolt 后端构建。因此没有发布该顺序改动，也没有换物理引擎或拆分原三角面。探针原始 JSON/脚本保留在本机证据目录。

本片改为处理独立文件校验。CollisionVerifier 在 WorkerThreadPool 上串行执行纯文件检查，不访问场景节点、形状或物理服务器。参考 [Godot 线程安全说明](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)：当前没有启用独立物理线程，不能把物理服务器/节点操作直接搬进工作线程。主线程逐帧等待，任务完成后 join 再取结果；重复输入合并，所有者销毁不丢任务，应用退出前 join 活跃任务。

SourceCollisionCache 分开文件证明与资源消费。原源/导入/缓存 SHA、引擎和原收据比对仍每次作业重新执行，不跨加载缓存哈希。证明携带源/缓存路径和文件大小/修改时间，主线程消费前检查变更，并再次计算缓存与导入字节 SHA，随后仍用 CACHE_MODE_IGNORE 读取形状并验证类型、背面策略、节点路径和变换。文件状态检查是交接保护，不代替 SHA；其保证是该次作业检查时点，上层冻结布局在对局就绪前也继续复核原源哈希。同步 API 不变，失效仍回退原网格生成。

collision_verification 的 wall_ms/wait_frames/max_frame_gap_ms 描述后台校验作业等待，不是 GPU 帧时间。collision_cache.verify_ms 为文件作业本身；预验证路径的 total_ms 仅消费阶段，不能和前者重复累加。缓存反序列化、Jolt 注册及冻结布局验证仍可能在主线程阻塞，不宣称整体加载提速或 70% FPS。

聚焦覆盖原缓存合同、输入合并、等待者销毁、独立证明、变换/路径/引擎错误、源变更、同大小缓存/导入字节变更和缺收据。首个编辑命令默认 GBK 读取项目中文文件失败，未写坏该文件；明确 UTF-8 后继续。仅修格式/导入别名及测试断言时不重复完整套件。

最终原生 **216**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；真实三图 **123 形状、3,265,932 三角面、11,725 射线、1,467 胶囊** 对照一致；双入口 **6 次 Vulkan、126 PNG** 通过，Inferno 购买页已检查。四个既有脏导入与用户设置逐字节保持。

普通入口后台校验：Dust II 约 129 ms、等待 10 帧、最大间隔 71 ms；Mirage 43 ms、7 帧、12 ms；Inferno 699 ms、161 帧、11.5 ms。主线程消费阶段分别约 42/14/244 ms，仍含反序列化和形状验证。Inferno 单网格本次约 1.5 秒，与先前约 1.9–2.2 秒不是受控 A/B，不能归功于本片或计算整体提速比例。

本机证据 `D:/AgentGamePipeline/evidence/collision-backend-preparation-20261024/`，结果见 audit.json，提交/PR/CI 首次快照见 delivery.json。原资产和缓存保留。Jolt 单网格仍待处理；环境上传、C4/观战、AI，以及最新头 18 场、连续人工三图和 70% FPS 继续待验。
