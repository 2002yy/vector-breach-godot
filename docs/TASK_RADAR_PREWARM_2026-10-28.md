# R38 雷达来源校验预热

基线 `e0bd468`。实际开局 `_start_selected_map` 在异步加载地图前，向现有 HUD 雷达传入地图ID与下一加载序号。`_on_level_loaded` 提前递增并确认实际序号，随后才执行环境、布局和队伍准备；同一 Atlas 实例及同一序号不会重启校验。没有在大厅选图时加载资源，没有用mtime或历史缓存绕过原哈希验证。

RadarDisplay仅在预热来源校验期间处理帧，ready/失败后停止；正常snapshot接管时停止预热轮询。失败开局明确取消，空地图使generation失效，避免失败重试复用旧证明；地图替换与重载继续使用既有代次隔离。取消不强制阻塞等待旧线程，析构仍须等待既有后台任务。

新增作者 `test_radar_prewarm.gd` 实测取消、替换、同序号snapshot保持generation和新序号重载，输出 `RADAR_PREWARM_OK lifecycle=cancel_replace_snapshot_reload`。根审查额外发现Main加载期间仍发旧snapshot，会打断预热；现增加待预热地图与序号双匹配门闸，旧snapshot在校验中及ready待接管时均被忽略，只有匹配snapshot接管后清空预热身份。新增回归覆盖旧地图、旧序号以及匹配序号但错误地图。两份新GDS格式/lint通过；Main/RadarDisplay lint债务数量完全保持，未整文件格式化。

新增 `probe_radar_prewarm.gd` 在真实Graybox地图构建前创建HUD并可选预热，以原有Vulkan测量逻辑记录绘制完成墙钟。Inferno一次冷/预热配对：地图准备13.021519/12.897743秒；地图准备后首张底图绘制730.472/254.639ms；地图准备后来源ready710.408/0.822ms。两次EXIT0，最终预热截图已查看。校验等待与真实地图构建发生重叠，但单次配对、磁盘缓存、渲染调度存在影响，不能宣传为总启动时间稳定下降或GPU帧预算通过。该探针验证相同HUD/API加载顺序，并不代替完整Main人工开局体验。

本机证据 `D:/AgentGamePipeline/evidence/radar-export-identity-20261028/prewarm/`：`inferno-cold.json/log/png`、`inferno-prewarm.json/log/png`、`lint-delta.json`、`focused-stale-snapshot-final.log`。配对Vulkan是修门闸前的独立HUD探针，不是完整Main开局性能证据；修复后通过定向旧帧竞争回归，根整合重新运行最终原生全套。正式Current与原资产几何不变。下一步三图重复冷启动/真正开局首次可见时间，以及加载取消竞争和真实GPU帧预算；完整18场/人工三图/70%FPS仍待验。
