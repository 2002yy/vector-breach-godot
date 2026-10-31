# R50 死亡拆弹者交互残留诊断

本片只增加作者诊断和审计文档，没有修改生产AI、比赛harness、地图、资源或正式Current。诊断退出0表示**已知缺陷被复现**，不是产品PASS；两份作者GDS不加入原生通过门闸。

## 观察与独立规则缺口

Mirage CT/1701第1回合末20秒：存活CT2/5距弹分别约34.63/47.32m，剩余路径105/187节点；随后节点减少，CT2进入交战，CT5在不足10秒时无kit而保枪，未采样到拆弹。这个回合只能解释为长路、战斗和保枪，不能用它证明拆弹卡死，也不能把零拆弹统计归因于下述候选。

独立调用链：`TacticalBotBrain._begin_defuse`将全局交互owner记为`ai`，本地置`_bomb_interacting`；死亡后`tick`在交互清理前返回；`TacticalActor`死亡发信号后延迟释放，没有取消自己的交互；`CombatSandbox._on_actor_killed`仅处理携弹者，拆弹者不携带已安装C4。另一CT受`is_objective_interacting()`阻止，玩家更新也跳过非player owner。`RoundManager._process`继续倒计时，交互进度只由Main玩家分支或AI交互tick推进。

已有TacticalBomb测试覆盖正常CT拆弹和死亡T掉弹回收接替，C4Device覆盖取消/生命周期；未覆盖死亡CT拆弹接替。

## 最小诊断与证据边界

作者入口`tools/authoring/probe_dead_defuser.gd`使用空SceneTree、假CharacterBody3D与真实RoundManager；`DeadDefuserBrainFixture.gd`继承真实brain，仅覆盖移动和停止。先通过真实方法开始拆弹并推进1秒，再设置`is_dead=true`，调用死者真实tick、另一CT真实目标函数和RoundManager时钟。结果为owner仍ai、交互停在1秒、第二CT未开始、炸弹钟40→39.75秒。

第一次外部脚本在顶层继承brain，编译期无法解析autoload RoundManager；失败日志`probe.log`保留，未将它计成功。改变加载时序，在deferred run确认autoload存在后动态load独立fixture，0.594秒退出0且无错误。可复用res路径另一次短运行日志/收据为`probe-reusable.log/json`；所有证据在`D:/AgentGamePipeline/evidence/r50-20261031/defuse-audit/`，汇总`review.json`。

这是模拟死亡标志的真实规则函数复现，尚非实际伤害/死亡信号全链，玩家锁定仅由源码验证；没有Main、模型、地图、GPU或实际比赛因果证明。诊断不写用户设置、不替换原生测试。

## 下一批修复合同

经典参考另核对[ReGameDLL_CS固定提交的拆弹实现](https://github.com/rehlds/ReGameDLL_CS/blob/5329d22101e0a1dc15bc4ff7c89995f97a119702/regamedll/dlls/ggrenade.cpp#L1023)：这是CS1.6兼容社区实现，不是Valve官方CS2源码。该实现绑定具体拆弹者，只限制该角色速度，按其工具包设置新的5/10秒截止时间；中断清除角色、进度与截止时间，炸弹端独立检查续期/落地条件。由此推导本项目修复应有明确owner生命周期与独立失效回收；没有做原客户端实测，也不将其全部规则直接套到CS:GO/CS2。来源blob与行段记录在本批classic-reference.json。

1. 用实际TacticalActor伤害链杀死正在拆弹的AI，保留另一CT，证明当前残留；添加真实失败回归后再改生产。
2. 明确交互绑定具体actor身份，死亡/释放只取消该actor拥有的交互，不能任意队员死亡都清全局。另一CT应按自身kit重新开始，不能继承死者进度。
3. 验证玩家与AI之间取消/接替、不同kit、越界/离开、回合重开与菜单暂停；对象释放、旧回合引用和旧owner不得串场。
4. 修复后将known-bug detector改成明确的行为回归或保留历史诊断并标过期，不让旧“缺陷复现退出0”混入产品通过门闸。生产改变后按合同跑原生完整套件，另定受影响比赛重验范围。

## 相邻本地输入owner边界

只读确认另一条独立数据流：Main约348行用全局`is_objective_interacting()`否定`combat_enabled`，没有检查owner。每帧将该值传入`player.set_movement_enabled`并控制射击/开镜/装备使用分支，武器换弹也据此暂停；`PlayerController.set_movement_enabled(false)`会立即清水平速度。`_can_accept_weapon_management`同样用全局交互禁武器管理。因而AI正常安装/拆弹时，本地活玩家也会被禁移动及这些战斗动作；`set_controls_enabled`仍true，不能笼统说全部输入/视角冻结。只有viewmodel动作提示已经按owner==player过滤，未防止前述门闸。

这是确定的源码数据流候选，尚未运行Main实际输入复现，也不由静止玩家比赛验收覆盖。下一片应在AI正常安装与拆弹时，分别验证本地移动/射击/换弹/切枪仍可用，而本地自己交互时保留相应限制；不能以简单移除全局保护同时破坏本地交互。与死亡owner残留相关但需独立失败测试，不在本批改生产。
