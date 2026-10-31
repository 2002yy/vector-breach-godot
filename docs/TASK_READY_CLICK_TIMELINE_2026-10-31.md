# R50 就绪点击与首发输入时序

基线09592b7。只增加空宿主作者探针，生产树冻结供18场比赛，不改正式输入、武器、参数或原资源。

R49实际普通/可选EXE三图曾重复观察到就绪后手枪12→11。这次在Godot4.7.1空宿主中创建真实Button，通过Input.parse_input_event注入左键down/up并flush，按钮pressed把局部live置真。实际日志：down时held=true/just_pressed=true/live=false；Button释放信号与同帧up后held=false/just_pressed=true/live=true；下一process_frame才清除just_pressed。进程退出0，无ERROR，不加载游戏、资源或用户设置。

静态产品链：BuyPage.gd:159连接默认释放触发的pressed；Main.gd:688的_on_player_ready同步调用RoundManager.player_ready，设LIVE并关闭购买页；Main.gd:361每帧全局轮询fire_primary的just_pressed；WeaponSystem.gd:80半自动枪依赖fire_pressed，不要求held。tools/verify_standard_release_start.py:129–132将WM_LBUTTONDOWN/UP连续排队，无帧间等待。Control消费GUI事件不会自动使全局Input状态清零。因此快点击在一个帧周期完成时，就绪UI转换和开火轮询存在确定的同帧重叠窗口。现有MainStateFlow购买页测试仅pressed.emit，没有真实鼠标输入，无法覆盖这个窗口。

证据：D:/AgentGamePipeline/evidence/r50-20261031/input/{probe.gd,project.godot,probe.log}。可复用探针tools/authoring/probe_ready_click_timeline.gd仅格式化；gdformat/gdlint通过。探针证明输入生命周期，不等于已经记录实际Main每帧弹量或普通人工点击；此前12→11的完整产品因果链仍需定向Main输入重放与实际EXE复验。不要归因雷达、武器伤害或装弹逻辑。

下一修复片建议：在UI→战斗转换时为primary/secondary及投掷/安装主键设置明确的输入重置门闸，要求转换帧之后释放、再进行新的按下才能使用。门闸应同时阻挡同帧just_pressed残留和跨帧按住自动枪，不使用全局Input.action_release抹除其他系统输入；覆盖购买关闭、帮助/菜单恢复等同类转换。先保留当前冻结18场，再独立实现，测试快速down/up、跨帧点击、按住自动枪、正常下一次点击、键盘激活就绪和右键/投掷物，最后按生产变化跑原生全套。尚未实施此生产修复，不改变当前包。

作者probe补为失败门闸：要求真实Button只发一次信号、down确有输入、释放同帧live=true/held=false/just_pressed=true、后帧just_pressed=false；缺信号或任一状态不符都会输出READY_INPUT_ASSERT并退出1，不再仅打印退出0。新空宿主重跑日志probe-assertions.log为failures=0、退出0，首次probe.log原样保留；gdformat/gdlint通过。该门闸确认的是引擎输入生命周期，尚不替代实际Main修复验收。
