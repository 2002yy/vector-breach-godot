# 专用碰撞层分帧注册

基线 `767f7d32a8e9e52f76a2dff5fd23341bd8b67051`（#83），分支 `feature/staged-collision-registration`。前头 Tests 40081728126、Windows 40081728141 全成功。本 PR 目标 main，包含前序已提交加载优化，不等待 CI；已验收试玩包仍为 main 598cde1，本片不覆盖。

上批 Inferno 缓存校验/读取约 1 秒、碰撞阶段合计约 4 秒，说明注册仍有集中阻塞。本片仅异步开局的专用碰撞层按原 COLLISION_* 网格逐个创建原 StaticBody3D/CollisionShape3D，再让出 process_frame。同步 load_level 和视觉自身生成碰撞保留原同步行为。两条路径使用同一个逐网格附件实现；三角面、局部/全局变换、背面规则、层/遮罩及网格释放策略不改。

缓存仍按原哈希、导入参数、引擎、节点路径与变换整组验证；失效仍回退 create_trimesh_shape。完成整个专用层后才开始主视觉后台读取。每次让帧后检查关卡代次，旧循环不继续注册、不覆盖新统计；所有者销毁会撤销旧协程和已创建的子节点。Warmup/不可交互窗口继续沿用。

collision_build_ms 包含校验、读取和让帧等待；collision_work_ms/collision_max_mesh_work_ms 是逐网格调用的工作量，collision_yielded_frames 是让帧次数，collision_max_frame_gap_ms 为注册窗口主循环最大采样间隔，包含可能的物理更新/渲染等待。它们不是 GPU 帧时间，不覆盖同步缓存阶段，也不保证每次 process_frame 都对应一个物理更新。单个大网格不可抢占，未宣称整体提速或 70% FPS。

聚焦覆盖缓存/回退形状、网格释放与保留、逐网格让帧、精确三角面、旋转平移下真实射线/胶囊、层/遮罩与背面规则、空层、被新关卡替换和所有者销毁。首稿类型标注与将胶囊放在凹面壳体内部的查询断言已修，旧日志保留；仅修聚焦用例，没有因断言问题重复完整套件。

最终原生 **215**、Python **80**、GdUnit **2/2**、格式/无新增 lint/资源合同通过；真实三图 **123 形状、3,265,932 三角面、11,725 射线、1,467 胶囊** 对照一致；普通/候选双入口 **6 次 Vulkan、126 PNG** 通过，Inferno 购买页已检查。四个原有脏导入与用户设置逐字节不变。

普通入口按原网格让帧 Dust II 35、Mirage 39、Inferno 49 次；注册窗口最大采样间隔分别约 306、80、1,918 ms。Inferno 单网格调用约 1,916 ms，说明剩余主因在单网格内部，未通过流畅加载验收。碰撞总墙钟约 703、293、4,417 ms，包含等待；不能据此宣称整体提速，也不与旧头单次值算加速比例。

本机证据 `D:/AgentGamePipeline/evidence/staged-collision-registration-20261024/`，结果见 audit.json；提交/PR/CI 首次快照见 delivery.json。三图比较不替代连续人工试玩、最新头 18 场或 70% FPS。下一片按测量处理剩余单网格/校验长帧及环境上传，再推进 C4/观战、AI。
