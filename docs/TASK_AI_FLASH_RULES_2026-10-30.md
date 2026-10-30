# R46 AI 闪光规则

基线5887573。共享FlashExposure保留现有18m距离、正面/背面曝光和持续时间函数；爆点逐接收者按眼位、实际朝向及世界碰撞遮挡。玩家仍用实际Camera3D，AI用get_eye_position和当前角色朝向。接收者和投掷物/投掷者RID以完整数组赋值，避免Godot属性数组副本导致自遮挡。友方与自闪不受友伤开关过滤。

TacticalActor保存与玩家相同的强度衰减，重置清除。AI强度大于0.05时无法视觉获取目标，射击入口同时阻止已缓存目标开火，包含后撤射击；后撤瞄准使用最后已知位置，避免受闪期间继续跟踪敌人真实位置。声音、已有任务及移动继续，未新增难度策略。不是CS原版闪光模型等价声明，部分闪光采取离散视觉门闸，听觉盲射及渐进准确度留待后续设计。

TacticalBombTestRunner新增--flash-only及全套集成fixture：真实闪光影响AI、视觉门闸、缓存射击不消耗弹药、自闪/友方、墙阻挡、重叠闪光保留强度/时长、受闪后撤瞄准记忆方向、重置、到期、朝向/距离函数。旧GrenadeProjectile同fixture红exit1，新版绿exit0。原生全套由主代理统一运行，未冒充CI。

证据：D:/AgentGamePipeline/evidence/r46-20261030/flash。focused.log最终绿；old-projectile-red.log旧投掷物反例；debug.log保留初始自遮挡定位。生产范围：FlashExposure/GrenadeProjectile/TacticalActor/TacticalBotBrain，无原资产/地图/Current移动改变。无渲染/UI变化。
