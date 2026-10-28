# 实际 Main 三图开局观测

基线98d170c，仅新增作者探针`probe_main_radar_startup.gd`。实例化真实Main，调用真实地图选择与`_on_start_pressed`，通过Main主循环完成关卡、角色、经济、购买阶段与雷达更新；未替换成独立HUD或预设雷达快照。三图分别新进程、串行source Vulkan运行。

选择地图后等待两帧确认load_count未变；实际开局后每个绘制帧记录Main状态、Atlas状态/generation及墙钟。三图均只发生一次实际加载，来源校验generation保持2，ready发生在game_started之前，旧地图快照没有重置预热。

|墙钟ms|Dust II|Mirage|Inferno|
|---|---:|---:|---:|
|确认开始→game_started|4570.695|2704.548|10138.460|
|确认开始→雷达切片所在绘制帧完成|4582.673|2742.066|10201.704|
|game_started后差值|11.978|37.518|63.244|

观测条件为真实运行时HUD可见、atlas_layer>=0与frame_post_draw，购买页当时仍打开；随后调用真实玩家就绪操作关闭购买页再截图，三图截图均已查看。不能把该时刻声称为没有任何遮挡的玩家首见时刻。计时不包括引擎启动/Main初始资源加载，非GPU时间戳，三图各一次且已有本地导入/碰撞缓存，不是冷启动分布、完整人工试玩或70%帧率验收。场景截图的瞬时FPS不能用于性能结论。

证据`D:/AgentGamePipeline/evidence/radar-final-pack-20261029/startup/`：三图JSON含事件时间线、逐帧墙钟及Main.last_start_timings；同名log/png均成功，设置文件逐图SHA256核对保持不变。未修改生产代码、用户设置、原版几何或正式手感。实际失败/取消主流程未在本探针注入；已有预热生命周期回归不能替代这项E2E证据。

复现：完整工程根目录，以Godot Vulkan运行`--script res://tools/authoring/probe_main_radar_startup.gd --resolution 1280x720 -- <地图id> <新输出前缀>`；现有JSON拒绝覆盖。格式/lint通过，不运行完整套件。
