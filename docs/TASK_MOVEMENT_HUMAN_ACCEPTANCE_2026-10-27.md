# Movement-4：三图三方案人工观察合同

起始代码 `666fb39658e1cb9f18e28ba8c419d8a758f8e1c7`（R31 后）；本文件规定待执行人工观察，不记录已完成试玩。当前权威状态见 [PROJECT_STATUS](PROJECT_STATUS.md)。**Movement-4 未验收、Movement-5 菜单/包冻结，正式默认保持 Current。** 作者窗口的方案切换只供观察，不是正式菜单或候选采用。

## 证据边界与执行前门槛

R31 自动记录的动作 15/15、必须跳跃脚本通路 9/15只表示已选点类别覆盖，不能填写下表的人工评分。普通/边缘中的 `walk_only` 是走路对照，不是失败，也不能冒充必须跳跃路线。R20 的11点/33行模板是历史观察入口；新一轮只能使用最新、来源验证通过的索引，不能把旧模板复制成最新资格。

开始人工观察前，操作者核对以下准备项；未核对则本次会话标为 `blocked`，已有历史记录仍保留：

1. 冻结本次代码 SHA、索引/计划/观察器 SHA、关卡/碰撞身份、方案 ID、点 ID 和源输入版本；最新索引验证器成功，缺失/变更来源必须重新生成独立版本，不能只改摘要计数。
2. 使用新输出目录，入口没有自动按键或 smoke 开关；会话标明 `manual`，先核对实际运行的地图和方案。自动窗口截图/冒烟会话只能写 `automated`，不能转成人工会话。
3. 观察器按玩家实际速度记录水平量，方案/点切换与重试清理旧状态；只读观察不改正式参数、原图/目标半径、默认方案或发布包。
4. 每张图至少验证入口能启动/保存、当前点/方案正确、重试/切点及手动 Ctrl/Shift 不残留；最新入口固定单一方案，换方案需保存退出后重新启动对应入口，F7不切换；明确这些是入口技术检查，不代表舒适度通过。
5. 记录设备、显示刷新率、窗口/分辨率、画质、Godot 版本、物理频率、实际 FPS、鼠标灵敏度及输入设备；不同配置另开会话。开镜项还需真实装备/瞄准状态证据，移动专用窗口缺此能力时该项保持 `blocked_scope_context`。

若最新来源绑定、实际速度或保存验证失败，先修技术入口再请求用户评分。原引擎等价、AI/18场和70%FPS是后续独立门槛，不阻止明确标注限制的移动作者窗口观察，也不能被这次观察免除。

## 固定场景与预期

同一操作者、同图同点和设备条件下先 Current、再 Legacy、再 Modern；复测可反向顺序并记录，以减少熟悉度影响。每项各做三次，失败/重试照录，不删除最差一轮。参考输入帮助理解动作，不要求人工重现脚本毫秒时间；若改变起点/目标/输入版本则另记，不能继承原通路资格。

| 编号 | 每个图/方案都执行的场景 | 预期与应留证据 | 人工判断边界 |
| --- | --- | --- | --- |
| S1 速度与响应 | 固定平地/朝向、同一装备，W前进→松键；Shift静步；Ctrl蹲行→恢复，每段重复三次 | 输入、实际水平速度、姿态/胶囊高度和时间序列；核对没有卡键、姿态切换或意外失速；速度与该方案/装备合同对照 | 记录响应是否拖延、速度是否可预测；合成事件一个tick上限不等于键盘到画面的真实延迟 |
| S2 跳跃/空控 | 最新普通点站跳，边缘点跳/不跳，蹲跳点空中Ctrl；起跳后一次A/D修正 | 实际起跳、首次落地/失支撑、姿态转换、目标偏差与撞顶/卡边；每次保留到达/失败 | 评价起跳反馈、空控与落地一致性；已知可走到的点不要求必须跳跃 |
| S3 松键/反向急停 | 同一平地同装备先前进到稳定，再松W；另轮W→S，再做A→D | 水平速度过零、停止时间、滑行/反向路径；统一初速才比较量化时间 | 分别写滑行是否可控、反向是否突兀；不能把统一6.2m/s求解器结果当实际枪速 |
| S4 开镜/切换 | 实装AWP：行进中开镜→关镜→换枪→刀→回AWP；站/静步/蹲各一轮 | 真实装备ID、有效开镜状态、最终速度上限与实际速度；上下文缺失则不执行、不评分 | R20移动窗口无此武器上下文；另约正式武器入口，未提供入口前始终待验，不能用手工填写scope标志代替 |
| S5 三类路线 | 每图最新关键落点、助跑、蹲跳点；再做索引中的walk_only走路对照 | 绑定具体点ID/方案输入版本；记录身体是否卡住、首落是否在原目标及到达方式；保留三次结果 | 作者起点到目标不等于出生点全路线；脚本成功不能替人工失败改判；不得改图/目标来凑通过 |
| S6 舒适与恢复 | 连续3分钟完成上述移动，按观察器记录容量分段重试/保存；再F5重试、F6换点、保存退出后另启方案、Esc释放/F4继续 | 人工描述抖动、眩晕、跳后相机、落地冲击、误操作及恢复；原始会话/可选录像路径；截断记录另列不完整 | 停止不适场景并记录；自动截图只验证可见画面，不能判断舒适度或落地伤害时序 |

S5 的点由最新索引直接引用，不在本文件再抄坐标或猜点名；Inferno 助跑需保留 rise_03 三方案各自来源输入版本，Current 的0.25s反向制动不作为所有方案的共同输入。Mirage 作者垂直/支撑候选的旧输入失败与新输入通过保持为独立版本，不混入正式 Modern 评级。

最新入口为 [movement_current_observation.py](../tools/movement_current_observation.py)：先 `build <新外部目录> --registry <已验证registry.json>`，再 `verify <该目录>`；人工启动使用 `launch <该目录> --godot <Godot控制台exe> --map dust2|mirage|inferno --scheme current|legacy_16|modern_cs --rate 60|120 --receipt <新外部json> --session manual`。每次启动前重算来源绑定，退出后校验收据；自动冒烟必须用独立收据并保持 `human_review=pending`。单次attempt最多7200样本，120Hz务必在60秒前、60Hz在120秒前按F5分段（建议每45秒），三分钟观察包含多个连续attempt；出现 `trace_truncated` 不作为完整记录。

## 九格人工验收矩阵

每格包含S1～S6六项子记录；`pending`表示无人完成本合同，不是零分。S4在移动专用窗口中单列阻塞，其余五项可先观察。没有任何一格预填 `pass`。

| 地图 | 方案ID | S1响应 | S2跳跃 | S3急停 | S4开镜 | S5路线 | S6舒适 | 会话/人工总评 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dust II | current | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Dust II | legacy_16 | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Dust II | modern_cs | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Mirage | current | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Mirage | legacy_16 | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Mirage | modern_cs | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Inferno | current | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Inferno | legacy_16 | pending | pending | pending | blocked_scope_context | pending | pending | pending |
| Inferno | modern_cs | pending | pending | pending | blocked_scope_context | pending | pending | pending |

另存一份带会话ID的反馈，不修改冻结计划/历史模板。每项保存：操作者确认/时间、代码和索引SHA、地图/方案/点/输入版本、三次结果、原始会话路径、录像或截图路径（若有）、1～5主观评分（1无法接受，3可用但需修，5满意）、具体问题和偏好。未做评分为 `null`，允许 `blocked`/`aborted`/`observed`，不得从遥测自动生成评分。人工确认只证明有人观察和填写，不授予验证器判断舒适度或原版等价的权力；技术验证成功与人工满意分栏保存。

## 待验收标志与后续切片

| 标志 | 当前状态 | 解除所需证据 |
| --- | --- | --- |
| HUMAN_9_CELLS | pending，0格人工完成 | 上述九格来源匹配的实际会话与操作者明确评分/问题记录 |
| SCOPE_WEAPON_CONTEXT | blocked（移动专用窗口） | 独立真实武器/开镜入口与速度、装备状态记录，再补九格S4 |
| ORIGINAL_ENGINE_FEEL | pending | 固定原机版本/设备的同条件比较；Legacy/Modern仍是候选名称 |
| FREQUENCY_PRECISION | pending，已有偏差保留 | 各目标原容差与60/120Hz落点/时序比较，独立裁定残余差异 |
| AUTHOR_CANDIDATE_ADOPTION | NO-GO，未自动采用 | 更广接触/姿态/动态支撑及落地伤害/相机证据与明确采用裁定 |
| FULL_ROUTES_AI_MATCH_FPS | pending | 出生点完整路线、AI共享规则/难度、最新头18场、连续人工三图及逐图70%FPS |
| MOVEMENT_5_MENU_PACKAGE | frozen | Movement-4明确裁定及后续授权；本矩阵或自动验证不能解冻 |

下一片先完成最新索引/观察入口的来源与手动保存核查，再进行九格S1/S2/S3/S5/S6人工观察；S4保持独立待验。此文件本身是准备合同，无新增原机试玩、人工评分、完整原生或比赛成绩。
