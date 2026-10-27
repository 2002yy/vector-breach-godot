# Movement-4 R33：真实武器上下文与双频采样审核

基线 `2e2d804`（#129），分支 `audit/movement-weapon-observation`。本片只增加作者工具，正式 Current、地图几何、资产、菜单和试玩包不改，Movement-5继续冻结。

新入口实例化正式 `WeaponSystem` 和 `TacticalEquipment`，用实际装备状态驱动玩家现有速度入口。作者按键为 1 AWP、2 AK、3 刀、右键开关镜；这些是独立观察器快捷键，不宣称与正式装备槽相同。WASD、Shift、Ctrl、Space及F5重试/F6切点/F8保存沿用原入口，方案冻结，换方案需另启会话。不开枪、不创建AI或整场比赛，也不能代替精度、枪战与完整路线验收。

采样新增真实武器ID、槽位、装备类型、有效开镜状态、相机FOV与原FOV、最终限速及实际水平速度。验证器核对开镜只发生于AWP、FOV28及关镜恢复、刀/枪类型与槽位一致、实际水平速度与三维速度相符。自动模式要求AWP站/静步/蹲的镜与非镜六组合、AWP→AK→刀→AWP顺序、非零移动和真实起跳；这只证明技术过程，不生成手感分数。Current原开镜限速不变，Legacy/Modern仍为待试玩候选。

`movement_observation_session_audit.py` 增加全会话帧序/消费时钟、事件时钟、60/120Hz步长、重试同点与切点顺序、请求/支撑/起跳一致性、方向、姿态与容量审核。审计旧15份补充入口收据，6份60Hz通过，9份120Hz因启动5～7个60Hz样本被拒绝；保留原始收据和失败，不能把旧入口宽门闸结果称作严格双频通过。新入口须在创建玩家前完成频率预热，再开始实际记录；不通过删除已记录样本或放宽delta容差来修复。

冻结包位于本机 `D:/AgentGamePipeline/evidence/movement-weapon-observation-20261028/`，只保存清单、锁、日志和采样，不复制原地图资产。旧registry来源与九份正式方案参考仍重新验证；武器参考属于新观察条件，不继承旧未装备上下文的跳点成功结论。失败pack-v1和120Hz收据保留，新冻结版本独立生成。

人工启动示例（完整项目根目录，实际版本见本机交付记录）：

```powershell
python tools/movement_weapon_observation.py launch D:/AgentGamePipeline/evidence/movement-weapon-observation-20261028/pack-v2 --godot D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --map mirage --scheme modern_cs --rate 120 --receipt D:/AgentGamePipeline/evidence/movement-weapon-observation-20261028/manual-mirage-modern-120-01.json --session manual
```

保持新收据路径，每次attempt不超过45秒，三分钟舒适观察分段保存。九格人工矩阵、设备条件和三次尝试合同继续适用。新入口只是提供S4真实装备/开镜上下文，S4人工评分仍pending，不自动解除整项验收；旧移动专用入口的S4仍blocked。原机同条件、落地伤害/相机、AI、18场、连续三图和逐图70%FPS仍待完成。

本机 `checks.json`、`static-final.json`、`native-suite.log`、`weapon-native-v2-results.json`、`weapon-render-v2-result.json`、`preservation.json` 和 `delivery.json` 分别保存检查、修复后静态、原生全套、矩阵、窗口、保护与提交/CI证据。自动窗口截图只证明画面及入口，人工、M4与M5均不据此放行。不等CI、不合并、不发包。

最终本机结果：新包18/18技术会话通过，3852实际样本、18次真实起跳，60/120Hz样本各自保持对应delta；559项Python、原生全套RUN_ALL_OK、188项真实装备夹具和静态检查通过；公共启动器Mirage Modern/120Hz原图Vulkan窗口通过并查看截图。完整人工、比赛、原机等价和性能仍未验。

真实速度入口输出的站姿AWP限速（m/s，未镜→开镜）：Current `5.828→5.828`，Legacy `5.334→3.810`，Modern `5.080→2.540`。这是项目当前方案的限速输出，不是原版客户端实测，也不声称短冒烟已达到每个最高速度；用于后续人工比较，正式Current不在本片调整。
