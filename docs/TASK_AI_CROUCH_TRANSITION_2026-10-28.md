# AI 导航蹲姿转交战修复

基线 `eda13b6`，R35。复用真实 TacticalActor / TacticalBotBrain 夹具：先走带 crouch/quiet/precise 的实际导航边，再进入 Modern AWP 横移或 Current 战术刀追击。原实现出现四条失败：横移保留导航蹲姿，AWP/刀追击使用旧姿态解析首帧速度，显式战斗蹲姿没有及时参与运动限速。失败原始日志保存在本机 `D:/AgentGamePipeline/evidence/radar-ai-transition-20261028/ai/before-fix.log`。

原因：`_update_combat_stance` 只更新计时器，步枪横移没有同步 actor 蹲姿；刀追击在运动后才同步。修复在战斗姿态计时器更新后、任何交战运动前同步 `_crouch_active`，使路线姿态退出、显式战斗蹲姿仍生效；静止/阻挡分支原有重置及重新应用保持。

新增8项断言覆盖两种路线进入交战、首帧真实限速、显式战斗蹲姿。定向359项通过；现有Brain lint分类与数量完全保持（56项旧债），测试文件无lint错误且已格式化。完整TacticalBot及整合套件结果见根交付收据。生产参数、原版几何和玩家默认方案保持。

限制：此处保留既有战斗蹲姿策略，不解决低顶空间里是否允许站起的全局姿态/导航约束。真实地图低顶转角、拥堵、完整AI地空运动、难度和整场比赛仍需独立验收；本夹具不是三图人工试玩或18场比赛。
