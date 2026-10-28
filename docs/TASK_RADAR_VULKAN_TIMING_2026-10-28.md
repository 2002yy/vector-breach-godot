# 三图 Vulkan 雷达首次显示与切层测量

基线 `f8cda2d`；新增独立作者入口 `open_radar_vulkan_timing.gd` 与 `probe_radar_vulkan_timing.gd`，复用真实 GrayboxLevel、CombatHud/RadarDisplay、本机 v4 atlas。未改运行时逻辑、原图或玩家参数。

三图按序在1280×720、Forward+ Vulkan、RTX5060 Laptop GPU执行，使用控制光照和固定相机。先请求出生脚底最近层，再请求相邻层，最后返回缓存层；这些高度由探针控制，不是玩家实际行走。每次更新记录HUD调用耗时、等待frame_post_draw的CPU墙钟时间、来源ready时刻与首次目标层绘制完成时刻。没有GPU timestamp query，因此不能称为GPU执行时间或稳定帧率。

|地图|首次来源ready ms|首次绘制完成 ms|相邻冷层绘制 ms|返回缓存层绘制 ms|三阶段最大HUD调用 ms|
|---|---:|---:|---:|---:|---:|
|Dust II|139.594|164.178|26.528|8.226|2.258|
|Mirage|103.435|134.445|29.848|8.901|3.024|
|Inferno|783.098|809.322|24.075|4.899|2.683|

首次阶段单次update至post_draw墙钟最大分别109.636/101.745/294.890ms，包含初始化、渲染提交、同步与等待，无法归因给雷达本身。HUD update最大也可能含图形驱动上传等待，不能用headless微测量替代。来源ready包含后台原碰撞GLB身份哈希，首次可见并非仅PNG解码延迟。三图截图均已查看，底图及标记可见；Inferno仍有明显首次可见等待，70%FPS与实战帧预算未验收。

证据：`D:/AgentGamePipeline/evidence/radar-player-package-20261028/vulkan/v2/`内三份JSON、PNG及Vulkan日志；`source-locks.json`记录探针/运行时源文件哈希。第一轮直接选最低层造成底图稀疏的截图与数据保留在上级目录，最终使用出生最近层；不是丢弃性能失败重跑。两轮均三个地图串行退出0。格式/lint通过。

下一步：在真实Player路线和完整对局中采集稳定帧分位数，使用GPU时间戳或外部图形分析工具分离GPU负载；补打包运行、冷磁盘/热缓存控制和多次重复。当前只完成来源工程的有界可见延迟观察，不代表PCK、设备全面性能或人工比赛验收。
