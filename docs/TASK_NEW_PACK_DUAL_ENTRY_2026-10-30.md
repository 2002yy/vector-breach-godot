# R48 新完整候选双入口开局验收

使用R47正常导出三件与R48补齐的完整支持文件，运行时源码756ef174。实际普通EXE及实际EXE加旧可选入口完整参数（--controlled-game和三份candidate内bundle）均独立运行三图菜单→开始→购买→就绪→战斗。12张start/ready截图全部逐张查看，菜单另有截图。所有输入仅投递到已核验测试PID的自有HWND，PrintWindow只抓该窗口；没有全局键鼠、抢前台或代码覆盖。可选入口ready后额外等待11秒。六个实际EXE进程均已关闭，设置SHA保持。

新`tools/authoring/capture_owned_release.py`补充PrintWindow通道，抓图前核验实时PID映像路径，拒绝覆盖截图，释放GDI资源；Ruff/格式/Pyright通过。它不证明PostMessage一定被接受，流程通过来自实际截图。

可选环境内部接线另用实际新主PCK/附包及新candidate bundle在独立editor Vulkan宿主验证，三图各退出0、零ERROR、OPTIONAL_EXPORT_VULKAN_READY，runtime configured、10角色绑定、玩家手臂和真实死亡后第一人称观战手臂绑定通过，六张内部截图已查看。隔离host中rawDust原字节以同盘硬链接读取，SHA核验，未复制313MB桥包或更改candidate文件。此通道仅证明内部接线，不代替上述实际EXE开局或原引擎画质/70%FPS。

新发现未通过项：普通及可选实际EXE截图左上雷达只有黑底/标记/细网格，ready后11秒仍无可读真实底图。Mirage/Inferno诊断宿主只读Radar.get_debug_snapshot明确atlas_status=source_identity_mismatch、atlas_layer=-1、layer_count=0、feature_count=0，说明不能以atlas资源存在或其他旧ready记录放行本包底图。未改产品或放松身份校验，待定位compiled/原资源身份冲突。

证据：`D:/AgentGamePipeline/evidence/r48-20261030/entry/result.json`、actual-optional三图日志/状态、普通及可选12张start/ready图、optional三图内部result及PNG、Mirage/Inferno*-radar-debug.json。短时T方开局不等于完整比赛/人工三图，观战内部断言不等于连续切人体验；新候选尚不能宣称完成全部可玩/画质验收。
