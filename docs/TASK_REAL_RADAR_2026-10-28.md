# 三路推进：真实碰撞底图雷达

基线 `4bd2291`。本片为三图增加原碰撞派生的稠密地面拓扑底图，不修改原地图、原纹理、碰撞或布局。它不是原版 overview 美术，也不是导航可达性证明。

## 实现

`build_real_radar.py` 读取当前关卡声明的原碰撞GLB，按默认scene递归合成node的matrix/TRS，再取朝上的碰撞表面与身体高度剖线。三图分别生成8/9/9个高度切片，1536×1536，所有PNG、原坐标及UV校准点只保存在忽略目录 `assets/local_reference/radar/<level>/v4/`。atlas锁定原GLB、其.import、关卡JSON、生成器与每张PNG的SHA256。三图最终生成器SHA与当前代码一致，核对记录在本机 `movement-three-lanes-20261028/radar/summary-v4.json`。

整合图像审查发现v3的Inferno出生高度切片只有少数地面块，远处大片透明，不能靠26张切片计数宣称可用。因此v4同一PNG先低亮绘全部原碰撞地面作地图上下文，再高亮本层地面、轮廓与身体高度截线；不增加运行时纹理次数或材质。v3及初轮图像保留，不覆盖旧结果。

`RadarAtlas.gd` 在后台线程校验大GLB，主线程轮询完成，不在每帧同步读取地图。小JSON/.import及PNG身份仍检查。缺失、身份不符、图像损坏或高度无合适切片时回退旧线框雷达。每张地图最多缓存两张解码纹理；切图释放缓存。现按地图ID缓存校验，要求同一活动会话原资产保持冻结；同ID运行中热替换GLB/import并重载后的generation失效尚未接入，不能宣称支持这种开发热替换流程。

Main雷达快照只新增地图ID、真实胶囊脚点及接地状态。底图按脚点高度选切片，接地后更新，跳跃期间保留起跳前层；换图重置，楼梯边界有滞回。它们是自动高度切片，不等于地图语义楼层，产品HUD不显示内部层编号。原北向/旋转、A/B、队友/已发现敌人、C4及人物高差箭头保留；底图就绪时停止叠加旧矩形障碍/arena边界。

## 本片证据

- Python 5项：非正方形/偏移世界坐标、TRS变换、剖线、朝上/朝下区分、含父子节点与索引的合成GLB；测试名符合现有CI `test_m*.py` 发现规则，不需要Pillow执行纯合同测试。
- 原生 `REAL_RADAR_CONTRACT_OK checks=116`：三图26个切片读取/PNG锁、源漂移、缺失/漂移import、路径/范围、UV校准、跳跃保层/接地换层、滞回和纹理缓存上限；缺失地图回退。
- Mirage与Inferno原图+实际CombatHud Vulkan/Forward+探针通过，1280×720截图已查看。受控探针光照只服务HUD核验，不当作原引擎材质、正式比赛或70%帧率验收。图中隐藏未发现敌人，队友/C4/朝向保留；未新增调试层编号。
- Python Ruff/格式/Pyright、新GDS格式/lint通过。旧Main/RadarDisplay仅定向修改，不做全文件重排。完整整合套件与最终提交/PR/CI由主线记录。

外部证据：`D:/AgentGamePipeline/evidence/movement-three-lanes-20261028/radar/` 内 `build-v4-results.json`、`summary-v4.json`、`native-v4-contract.log`、`mirage-classic-local-hud-v4.png/.json/.log`、`inferno-classic-local-hud-v4.png/.json/.log`。首次探针SceneTree直接引用autoload的编译问题已改为deferred加载Node入口；生产逻辑不依赖此探针时序。

## 执行与剩余边界

从完整工程根目录生成新版本，不能覆盖既有atlas：

```powershell
python tools/build_real_radar.py mirage-classic-local <新的本机外部或忽略目录>
D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/authoring/test_real_radar.gd
D:/Godot/4.7.1/Godot_v4.7.1-stable_win64_console.exe --path . --resolution 1280x720 --script res://tools/authoring/open_real_radar_probe.gd -- mirage-classic-local <新的外部输出前缀>
```

仍需三图实走核对通道/上下层、楼梯/隧道边界与不同雷达范围的可读性；自动切片不是人工标注的楼层图，屋顶/道具上表面与遮挡仍须逐区审查。需要完成底图解码/切层帧时间与显存预算、同ID身份更新失效、完整敌情/C4信息规则及观战雷达验收。原版素材与派生底图不进入Git，本片不更新试玩包；下一次整合发包须显式纳入本机atlas并验证缺失回退，当前桌面旧包不会自动拥有新底图。
