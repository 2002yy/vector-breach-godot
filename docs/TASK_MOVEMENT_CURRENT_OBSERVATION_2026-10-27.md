# Movement-4 R32：最新来源人工观察入口

本片仅新增作者适配器 `CurrentMovementObservationSession.gd`、原生启动脚本和 `movement_current_observation.py`。复用R20原图、原生Player、原环境、目标圈和采样器；旧观察器和正式菜单、Current默认、原图、试玩包不改。正式三方案与实验Modern候选分开，包中只收最新registry选定的正式三方案。

入口先验证registry所有来源及三图全部九份清单，再打开所选地图/方案/60或120Hz。每份清单使用该方案自己的原坐标、朝向、目标半径、输入时间线与来源case，坐标仅存本机外部证据，不写Git。`qualified_jump`和`walk_only`原标签保留；walk_only只是动作/观察点，不升级为必须跳跃通路。橙色目标圈是诊断标记，完整出生点路线仍待验。

原生HUD显示地图、点、类别、方案、频率、资格标签、键盘/鼠标参考和来源case。人工自行操作WASD、鼠标、Space、Ctrl、Shift；F5重试、F6换点、Esc释放、F4继续、F8保存退出。F7禁用，换方案从入口重新启动，避免在不属于该方案的参考上采样。smoke才自动操作；manual不注入按键。无队伍/AI/比赛入口；射击、精度、AI与完整路线按人工清单另验。

```powershell
python tools/movement_current_observation.py build D:/AgentGamePipeline/evidence/movement-current-observation-20261028/v1 --registry D:/AgentGamePipeline/evidence/movement-current-registry-20261028/registry-v1.json
python tools/movement_current_observation.py verify D:/AgentGamePipeline/evidence/movement-current-observation-20261028/v1
python tools/movement_current_observation.py launch D:/AgentGamePipeline/evidence/movement-current-observation-20261028/v1 --godot D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --map mirage --scheme current --rate 60 --receipt D:/AgentGamePipeline/evidence/movement-current-observation-20261028/manual-mirage-current-60-01.json
```

从完整Godot工程根目录执行；外部包/收据不可覆盖，新版本另建目录。`--map`接受dust2/mirage/inferno，`--scheme`接受current/legacy_16/modern_cs。参考毫秒输入是已知成功的作者输入提示，不要求人类精确复现，也不构成盲测。

收据始终`human_review=pending`、`formal_release_ready=false`。保存后验证原R20身份/姿态/采样顺序，并额外核对新适配器与入口源码、冻结方案、有限位置/实际速度；截断轨迹拒绝。每次尝试最多7200采样，人工观察统一采用不超过45秒的分段，长观察应F5分段或保存新会话，不能把截断当完整记录。评分另存人工模板，自动窗口/截图/速度不能填人工手感分数。Movement-4未验收、Movement-5冻结。

验证结果以本机新观察目录中的收据及整合交付记录为准。Python回归覆盖九份清单、各方案自己的输入、源码/registry漂移、覆盖拒绝、假人工验收、跨方案/截断/非有限速度与先验证后启动；原生冒烟与真实Vulkan图像只证明入口能够运行，不证明人工观察完成。
