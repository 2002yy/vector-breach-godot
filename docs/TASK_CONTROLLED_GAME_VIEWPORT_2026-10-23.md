# 显式候选游戏入口与角色生命周期

2026-10-24 续修：玩家与观战第一人称手臂、普通 PBR 袖子适配、3D 音频监听及优先次序见 [手臂接线记录](TASK_FIRST_PERSON_ENVIRONMENT_2026-10-24.md)。下文“手臂尚未接线”属于原批头的历史边界，最新状态以项目入口为准。

## 基线与入口

分支 `feat/controlled-game-viewport-20261023`，main 基线 `bfc7ba5dbe4e0739f2781a4a45faf05104f37cfe`。#74 精确修复头 `38cee770e413892bd0492246a88a829cb3a6996c` 的 Tests `39925209809`、Windows export/smoke `39925209839` 成功，审查项解决且 CLEAN 后合并；没有等待新片 CI。

默认 `project.godot` 仍启动 Main。开发入口为 `scenes/ControlledGame.tscn`，它加载真实 Main、地图、AI、菜单和 HUD；不再把独立角色摆拍算作游戏接线。使用本机 Godot 4.7.1：

```powershell
& D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --path D:/AgentGamePipeline/repos/VectorBreach-godot --rendering-method forward_plus --rendering-driver vulkan --scene res://scenes/ControlledGame.tscn -- --character-bundle D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/bundles/dust2/bundle.json --character-bundle D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/bundles/mirage/bundle.json --character-bundle D:/AgentGamePipeline/evidence/character-runtime-inputs-20261023/bundles/inferno/bundle.json
```

私有输入包不进 Git/导出。无输入或无对应地图时保留原材质。清单目录只读至多 64 KiB 的身份头；真正地图就绪后才做整包完整校验、上传和绑定。重复地图、无效 JSON/类型、过大/缺失清单会拒绝目录。该入口仍有同步哈希/LPV 分配，不能作为加载优化成果。

## 输入与渲染归属

Main 位于独立世界的 SubViewport；TextureRect 只显示结果，绝不通过容器 stretch 在拥有者背后重建原生缓冲。子视口按外层画布逻辑尺寸渲染，尺寸变更经已有 SSAO 事务提交，不能等同默认根视口物理分辨率下的帧率/画质验收。

输入经外层 `_input` 单次进入子视口的完整输入链，先 GUI 再未处理按键。自由鼠标位置换算到子视口；捕获鼠标保留外层实际收到的相对位移，避免再次缩放/重复转向。输入 API 参考 [Godot Viewport 官方文档](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-push-input) 及本机固定版本源码。

常用键保持现有规则：F1 按当前菜单/购买/战斗状态展开帮助；B 买枪；Esc 收起面板/暂停/返回；死亡后 `[` / `]` 切队友、空格切视角。窗口失焦打开暂停菜单，重新获得焦点不自动开战。F11 沿用原全屏动作，本片流程未将全屏/最小化验收宣称完成。

## 地图与角色

GrayboxLevel 在实际加载前发开始通知，Main 在布局与角色就绪后发 `level_prepared`。候选拥有者先撤销旧材质/上传和旧观战，再按实际地图身份加载；异步完成还要核对地图代次。不会依据尚未加载的选卡状态给旧地图角色套参数。

TacticalActor 提供外观替换前后通知和原生视觉 getter；CombatSandbox 提供清空阵容前通知。拥有者在旧角色销毁前解绑，外观重装和回合阵容重建后绑定新视觉；旧角色登记不会沿用到新对象。退役材质留存至渲染帧结束。此处只接第三人称 TacticalActor 全身，玩家/观战第一人称手臂尚未加入候选环境合成。

实测仅延长候选材质寿命仍有渲染线程空材质错误；在角色/原生视觉 `NOTIFICATION_PREDELETE` 中清理实例覆盖后，同一真实阵容重建流程无错通过。该症状与 [Godot #85817](https://github.com/godotengine/godot/issues/85817) 的覆盖材质销毁问题相符，但简化的无候选阵容/混合覆盖探针未复现，不把它说成已完整证明相同引擎根因。只清实例覆盖，不改 Mesh 资源或原表面材质。失败日志和简化探针源文件保存在私有证据目录。

观战目标现在拒绝已移出树、等待删除或跨视口队友；旧对象释放后先清目标再切人，避免把失效引用传入 TypedArray.find。原生回归覆盖移出、移动到另一视口、释放、等待删除、无本视口队友与预览队友排除。切图时先结束旧观战，避免 HUD 读取旧目标坐标。

## 验证与边界

`ControlledGameProbe` 从根窗口注入输入，实际走 Main 输入/GUI，覆盖三图菜单/F1、地图卡/阵营、购买帮助/B、窗口缩放后的鼠标点击、捕获鼠标单次转向、外观替换、真实阵容重建、死亡切人/双视角/暂停、缺包地图回退和实际上传期间切图取消。窗口请求 1024×768 时，项目保持 16:9 内容，读回截图为 1024×576；另显式经 SSAO 拥有者把真实游戏子视口重建为 1280×720，再测试点击/转向和恢复，避免仅验证外层缩放。最初两个测试错误分别是点击暂停时本来禁用的地图卡、注入时未换算窗口物理坐标，均修正测试并保留失败日志。

最终 GPU、完整原生、Python/GdUnit、格式/lint/静态导入、资源合同、原模型哈希及提交/CI 首次快照见 `D:/AgentGamePipeline/evidence/controlled-game-viewport-20261023/audit.json` / `delivery.json`。不等待 hosted CI，不以旧头成功代替新头检查。

三图上述实际游戏流程全部通过，每图 **9 PNG**，共 **27 PNG**，日志无脚本/Shader/渲染错误。完整原生 **208 / RUN_ALL_OK**、Python 非 Blender **80**、GdUnit **2/2**、静态导入/资源合同通过，18 原模型哈希不变。新增和规范脚本格式/lint 通过；五个旧脚本逐项对照基线，无新增 lint 问题，不把已有风格债称作全零错误。三图截图中的即时 FPS 包含加载/重建过渡短窗口，尚无稳态采样，不能作为帧率目标验收。

下一执行片为选卡零实际关卡加载、开始只加载最终地图一次及加载分段计时。C4 提示/爆炸、观战视觉与 AI 运动/难度随后继续；原 Source 2 per-view/对象遮挡/切线、眼球时序、雾/平均色、最新头 18 场、三图连续人工比赛及逐图 70% FPS 仍待验收。唯一试玩包保持 #63，不把候选开发入口当作新版正式可玩包。
