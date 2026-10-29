# R42 标准EXE图形验收：菜单已观察，三图开局未放行

基线`0b98bc9`，使用本轮正常Windows Desktop导出的`D:/AgentGamePipeline/evidence/standard-release-20261029/candidate/VectorBreach.exe`，未注入诊断主场景、代码覆盖或作者地图选项。实际EXE的SHA256为`2b9f079a843397d8b441b762173dc5278c658e949ab7d8a0882696387e8780bd`。

`graphical/menu-own.png`为该进程窗口的PrintWindow截图，已人工检查：1280×720，Inferno背景、地图卡片、CT/T选项、开始/设置/操作帮助按钮正常可见。该截图仅证明菜单渲染，不能证明Dust II、Mirage或任何地图已经开始并进入ready。

正常截图/输入通道遇到Windows前台焦点限制：候选不是前台窗口时，自动化拒绝发送全局输入。自有窗口PrintWindow抓图成功，但未取得三图菜单切换、开始、ready的完整证据。收尾时原测试PID 904已不存在，未重新启动或持续争抢前台。三图正常开局仍为待验，不能替代为隔离雷达切片检查或R41诊断开局结果；暂不覆盖桌面试玩包，不删除上一可用基线。

新增`tools/verify_standard_release_start.py`仅针对显式启动并记录的PID，操作前查询活进程映像路径防止PID重用。窗口点击/键盘使用目标HWND的PostMessage，不移动用户鼠标、不发送全局键盘、不调用SetForegroundWindow或AttachThreadInput。截图仅在候选已是前台时执行，否则安全失败。PostMessage返回成功仅表示投递，不能充当游戏接受输入的证明；截图仍须逐张人工检查。

收尾核验：当前用户settings.cfg与事前备份SHA256均为`5240ec0a121bcc3fcd1c4a2b4d3e48e870ea1a2773798fa094fc41cb65e061b8`，无需还原，也没有覆盖用户的新设置。新增工具Ruff F、格式、Pyright通过，未改生产脚本/配置/正式手感。下一步在候选窗口可保持前台时完成三图正常菜单→开始→ready截图，不以本记录放行比赛、帧率或人工试玩。
